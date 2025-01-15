--[[
MIT License

Copyright (c) 2022-2025 Dan Uznanski

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
]]

local vornmath = {}

-- loadstring gets folded into load in later versions (5.2+)
---@diagnostic disable-next-line: deprecated
local load = loadstring or load

-- these are used to name generic parameters for functions that accept a different
-- number of arguments based on type

local LETTERS = {'a','b','c','d','e','f','g','h','i','j','k','l','m','n','o','p','q'}

-- prefixes for types that use different storage types

local SCALAR_PREFIXES = {
  boolean = 'b',
  number = '',
  complex = 'c',
  quat = 'q'
}

vornmath.utils = {}
vornmath.bakeries = {}
vornmath.metabakeries = {}
vornmath.metatables = {}
vornmath.metameta = {
  __index = function(_, thing)
    -- process the thing to get the name.
    -- the name should just be the first word of the name.
    local name = string.match(thing, '[^_]+')
    return function(...) return vornmath.utils.bakeByCall(name, ...)(...) end
  end
}

vornmath.utils.bakerymeta = {
  __index = function(bakeries, name)
    for _,metabakery in pairs(vornmath.metabakeries) do
      local bakery = metabakery(name)
      if bakery then
        bakeries[name] = bakery
        return bakery
      end
    end
  end
}

setmetatable(vornmath.bakeries, vornmath.utils.bakerymeta)

function vornmath.utils.hasBakery(function_name, types)
  local available_bakeries = vornmath.bakeries[function_name]
  if not available_bakeries then return nil end
  for _, bakery in ipairs(available_bakeries) do
    if bakery.signature_check(types) then return bakery end
  end
  return false
end

local function buildProxies(function_name, types)
  local built_name = '_' .. function_name
  if not rawget(vornmath, function_name) then
    local existing_name = built_name
    local gmt = vornmath.utils.getmetatable
    vornmath[function_name] = function(...) return gmt(select(1, ...))[existing_name](...) end
  end
  for i,type_name in ipairs(types) do
    local existing_name = built_name
    local next_name = existing_name .. '_' .. type_name
    local select_index = i + 1
    if i == #types then
      break
    end
    built_name = next_name
    if not rawget(vornmath.metatables[type_name], existing_name) then
      vornmath.metatables[type_name][existing_name] = function(...) return vornmath.utils.getmetatable(select(select_index, ...))[next_name](...) end
    end
  end
  vornmath.metatables[types[#types]][built_name] = vornmath[function_name .. '_' .. table.concat(types, '_')]
end

function vornmath.utils.bake(function_name, types)
  local bakery = vornmath.utils.hasBakery(function_name, types)
  if bakery == nil then error("unknown vornmath function `" .. function_name .. "`.") end
  if bakery == false then error('vornmath function `' .. function_name .. '` does not accept types `' .. table.concat(types, ', ') .. '`.') end
  local name = function_name .. '_' .. table.concat(types, '_')
  if rawget(vornmath, name) then return vornmath[name] end
  ---@diagnostic disable-next-line: need-check-nil, undefined-field
  local result = bakery.create(types)
  vornmath[name] = result
  buildProxies(function_name, types)
  return result
end

function vornmath.utils.bakeByCall(name, ...)
  local types = {}
  for i = 1, select('#', ...) do
    types[i] = vornmath.utils.type(select(i, ...))
  end
  return vornmath.utils.bake(name, types)
end

function vornmath.utils.findTypeByData(shape, dim, storage)
  if shape == 'scalar' then dim = 1 end
  for typename, meta in pairs(vornmath.metatables) do
    if meta.vm_storage == storage and meta.vm_shape == shape then
      if type(dim) == 'number' then
        if meta.vm_dim == dim then
          return typename
        end
      else -- type(dim) == 'table'
        local matches = true
        for i,k in ipairs(dim) do
          if meta.vm_dim[i] ~= k then matches = false end
        end
        if matches then return typename end
      end
    end
  end
end

function vornmath.utils.returnType(function_name, types)
  local bakery = vornmath.utils.hasBakery(function_name, types)
  if bakery == nil then error("unknown vornmath function `" .. function_name .. "`.") end
  if bakery == false then error('vornmath function `' .. function_name .. '` does not accept types `' .. table.concat(types, ', ') .. '`.') end
  ---@diagnostic disable-next-line: need-check-nil, undefined-field
  return bakery.return_type(types)
end

function vornmath.utils.componentWiseReturnOnlys(function_name, arity, force_output_storage)
  return {
    signature_check = function(types)
      if #types > arity then
        -- since we're targeting a specific arity only nils after that
        for i, typename in ipairs(types) do
          if i > arity and typename ~= 'nil' then return false end
        end
      end
      local big_type = vornmath.utils.componentWiseConsensusType(types, force_output_storage)
      if not big_type then return false end
      local full_types = {}
      for i, typename in ipairs(types) do
        full_types[i] = typename
      end
      full_types[arity + 1] = big_type
      if vornmath.utils.hasBakery(function_name, full_types) then
        for i = #types + 1, arity + 1 do -- fill out all the rest of the types thing with nil until I get there
          types[i] = 'nil'
        end
        return true
      end
    end,
    create = function(types)
      local big_type = vornmath.utils.componentWiseConsensusType(types, force_output_storage)
      local full_types = {}
      local letters = {}
      for i = 1,arity do
        full_types[i] = types[i]
        letters[i] = LETTERS[i]
      end
      full_types[arity + 1] = big_type
      local f = vornmath.utils.bake(function_name, full_types)
      local construct = vornmath.utils.bake(big_type, {})
      local letter_glom = table.concat(letters, ', ')
      local code = [[
        local f = select(1, ...)
        local construct = select(2, ...)
        return function(]] .. letter_glom .. [[)
          return f(]] .. letter_glom .. [[, construct())
        end
      ]]
      return load(code)(f, construct)
    end,
    return_type = function(types)
      return vornmath.utils.componentWiseConsensusType(types, force_output_storage)
    end
  }
end

function vornmath.utils.componentWiseConsensusType(types, force_output_storage)
  local shape, dim, storage
  for _, typename in ipairs(types) do
    local meta = vornmath.metatables[typename]
    if meta.vm_shape == 'vector' then
      if shape and (shape ~= 'vector' and shape ~= 'scalar') then return nil end
      if dim and dim ~= meta.vm_dim then return nil end
      shape = meta.vm_shape
      dim = meta.vm_dim
    elseif meta.vm_shape == 'matrix' then
      if shape and (shape ~= 'matrix' and shape ~= 'scalar') then return nil end
      if dim and (dim[1] ~= meta.vm_dim[1] or dim[2] ~= meta.vm_dim[2]) then return nil end
      shape = meta.vm_shape
      dim = meta.vm_dim
    elseif meta.vm_shape == 'scalar' then
      if not shape then shape = 'scalar' end
    elseif meta.vm_shape == 'string' then -- strings aren't allowed
      return nil
    end
  end
  if force_output_storage then
    storage = force_output_storage
  else
    storage = vornmath.utils.consensusStorage(types)
  end
  return vornmath.utils.findTypeByData(shape, dim, storage)
end

vornmath.utils.vm_meta = {
  __index = function(vm, index)
    -- is this supposed to be a base proxy or a fully qualified function?
    local is_fully_qualified = string.find(index, '_')
    if is_fully_qualified then
      -- do the stuff needed to bake; this is a split...
      local types = {}
      for match in string.gmatch(index, '[^_]+') do
        table.insert(types,match)
      end
      local name = table.remove(types, 1)
      -- safety: make sure the name I'm about to make in the bakery is the same as the one I just passed in.
      local rebuilt_index = name .. '_' .. table.concat(types, '_')
      if rebuilt_index ~= index then error("invalid vornmath function signature `" .. index .. "` (should probably be `" .. rebuilt_index .."`).") end
      -- return the baked object even if it doesn't land in the expected name.
      return vm.utils.bake(name, types)
    else
      -- instead, bake *only* the proxy.
      if not vm.bakeries[index] then error("unknown vornmath function `" .. index .. "`.") end
      local proxy_index = '_' .. index
      vm[index] = function(...) return vm.utils.getmetatable(select(1, ...))[proxy_index](...) end
      return vm[index]
    end
  end
}

setmetatable(vornmath, vornmath.utils.vm_meta)

function vornmath.utils.type(obj)
  local mt = getmetatable(obj)
  return (mt and mt.vm_type) or type(obj)
end

function vornmath.utils.getmetatable(obj)
  local mt = getmetatable(obj)
  if mt and mt.vm_type then
    return mt
  else
    return vornmath.metatables[type(obj)]
  end
end

vornmath.utils.CONSENSUS_TABLE = { -- this hierarchy is in alphabetical order:
-- it will try checking CT['complex']['number'], but not CT['number']['complex']
  complex = {
    number = 'complex',
    quat = 'quat'
  },
  number = {
    quat = 'quat'
  }

}

do
  local function consensusStoragePair(a, b)
    if a == b then return a end
    if a > b then a,b = b,a end
    local sub_table = vornmath.utils.CONSENSUS_TABLE[a]
    if not sub_table then return nil end -- I don't have one
    return sub_table[b]
  end

  function vornmath.utils.consensusStorage(types)
    local consensus_size = 0
    local consensus_type
    for _,typename in ipairs(types) do
      if typename ~= 'nil' then
        local storage = vornmath.metatables[typename].vm_storage
        if not consensus_type then
          consensus_type = storage
        else
          consensus_type = consensusStoragePair(consensus_type, storage)
        end
      end
    end
    return consensus_type
  end
end

-- Swizzle

local swizzle_characters_to_indices = {x = 1, y = 2, z = 3, w = 4}

local swizzle_alternate_spellings = {
  {x = 'x', y = 'y', z = 'z', w = 'w'},
  {r = 'x', g = 'y', b = 'z', a = 'w'},
  {s = 'x', t = 'y', p = 'z', q = 'w'}
}

function vornmath.utils.swizzleRespell(swizzle)
  local exemplar = swizzle:sub(1,1)
  for _,alphabet in ipairs(swizzle_alternate_spellings) do
    if alphabet[exemplar] then
      local letters = {}
      for i = 1,#swizzle do
        letters[i] = alphabet[swizzle:sub(i,i)]
        if not letters[i] then error("Invalid swizzle string: " .. swizzle) end
      end
      return table.concat(letters, '')
    end
  end
  error("Invalid swizzle string: " .. swizzle)
end

function vornmath.utils.swizzleReadBakery(function_name)
  if function_name:sub(1,11) ~= 'swizzleRead' then return false end -- not a swizzle read
  local swizzle_string = function_name:sub(12)
  local target_dimension = #swizzle_string
  if target_dimension < 1 or target_dimension > 4 then return false end -- can't make vectors this big
  local min_dimension = 2
  local swizzle_indices = {}
  for k = 1,#swizzle_string do
    local letter = swizzle_string:sub(k,k)
    local index = swizzle_characters_to_indices[letter]
    if not index then return false end -- not a legal index
    table.insert(swizzle_indices, index)
    min_dimension = math.max(min_dimension, index)
  end
  if target_dimension == 1 then
    -- this is a single index swizzle, I don't have to do anything fancy to get tables out of my upvalues
    local source_index = swizzle_indices[1]
    return {
      {
        signature_check = function(types)
          if #types < 2 then return false end
          local source = vornmath.metatables[types[1]]
          local target = vornmath.metatables[types[2]]
          if source.vm_shape ~= 'vector' or source.vm_dim < min_dimension or
             target.vm_shape ~= 'scalar' or source.vm_storage ~= target.vm_storage
          then
            return false
          end
          types[3] = nil
          return true
        end,
        create = function(types)
          local fill = vornmath.utils.bake('fill', {types[2], types[2]})
          return function(source, target)
            return fill(target, source[source_index])
          end
        end,
        return_type = function(types) return types[2] end
      },
      {
        signature_check = function(types)
          if #types < 1 then return false end
          local source = vornmath.metatables[types[1]]
          if source.vm_shape ~= 'vector' or source.vm_dim < min_dimension then return false end
          if not types[2] then types[2] = 'nil' end
          return types[2] == 'nil'
        end,
        create = function(types)
          local source_metatable = vornmath.metatables[types[1]]
          local construct = vornmath.utils.bake(source_metatable.vm_storage, {})
          local read = vornmath.utils.bake(function_name, {types[1], source_metatable.vm_storage})
          return function(source)
            return read(source, construct())
          end
        end,
        return_type = function(types) return vornmath.metatables[types[1]].vm_source end
      }
    }
  else
    return {
      {
        signature_check = function(types)
          if #types < 2 then return false end
          local source = vornmath.metatables[types[1]]
          local target = vornmath.metatables[types[2]]
          if source.vm_shape ~= 'vector' or source.vm_dim < min_dimension or
             target.vm_shape ~= 'vector' or target.vm_dim ~= target_dimension or
             source.vm_storage ~= target.vm_storage
          then
            return false
          end
          types[3] = nil
          return true
        end,
        create = function(types)
          local storage_type = vornmath.metatables[types[1]].vm_storage
          local big_fill = vornmath.utils.bake('fill', {types[2], types[2]})
          local little_fill = vornmath.utils.bake('fill', {storage_type, storage_type})
          local make_scratch = vornmath.utils.bake(types[2], {})
          local scratch = make_scratch()
          local fill_targets = {}
          for s,t in ipairs(swizzle_indices) do
            local fill_command = "scratch[" .. s .. "] = little_fill(scratch[" .. s .. "], source[" .. t .. "])"
            table.insert(fill_targets, fill_command)
          end
          local function_text = [[
            local big_fill = select(1, ...)
            local little_fill = select(2, ...)
            local scratch = select(3, ...)
            return function(source, target)
              ]] .. table.concat(fill_targets, '\n') .. [[
              return big_fill(target, scratch)
            end]]
          return load(function_text)(big_fill, little_fill, scratch)
        end,
        return_type = function(types) return types[2] end
      },
      {
        signature_check = function(types)
          if #types < 1 then return false end
          local source = vornmath.metatables[types[1]]
          if source.vm_shape ~= 'vector' or source.vm_dim < min_dimension then return false end
          if not types[2] then types[2] = 'nil' end
          return types[2] == 'nil'
        end,
        create = function(types)
          local source_metatable = vornmath.metatables[types[1]]
          local target_type = vornmath.utils.findTypeByData('vector', target_dimension, source_metatable.vm_storage)
          local construct = vornmath.utils.bake(target_type, {})
          local read = vornmath.utils.bake(function_name, {types[1], target_type})
          return function(source)
            return read(source, construct())
          end
        end,
        return_type = function(types) return vornmath.metatables[types[1]].vm_storage end
      }
    }
  end
end

table.insert(vornmath.metabakeries, vornmath.utils.swizzleReadBakery)

function vornmath.utils.swizzleGetter(t, k)
  if type(k) ~= 'string' then return nil end
  local mt = getmetatable(t)
  if not mt.getters[k] then
    local real_k = vornmath.utils.swizzleRespell(k)
    mt.getters[k] = vornmath.utils.bake('swizzleRead' .. real_k, {mt.vm_type})
  end
  return mt.getters[k](t)
end

function vornmath.utils.swizzleWriteBakery(function_name)
  if function_name:sub(1,12) ~= 'swizzleWrite' then return false end -- not a swizzle read
  local swizzle_string = function_name:sub(13)
  local target_dimension = #swizzle_string
  if target_dimension < 1 or target_dimension > 4 then return false end -- can't do this much
  local min_dimension = 2
  local swizzle_indices = {}
  for k = 1,#swizzle_string do
    local letter = swizzle_string:sub(k,k)
    local index = swizzle_characters_to_indices[letter]
    if not index then return false end -- not a legal index
    for _,i in ipairs(swizzle_indices) do
      if i == index then return false end -- can't duplicate indices
    end
    table.insert(swizzle_indices, index)
    min_dimension = math.max(min_dimension, index)
  end
  if target_dimension == 1 then
    -- this is a single index swizzle, I don't have to do anything fancy to get tables out of my upvalues
    local source_index = swizzle_indices[1]
    return {
      {
        signature_check = function(types)
          if #types < 2 then return false end
          local lvalue_meta = vornmath.metatables[types[1]]
          local rvalue_meta = vornmath.metatables[types[2]]
          if lvalue_meta.vm_shape ~= 'vector' or lvalue_meta.vm_dim < min_dimension or
             rvalue_meta.vm_shape ~= 'scalar' or
             not vornmath.utils.hasBakery('fill', {lvalue_meta.vm_storage, rvalue_meta.vm_storage})
          then
            return false
          end
          types[3] = nil
          return true
        end,
        create = function(types)
          local lvalue_meta = vornmath.metatables[types[1]]
          local rvalue_meta = vornmath.metatables[types[2]]
          local fill = vornmath.utils.bake('fill', {lvalue_meta.vm_storage, rvalue_meta.vm_storage})
          return function(lvalue, rvalue)
            lvalue[source_index] = fill(lvalue[source_index], rvalue)
          end
        end,
        return_type = function(types) return 'nil' end
      },
    }
  else
    return {
      {
        signature_check = function(types)
          if #types < 2 then return false end
          local lvalue_meta = vornmath.metatables[types[1]]
          local rvalue_meta = vornmath.metatables[types[2]]
          if lvalue_meta.vm_shape ~= 'vector' or lvalue_meta.vm_dim < min_dimension or
             rvalue_meta.vm_shape ~= 'vector' or rvalue_meta.vm_dim ~= target_dimension or
             not vornmath.utils.hasBakery('fill', {lvalue_meta.vm_storage, rvalue_meta.vm_storage})
          then
            return false
          end
          types[3] = nil
          return true
        end,
        create = function(types)
          local lvalue_meta = vornmath.metatables[types[1]]
          local rvalue_meta = vornmath.metatables[types[2]]
          local big_fill = vornmath.utils.bake('fill', {types[2], types[2]})
          local little_fill = vornmath.utils.bake('fill', {lvalue_meta.vm_storage, rvalue_meta.vm_storage})
          local make_scratch = vornmath.utils.bake(types[2], {})
          local scratch = make_scratch()
          local fill_targets = {}
          for s,t in ipairs(swizzle_indices) do
            local fill_command = "lvalue[" .. t .. "] = little_fill(lvalue[" .. t .. "], scratch[" .. s .. "])"
            table.insert(fill_targets, fill_command)
          end
          local function_text = [[
            local big_fill = select(1, ...)
            local little_fill = select(2, ...)
            local scratch = select(3, ...)
            return function(lvalue, rvalue)
              scratch = big_fill(scratch, rvalue)
              ]] .. table.concat(fill_targets, '\n') .. [[
            end]]
          return load(function_text)(big_fill, little_fill, scratch)
        end,
        return_type = function(types) return 'nil' end
      },
    }
  end
end

table.insert(vornmath.metabakeries, vornmath.utils.swizzleWriteBakery)

function vornmath.utils.swizzleSetter(t, k, v)
  local mt = vornmath.utils.getmetatable(t)
  local vmt = vornmath.utils.getmetatable(v)
  if not mt.setters[k] then
    local real_k = vornmath.utils.swizzleRespell(k)
    mt.setters[k] = vornmath.utils.bake('swizzleWrite' .. real_k, {mt.vm_type, vmt.vm_type})
  end
  return mt.setters[k](t, v)
end

-- simple type checkers

function vornmath.utils.justNilTypeCheck(types)
  if not types[1] then
    types[1] = 'nil' -- I have to edit type lists that need to include a nil.
  end
  return types[1] == 'nil'
end

function vornmath.utils.clearingExactTypeCheck(correct_types)
  return function(types)
    for i,t in ipairs(correct_types) do
      if not types[i] then types[i] = 'nil' end
      if types[i] ~= t then return false end
    end
    types[#correct_types + 1] = nil
    return true
  end
end

function vornmath.utils.nilFollowingExactTypeCheck(correct_types)
  return function(types)
    for i,t in ipairs(correct_types) do
      if types[i] ~= t then return false end
    end
    if not types[#correct_types + 1] then
      types[#correct_types + 1] = 'nil'
    end
    return types[#correct_types + 1] == 'nil'
  end
end

-- common bakeries

function vornmath.utils.quatOperatorFromComplex(funcname)
  return {
    signature_check = vornmath.utils.clearingExactTypeCheck({'quat', 'quat'}),
    create = function(types)
      local decompose = vornmath.axisDecompose_quat
      local complex_function = vornmath.utils.bake(funcname, {'complex', 'complex'})
      local fill = vornmath.fill_quat_complex_vec3
      return function(z, result)
        local cpx, axis = decompose(z)
        cpx = complex_function(cpx, cpx)
        return fill(result, cpx, axis)
      end
    end,
    return_type = function(types) return 'quat' end
  }
end

function vornmath.utils.genericConstructor(typename)
  return {
    signature_check = function(types)
      local extended_types = {typename}
      for _,t in ipairs(types) do
        table.insert(extended_types, t)
      end
      if vornmath.utils.hasBakery('fill', extended_types) then
        -- copy any edits to extended_types back
        for i = 2,#extended_types + 1 do -- grab up the nil too
          types[i - 1] = extended_types[i]
        end
        return true
      else
        return false
      end
    end,
    create = function(types)
      local constructor = vornmath.utils.bake(typename, {})
      local fill_types = {typename}
      for _,t in ipairs(types) do table.insert(fill_types, t) end
      local fill = vornmath.utils.bake('fill', fill_types)
      return function(...)
        local result = constructor()
        return fill(result, ...)
      end
    end,
    return_type = function(types) return typename end
  }
end

function vornmath.utils.vectorNilConstructor(storage,d)
  local typename = SCALAR_PREFIXES[storage] .. 'vec' .. d
  return { -- vecd()
    signature_check = vornmath.utils.justNilTypeCheck,
    create = function(types)
      local mt = vornmath.metatables[typename]
      local constructor = vornmath.utils.bake(storage, {})
      return function()
        local result = {}
        for k = 1,d do
          result[k] = constructor()
        end
        return setmetatable(result, mt)
      end
    end,
    return_type = function(types) return typename end
  }
end

function vornmath.utils.matrixNilConstructor(storage,w,h)
  local prefix = SCALAR_PREFIXES[storage]
  local typename = prefix .. 'mat' .. w .. 'x' .. h
  return {
    signature_check = vornmath.utils.justNilTypeCheck,
    create = function(types)
      local mt = vornmath.metatables[typename]
      local vectype = prefix .. 'vec' .. h
      local vec = vornmath.utils.bake(vectype, {})
      local identity_diagonal_length = math.min(w, h)
      local fill = vornmath.implicit_conversions[storage]['number'][2]
      return function()
        local result = setmetatable({}, mt)
        for i = 1,w do
          result[i] = vec()
        end
        for i = 1,identity_diagonal_length do
          result[i][i] = fill(result[i][i], 1)
        end
        return result
      end
    end,
    return_type = function(types) return typename end
  }
end

local COMPONENT_EXPANSION_SHAPES = {
  scalar = '',
  vector = '[col]',
  matrix = '[col][row]',
  ['nil'] = ''
}

local COMPONENT_LOOP_PARTS = {
  vector = {'for col = 1,width do', 'end'},
  matrix = {'for col = 1,width do for row = 1,height do', 'end end'}
}

function vornmath.utils.componentWiseExpander(function_name, pattern, force_output_storage)
  return {
    signature_check = function(types)
      if #types < #pattern + 1 then return false end
      local shortened_types = {}
      local scalar_types = {}
      for i,shape in ipairs(pattern) do
        local meta = vornmath.metatables[types[i]]
        if meta.vm_shape ~= shape then return false end
        table.insert(shortened_types, types[i])
        table.insert(scalar_types, meta.vm_storage)
      end
      local return_type = vornmath.utils.componentWiseConsensusType(shortened_types, force_output_storage)
      if return_type ~= types[#pattern + 1] then return false end
      table.insert(scalar_types, vornmath.metatables[return_type].vm_storage)
      if vornmath.utils.hasBakery(function_name, scalar_types) then
        types[#pattern + 2] = nil
        return true
      end
      return false
    end,
    create = function(types)
      local scalar_types = {}
      local arguments = {}
      local argument_uses = {}
      local last_shape, last_dim
      for i,typename in ipairs(types) do
        local meta = vornmath.metatables[typename]
        table.insert(scalar_types,meta.vm_storage)
        table.insert(arguments, LETTERS[i])
        table.insert(argument_uses, LETTERS[i] .. COMPONENT_EXPANSION_SHAPES[meta.vm_shape])
        last_shape = meta.vm_shape
        last_dim = meta.vm_dim
      end
      local width, height
      if last_shape == 'matrix' then
        width, height = last_dim[1], last_dim[2]
      else -- last_shape == 'vector'
        width = last_dim
      end
      local func = vornmath.utils.bake(function_name, scalar_types)
      local code = [[
        local func, width, height = ...
        return function(]] .. table.concat(arguments, ', ') ..[[)
          ]] .. COMPONENT_LOOP_PARTS[last_shape][1] .. [[
            ]] .. argument_uses[#argument_uses] .. [[ = func(]] .. table.concat(argument_uses, ', ') .. [[)
          ]] .. COMPONENT_LOOP_PARTS[last_shape][2] .. [[
          return ]] .. arguments[#arguments] .. [[
        end
      ]]
      return load(code)(func,width,height)
    end,
    return_type = function(types) return types[#types] end
  }
end

function vornmath.utils.twoMixedScalars(function_name)
  return { -- add(mixed scalars)
    signature_check = function(types)
      local left_meta = vornmath.metatables[types[1]]
      local right_meta = vornmath.metatables[types[2]]
      if left_meta.vm_shape ~= 'scalar' then return false end
      if right_meta.vm_shape ~= 'scalar' then return false end
      local joint_type = vornmath.utils.consensusStorage({types[1], types[2]})
      if types[3] ~= joint_type then return false end
      if not vornmath.utils.hasBakery(function_name, {types[3], types[3], types[3]}) then return false end
      types[4] = nil
      return true
    end,
    create = function(types)
      local final_function = vornmath.utils.bake(function_name, {types[3], types[3], types[3]})
      if types[1] ~= types[3] then
        local left_cast = vornmath.utils.bake(types[3], {types[1]})
        if types[2] ~= types[3] then
          local right_cast = vornmath.utils.bake(types[3], {types[2]})
          return function(a,b,result) return final_function(left_cast(a), right_cast(b), result) end
        else
          return function(a,b,result) return final_function(left_cast(a), b, result) end
        end
      end
      local right_cast = vornmath.utils.bake(types[3], {types[2]})
      return function(a,b,result) return final_function(a, right_cast(b), result) end
    end,
    return_type = function(types)
      return types[3]
    end

  }
end

function vornmath.utils.consensusType(types)
  local storage, shape, dim
  for _,typename in ipairs(types) do
    local meta = vornmath.metatables[typename]
    
  end
end

-- types

vornmath.bakeries.boolean = {
  { -- boolean()
    signature_check = vornmath.utils.justNilTypeCheck,
    create = function(types)
      return function() return false end
    end,
    return_type = function(types) return 'boolean' end
  },
  vornmath.utils.genericConstructor('boolean')
}

vornmath.bakeries.number = {
  { -- number()
    signature_check = vornmath.utils.justNilTypeCheck,
    create = function(types)
      return function() return 0 end
    end,
    return_type = function(types) return 'number' end
  },
  vornmath.utils.genericConstructor('number')
}

vornmath.bakeries.complex = {
  { -- complex()
    signature_check = vornmath.utils.justNilTypeCheck,
    create = function(types)
      local complex_meta = vornmath.metatables.complex
      return function()
        return setmetatable({a = 0, b = 0}, complex_meta)
      end
    end,
    return_type = function(types) return 'complex' end
  },
  vornmath.utils.genericConstructor('complex')
}

vornmath.bakeries.quat = {
  { -- quat()
    signature_check = vornmath.utils.justNilTypeCheck,
    create = function(types)
      local quat_meta = vornmath.metatables.quat
      return function()
        return setmetatable({a = 0, b = 0, c = 0, d = 0}, quat_meta)
      end
    end,
    return_type = function(types) return 'quat' end
  },
  vornmath.utils.genericConstructor('quat')
}

for _,storage in ipairs({'boolean', 'number', 'complex'}) do
  for d = 2,4 do
    vornmath.bakeries[SCALAR_PREFIXES[storage] .. 'vec' .. d] = {
      vornmath.utils.vectorNilConstructor(storage, d),
      vornmath.utils.genericConstructor(SCALAR_PREFIXES[storage] .. 'vec' .. d)
    }
  end
end

for _,storage in ipairs({'number', 'complex'}) do
  for w = 2,4 do
    for h = 2,4 do
      local typename = SCALAR_PREFIXES[storage] .. 'mat' .. w .. 'x' .. h
      vornmath.bakeries[typename] = {
        vornmath.utils.matrixNilConstructor(storage, w, h),
        vornmath.utils.genericConstructor(typename)
      }
    end
  end
end

-- fills (also constructors)

vornmath.bakeries.fill = {
  { -- fill(boolean)
    signature_check = vornmath.utils.nilFollowingExactTypeCheck({'boolean'}),
    create = function(types)
      return function(target) return false end
    end,
    return_type = function(types) return 'boolean' end
  },
  { -- fill(boolean, boolean)
    signature_check = vornmath.utils.clearingExactTypeCheck({'boolean', 'boolean'}),
    create = function(types)
      return function(target, x) return x end
    end,
    return_type = function(types) return 'boolean' end
  },
  { -- fill(number)
    signature_check = vornmath.utils.nilFollowingExactTypeCheck({'number'}),
    create = function(types)
      return function(target) return 0 end
    end,
    return_type = function(types) return 'number' end
  },
  { -- fill(number, number)
    signature_check = vornmath.utils.clearingExactTypeCheck({'number','number'}),
    create = function(types)
      return function(target, x) return x end
    end,
    return_type = function(types) return 'number' end
  },
  { -- fill(number, string[, number])
    signature_check = function(types)
      return types[1] == 'number' and types[2] == 'string'
    end,
    create = function(types)
      return function(target, s, base) return tonumber(s, base) or error("Couldn't convert `" .. s .. "` to number.") end
    end,
    return_type = function(types) return 'number' end
  },
  { -- fill(complex)
    signature_check = vornmath.utils.nilFollowingExactTypeCheck({'complex'}),
    create = function(types)
      return function(z)
        z.a = 0
        z.b = 0
        return z
      end
    end,
    return_type = function(types) return 'complex' end
  },
  { -- fill(complex, number[, nil])
    signature_check = vornmath.utils.nilFollowingExactTypeCheck({'complex','number'}),
    create = function(types)
      return function(z, a)
        z.a = a
        z.b = 0
        return z
      end
    end,
    return_type = function(types) return 'complex' end
  },
  { -- fill(complex, number, number)
    signature_check = vornmath.utils.clearingExactTypeCheck({'complex','number','number'}),
    create = function(types)
      return function(z, a, b)
        z.a = a
        z.b = b
        return z
      end
    end,
    return_type = function(types) return 'complex' end
  },
  { -- fill(complex, complex)
    signature_check = vornmath.utils.clearingExactTypeCheck({'complex','complex'}),
    create = function(types)
      return function(target, z)
        target.a = z.a
        target.b = z.b
        return target
      end
    end,
    return_type = function(types) return 'complex' end
  },
  { -- fill(quat)
    signature_check = vornmath.utils.nilFollowingExactTypeCheck({'quat'}),
    create = function(types)
      return function(z)
        z.a = 0
        z.b = 0
        z.c = 0
        z.d = 0
        return z
      end
    end,
    return_type = function(types) return 'quat' end
  },
  { -- fill(quat, number)
    signature_check = vornmath.utils.nilFollowingExactTypeCheck({'quat','number'}),
    create = function(types)
      return function(z,x)
        z.a = x
        z.b = 0
        z.c = 0
        z.d = 0
        return z
      end
    end,
    return_type = function(types) return 'quat' end
  },
  { -- fill(quat, number, number, number, number)
    signature_check = vornmath.utils.clearingExactTypeCheck({'quat','number','number','number','number'}),
    create = function(types)
      return function(z,a,b,c,d)
        z.a = a
        z.b = b
        z.c = c
        z.d = d
        return z
      end
    end,
    return_type = function(types) return 'quat' end
  },
  { -- fill(quat, complex, nil)
    signature_check = vornmath.utils.nilFollowingExactTypeCheck({'quat','complex'}),
    create = function(types)
      return function(z,x)
        z.a = x.a
        z.b = x.b
        z.c = 0
        z.d = 0
        return z
      end
    end,
    return_type = function(types) return 'quat' end
  },
  { -- fill(quat, complex, complex)
    signature_check = vornmath.utils.clearingExactTypeCheck({'quat','complex','complex'}),
    create = function(types)
      return function(z,x,y)
        z.a = x.a
        z.b = x.b
        z.c = y.a
        z.d = y.b
        return z
      end
    end,
    return_type = function(types) return 'quat' end
  },
  { -- fill(quat, quat)
    signature_check = vornmath.utils.clearingExactTypeCheck({'quat','quat'}),
    create = function(types)
      return function(z,x)
        z.a = x.a
        z.b = x.b
        z.c = x.c
        z.d = x.d
        return z
      end
    end,
    return_type = function(types) return 'quat' end
  },
  { -- fill(quat, axis, angle)
    signature_check = vornmath.utils.clearingExactTypeCheck({'quat','vec3','number'}),
    create = function(types)
      local sin, cos = math.sin, math.cos
      return function(z, axis, angle)
        local halfangle = angle / 2
        local c = cos(halfangle)
        local s = sin(halfangle)
        z.a, z.b, z.c, z.d = c, s * axis[1], s * axis[2], s * axis[3]
        return z
      end
    end,
    return_type = function(types) return 'quat' end
  },
  { -- fill(quat, complex, axis)
    signature_check = vornmath.utils.clearingExactTypeCheck({'quat','complex','vec3'}),
    create = function(types)
      return function(z, cpx, axis)
        z.a, z.b, z.c, z.d = cpx.a, cpx.b * axis[1], cpx.b * axis[2], cpx.b * axis[3]
        return z
      end
    end,
    return_type = function(types) return 'quat' end
  },
  { -- fill(quat, vec3, vec3)
    signature_check = vornmath.utils.clearingExactTypeCheck({'quat','vec3','vec3'}),
    create = function(types)
      local dot = vornmath.utils.bake('dot', {'vec3', 'vec3'})
      local cross = vornmath.utils.bake('cross', {'vec3', 'vec3', 'vec3'})
      local eq = vornmath.utils.bake('eq', {'vec3', 'vec3'})
      local fill = vornmath.utils.bake('fill', {'quat', 'number', 'number', 'number', 'number'})
      local sqrt = vornmath.utils.bake('sqrt', {'quat', 'quat'})
      local normalize = vornmath.utils.bake('normalize', {'vec3', 'vec3'})
      local c = vornmath.vec3()
      local zero = vornmath.vec3()
      return function(q, from, to)
        local d = dot(from, to)
        c = cross(from, to, c)
        if eq(c, zero) and d < 0 then
          -- we need to pick an axis at all.
          if from[1] == 0 and from[2] == 0 then
            return fill(q,0,1,0,0)
          else
            c = fill(c,from[2], -from[1],0)
            c = normalize(c,c)
            return fill(q,0,c[1],c[2],0)
          end
        end
        q = fill(q, d, c[1], c[2], c[3])
        return sqrt(q, q)
      end
    end,
    return_type = function(types) return 'quat' end
  },
  { -- fill(vec)
    signature_check = function(types)
      local first = vornmath.metatables[types[1]]
      if first.vm_shape ~= 'vector' then
        return false
      end
      if not types[2] then types[2] = 'nil' end
      return types[2] == 'nil'
    end,
    create = function(types)
      local d = vornmath.metatables[types[1]].vm_dim
      local storage = vornmath.metatables[types[1]].vm_storage
      local fill = vornmath.utils.bake('fill', {storage, 'nil'})
      return function(v)
        for i = 1,d do
          v[i] = fill(v[i])
        end
        return v
      end
    end,
    return_type = function(types) return types[1] end
  },
  { -- fill(vec, scalar)
    signature_check = function(types)
      local first = vornmath.metatables[types[1]]
      local second = vornmath.metatables[types[2]]
      if first.vm_shape ~= 'vector' then return false end
      if second.vm_shape ~= 'scalar' then return false end
      if not vornmath.utils.hasBakery('fill', {first.vm_storage, second.vm_storage}) then return false end
      if not types[3] then types[3] = 'nil' end
      return types[3] == 'nil'
    end,
    create = function(types)
      local first = vornmath.metatables[types[1]]
      local second = vornmath.metatables[types[2]]
      local fill = vornmath.utils.bake('fill', {first.vm_storage, second.vm_storage})
      local d = vornmath.metatables[types[1]].vm_dim
      return function(v,x)
        for i = 1,d do
          v[i] = fill(v[i],x)
        end
        return v
      end
    end,
    return_type = function(types) return types[1] end
  },
  { -- fill(vec, mixed)
    signature_check = function(types)
      if #types < 2 then return false end
      local first = vornmath.metatables[types[1]]
      if first.vm_shape ~= 'vector' then
        return false
      end
      local casts = vornmath.implicit_conversions[first.vm_storage]
      local d = first.vm_dim
      local input_count = 0
      for i = 2,#types do
        local t = types[i]
        if input_count >= d then return false end -- I have a pattern that's too long
        local mt = vornmath.metatables[t]
        if not casts[mt.vm_storage] then return false end
        if mt.vm_shape == 'scalar' then
          input_count = input_count + 1
        elseif mt.vm_shape == 'vector' then
          input_count = input_count + mt.vm_dim
        elseif mt.vm_shape == 'matrix' then
          input_count = input_count + mt.vm_dim[1] * mt.vm_dim[2]
        end
      end
      return input_count >= d
    end,
    create = function(types)
      -- we'll have to do this the hard way: string loading.
      local arguments = {}
      local full_inputs = {}
      local first = vornmath.metatables[types[1]]
      local d = first.vm_dim
      local implicit_casts = vornmath.implicit_conversions[first.vm_storage]
      local cast_assigns = {}
      for name,_ in pairs(implicit_casts) do
        table.insert(cast_assigns, 'local fill_'.. name .. ' = casts.' .. name .. '[2]')
      end
      local idx = 1
      for i = 2,#types do
        local t = types[i]
        local letter = LETTERS[i] 
        table.insert(arguments, letter)
        local tmt = vornmath.metatables[t]
        if tmt.vm_shape == 'scalar' then
          -- a scalar goes in directly.
          table.insert(full_inputs, 'target[' .. idx .. '] = fill_' .. tmt.vm_storage .. '(target[' .. idx .. '], ' .. letter .. ')')
          idx = idx + 1
        elseif tmt.vm_shape == 'vector' then
          -- a vector goes in by element
          for j = 1,tmt.vm_dim do
            if #full_inputs == d then break end
            table.insert(full_inputs, 'target[' .. idx .. '] = fill_' .. tmt.vm_storage .. '(target[' .. idx .. '], ' .. letter .. '[' .. j .. '])')
            idx = idx + 1
          end
        else -- tmt.vm_shape == 'matrix'
          for j = 1,tmt.vm_dim[1] do
            for k = 1,tmt.vm_dim[2] do
              if #full_inputs == d then break end
              table.insert(full_inputs, 'target[' .. idx .. '] = fill_' .. tmt.vm_storage .. '(target[' .. idx .. '], ' .. letter .. '[' .. j .. '][' .. k .. '])')
              idx = idx + 1
            end
          end
        end
      end
      local cast_glom = table.concat(cast_assigns, '\n')
      local letter_glom = table.concat(arguments, ', ')
      local inputs_glom = table.concat(full_inputs, '\n')
      
      local code = [[
        local casts = select(1, ...)
        ]] .. cast_glom .. [[
        return function(target, ]] .. letter_glom .. [[)
          ]] .. inputs_glom .. [[
          return target
        end
      ]]
      return load(code)(implicit_casts)
    end,
    return_type = function(types) return types[1] end
  },
  { -- fill(matrix)
    signature_check = function(types)
      local first = vornmath.metatables[types[1]]
      if first.vm_shape ~= 'matrix' then
        return false
      end
      if not types[2] then types[2] = 'nil' end
      return types[2] == 'nil'
    end,
    create = function(types)
      local first = vornmath.metatables[types[1]]
      local storage = first.vm_storage
      local dim = first.vm_dim
      local w, h = dim[1], dim[2]
      local nilfill = vornmath.utils.bake('fill', {storage, 'nil'})
      local numfill = vornmath.utils.bake('fill', {storage, 'number'})
      return function(m)
        for x = 1,w do
          for y = 1,h do
            if x == y then
              m[x][y] = numfill(m[x][y], 1)
            else
              m[x][y] = nilfill(m[x][y])
            end
          end
        end
        return m
      end
    end,
    return_type = function(types) return types[1] end
  },
  { -- fill(matrix, scalar)
    signature_check = function(types)
      local first = vornmath.metatables[types[1]]
      local second = vornmath.metatables[types[2]]
      if first.vm_shape ~= 'matrix' then return false end
      if second.vm_shape ~= 'scalar' then return false end
      if not vornmath.utils.hasBakery('fill', {first.vm_storage, second.vm_storage}) then return false end
      if not types[3] then types[3] = 'nil' end
      return types[3] == 'nil'
    end,
    create = function(types)
      local first = vornmath.metatables[types[1]]
      local second = vornmath.metatables[types[2]]
      local nilfill = vornmath.utils.bake('fill', {first.vm_storage})
      local valfill = vornmath.utils.bake('fill', {first.vm_storage, second.vm_storage})
      local dim = first.vm_dim
      local w, h = dim[1], dim[2]
      return function(m,val)
        for x = 1,w do
          for y = 1,h do
            if x == y then
              m[x][y] = valfill(m[x][y], val)
            else
              m[x][y] = nilfill(m[x][y])
            end
          end
        end
        return m
      end
    end,
    return_type = function(types) return types[1] end
  },
  { -- fill(matrix, matrix)
    signature_check = function(types)
      local first = vornmath.metatables[types[1]]
      local second = vornmath.metatables[types[2]]
      if first.vm_shape ~= 'matrix' then return false end
      if second.vm_shape ~= 'matrix' then return false end
      if not vornmath.implicit_conversions[first.vm_storage][second.vm_storage] then return false end
      if not types[3] then types[3] = 'nil' end
      return types[3] == 'nil'
    end,
    create = function(types)
      local first = vornmath.metatables[types[1]]
      local second = vornmath.metatables[types[2]]
      local nilfill = vornmath.utils.bake('fill', {first.vm_storage})
      local valfill = vornmath.implicit_conversions[first.vm_storage][second.vm_storage][2]
      local numfill = vornmath.implicit_conversions[first.vm_storage]['number'][2]
      local dest_dim = first.vm_dim
      local src_dim = second.vm_dim
      local dest_w, dest_h = dest_dim[1], dest_dim[2]
      local src_w, src_h = src_dim[1], src_dim[2]
      return function(dest, src)
        for x = 1,dest_w do
          for y = 1, dest_h do
            if x <= src_w and y <= src_h then
              dest[x][y] = valfill(dest[x][y], src[x][y])
            elseif x == y then
              dest[x][y] = numfill(dest[x][y], 1)
            else
              dest[x][y] = nilfill(dest[x][y])
            end
          end
        end
        return dest
      end
    end,
    return_type = function(types) return types[1] end
  },
  { -- fill(matrix, mixed)
    signature_check = function(types)
      if #types < 2 then return false end
      local first = vornmath.metatables[types[1]]
      if first.vm_shape ~= 'matrix' then
        return false
      end
      local casts = vornmath.implicit_conversions[first.vm_storage]
      local d = first.vm_dim[1] * first.vm_dim[2]
      local input_count = 0
      for i = 2,#types do
        local t = types[i]
        if input_count >= d then return false end -- I have a pattern that's too long
        local mt = vornmath.metatables[t]
        if not casts[mt.vm_storage] then return false end
        if mt.vm_shape == 'scalar' then
          input_count = input_count + 1
        elseif mt.vm_shape == 'vector' then
          input_count = input_count + mt.vm_dim
        else 
          return false
        end
      end
      return input_count >= d
    end,
    create = function(types)
      -- we'll have to do this the hard way: string loading.
      local arguments = {}
      local full_inputs = {}
      local first = vornmath.metatables[types[1]]
      local w,h = first.vm_dim[1], first.vm_dim[2]
      local d = w * h
      local implicit_casts = vornmath.implicit_conversions[first.vm_storage]
      local cast_assigns = {}
      for name,_ in pairs(implicit_casts) do
        table.insert(cast_assigns, 'local fill_'.. name .. ' = casts.' .. name .. '[2]')
      end
      local x,y = 1,1
      for i = 2,#types do
        local t = types[i]
        local letter = LETTERS[i]
        table.insert(arguments, letter)
        local tmt = vornmath.metatables[t]
        if tmt.vm_shape == 'scalar' then
          -- a scalar goes in directly.
          table.insert(full_inputs, 'target[' .. x .. '][' .. y .. '] = fill_' .. tmt.vm_storage .. '(target[' .. x .. '][' .. y .. '], ' .. letter .. ')')
          y = y + 1
          if y > h then
            x = x + 1
            y = 1
          end
        elseif tmt.vm_shape == 'vector' then
          -- a vector goes in by element
          for j = 1,tmt.vm_dim do
            if #full_inputs == d then break end
            table.insert(full_inputs, 'target[' .. x .. '][' .. y .. '] = fill_' .. tmt.vm_storage .. '(target[' .. x .. '][' .. y .. '], ' .. letter .. '[' .. j .. '])')
            y = y + 1
            if y > h then
              x = x + 1
              y = 1
            end
           end
        end
      end
      local cast_glom = table.concat(cast_assigns, '\n')
      local letter_glom = table.concat(arguments, ', ')
      local inputs_glom = table.concat(full_inputs, '\n')

      local code = [[
        local casts = select(1, ...)
        ]] .. cast_glom .. [[
        return function(target, ]] .. letter_glom .. [[)
          ]] .. inputs_glom .. [[
          return target
        end
      ]]
      return load(code)(implicit_casts)
    end,
    return_type = function(types) return types[1] end
  },
  { -- fill(mat3, quat)
    signature_check = vornmath.utils.clearingExactTypeCheck({'mat3x3', 'quat'}),
    create = function(types)
      local sqabs = vornmath.utils.bake('sqabs', {'quat'})
      local fill = vornmath.utils.bake('fill', {'mat3x3', 'number', 'number', 'number', 'number', 'number', 'number', 'number', 'number', 'number'})
      return function(m, q)
        local s = 2 / sqabs(q)
        local bs, cs, ds = q.b * s, q.c * s, q.d * s
        local ab, ac, ad = q.a * bs, q.a * cs, q.a * ds
        local bb, cc, dd = q.b * bs, q.c * cs, q.d * ds
        local bc, cd, bd = q.b * cs, q.c * ds, q.b * ds
        return fill(m, 1 - cc - dd, bc + ad, bd - ac, bc - ad, 1 - bb - dd, cd + ab, bd + ac, cd - ab, 1 - bb - cc)
      end
    end,
    return_type = function(types) return 'mat3x3' end
  },
  { -- fill(mat4, quat)
    signature_check = vornmath.utils.clearingExactTypeCheck({'mat4x4', 'quat'}),
    create = function(types)
      local make_3 = vornmath.utils.bake('fill', {'mat3x3', 'quat'})
      local fill = vornmath.utils.bake('fill', {'mat4x4', 'mat3x3'})
      local scratch = vornmath.mat3()
      return function(m, q)
        return fill(m, make_3(scratch, q))
      end
    end,
    return_type = function(types) return 'mat4x4' end
  }
}

-- arithmetic operators

vornmath.bakeries.add = {
  { -- add(number, number, number)
    signature_check = vornmath.utils.clearingExactTypeCheck({'number', 'number', 'number'}),
    create = function(types)
      return function(x, y) return x + y end
    end,
    return_type = function(types) return 'number' end
  },
  { -- add(complex, complex, complex)
    signature_check = vornmath.utils.clearingExactTypeCheck({'complex', 'complex', 'complex'}),
    create = function(types)
      local fill = vornmath.fill_complex_number_number
      return function(x, y, result)
        return fill(result, x.a + y.a, x.b + y.b)
      end
    end,
    return_type = function(types) return 'complex' end
  },
  { -- add(quat, quat, quat)
    signature_check = vornmath.utils.clearingExactTypeCheck({'quat', 'quat', 'quat'}),
    create = function(types)
      local fill = vornmath.fill_quat_number_number_number_number
      return function(x, y, result)
        return fill(result, x.a + y.a, x.b + y.b, x.c + y.c, x.d + y.d)
      end
    end,
    return_type = function(types) return 'quat' end
  },
  vornmath.utils.componentWiseExpander('add', {'vector', 'scalar'}),
  vornmath.utils.componentWiseExpander('add', {'scalar', 'vector'}),
  vornmath.utils.componentWiseExpander('add', {'vector', 'vector'}),
  vornmath.utils.componentWiseExpander('add', {'matrix', 'scalar'}),
  vornmath.utils.componentWiseExpander('add', {'scalar', 'matrix'}),
  vornmath.utils.componentWiseExpander('add', {'matrix', 'matrix'}),
  vornmath.utils.componentWiseReturnOnlys('add', 2),
  vornmath.utils.twoMixedScalars('add')
}

vornmath.bakeries.unm = {
  { -- unm(number, number)
    signature_check = vornmath.utils.clearingExactTypeCheck({'number', 'number'}),
    create = function(types)
      return function(x) return -x end
    end,
    return_type = function(types) return 'number' end
  },
  { -- unm(complex, complex)
    signature_check = vornmath.utils.clearingExactTypeCheck({'complex', 'complex'}),
    create = function(types)
      local fill = vornmath.fill_complex_number_number
      return function(x, result)
        return fill(result, -x.a, -x.b)
      end
    end,
    return_type = function(types) return 'complex' end
  },
  { -- unm(quat, quat)
    signature_check = vornmath.utils.clearingExactTypeCheck({'quat', 'quat'}),
    create = function(types)
      local fill = vornmath.fill_quat_number_number_number_number
      return function(x, result)
        return fill(result, -x.a, -x.b, -x.c, -x.d)
      end
    end,
    return_type = function(types) return 'quat' end
  },
  vornmath.utils.componentWiseExpander('unm', {'vector'}),
  vornmath.utils.componentWiseExpander('unm', {'matrix'}),
  vornmath.utils.componentWiseReturnOnlys('unm', 1),
}

vornmath.bakeries.sub = {
  { -- sub(number, number)
    signature_check = vornmath.utils.clearingExactTypeCheck({'number', 'number', 'number'}),
    create = function(types)
      return function(x, y) return x - y end
    end,
    return_type = function(types) return 'number' end
  },
  { -- sub(complex, complex)
    signature_check = vornmath.utils.clearingExactTypeCheck({'complex', 'complex', 'complex'}),
    create = function(types)
      local fill = vornmath.fill_complex_number_number
      return function(x, y, result)
        return fill(result, x.a - y.a, x.b - y.b)
      end
    end,
    return_type = function(types) return 'complex' end
  },
  { -- sub(quat, quat)
    signature_check = vornmath.utils.clearingExactTypeCheck({'quat', 'quat', 'quat'}),
    create = function(types)
      local fill = vornmath.fill_quat_number_number_number_number
      return function(x, y, result)
        return fill(result, x.a - y.a, x.b - y.b, x.c - y.c, x.d - y.d)
      end
    end,
    return_type = function(types) return 'quat' end
  },
  vornmath.utils.componentWiseExpander('sub', {'vector', 'scalar'}),
  vornmath.utils.componentWiseExpander('sub', {'scalar', 'vector'}),
  vornmath.utils.componentWiseExpander('sub', {'vector', 'vector'}),
  vornmath.utils.componentWiseExpander('sub', {'matrix', 'scalar'}),
  vornmath.utils.componentWiseExpander('sub', {'scalar', 'matrix'}),
  vornmath.utils.componentWiseExpander('sub', {'matrix', 'matrix'}),
  vornmath.utils.componentWiseReturnOnlys('sub', 2),
  vornmath.utils.twoMixedScalars('sub')
}

vornmath.bakeries.mul = {
  { -- mul(number, number)
    signature_check = vornmath.utils.clearingExactTypeCheck({'number', 'number', 'number'}),
    create = function(types)
      return function(x, y) return x * y end
    end,
    return_type = function(types) return 'number' end
  },
  { -- mul(complex, complex)
    signature_check = vornmath.utils.clearingExactTypeCheck({'complex', 'complex', 'complex'}),
    create = function(types)
      local fill = vornmath.fill_complex_number_number
      return function(x, y, result)
        return fill(result, x.a * y.a - x.b * y.b, x.a * y.b + x.b * y.a)
      end
    end,
    return_type = function(types) return 'complex' end
  },
  { -- mul(quat, quat)
    signature_check = vornmath.utils.clearingExactTypeCheck({'quat', 'quat', 'quat'}),
    create = function(types)
      local fill = vornmath.fill_quat_number_number_number_number
      return function(x, y, result)
        return fill(result, x.a * y.a - x.b * y.b - x.c * y.c - x.d * y.d,
                            x.a * y.b + x.b * y.a + x.c * y.d - x.d * y.c,
                            x.a * y.c - x.b * y.d + x.c * y.a + x.d * y.b,
                            x.a * y.d + x.b * y.c - x.c * y.b + x.d * y.a)
      end
    end,
    return_type = function(types) return 'quat' end
  },
  { -- mul(matrix, matrix, matrix)}
    signature_check = function(types)
      if #types < 3 then return false end
      local left = vornmath.metatables[types[1]]
      local right = vornmath.metatables[types[2]]
      local result = vornmath.metatables[types[3]]
      if (left.vm_shape ~= 'matrix' or
        right.vm_shape ~= 'matrix' or
        result.vm_shape ~= 'matrix' or
        left.vm_dim[1] ~= right.vm_dim[2] or
        left.vm_dim[2] ~= result.vm_dim[2] or
        result.vm_dim[1] ~= right.vm_dim[1] or
        not vornmath.utils.hasBakery('mul', {left.vm_storage, right.vm_storage, result.vm_storage})
        or not vornmath.utils.hasBakery('add', {result.vm_storage, result.vm_storage, result.vm_storage})
      )
      then
        return false
      end
      types[4] = nil
      return true
    end,
    create = function(types)
      local left_type = vornmath.metatables[types[1]]
      local right_type = vornmath.metatables[types[2]]
      local result_type = vornmath.metatables[types[3]]
      local width = result_type.vm_dim[1]
      local height = result_type.vm_dim[2]
      local depth = left_type.vm_dim[1]
      local mul = vornmath.utils.bake('mul', {left_type.vm_storage, right_type.vm_storage, result_type.vm_storage})
      local add = vornmath.utils.bake('add', {result_type.vm_storage, result_type.vm_storage, result_type.vm_storage})
      local make = vornmath.utils.bake(types[3], {'number'})
      local make_scratch = vornmath.utils.bake(result_type.vm_storage, {})
      local fill = vornmath.utils.bake('fill', {types[3], types[3]})
      return function(left, right, result)
        local temp = make(0)
        local value_scratch = make_scratch()
        for x = 1, width do
          for y = 1, height do
            for z = 1, depth do
              value_scratch = mul(left[z][y], right[x][z], value_scratch)
              temp[x][y] = add(temp[x][y], value_scratch, temp[x][y])
            end
          end
        end
        fill(result, temp)
        return result
      end
    end,
    return_type = function(types) return types[3] end
  },
  { -- mul(vector, matrix, vector)}
    signature_check = function(types)
      if #types < 3 then return false end
      local left = vornmath.metatables[types[1]]
      local right = vornmath.metatables[types[2]]
      local result = vornmath.metatables[types[3]]
      if (left.vm_shape ~= 'vector' or
        right.vm_shape ~= 'matrix' or
        result.vm_shape ~= 'vector' or
        left.vm_dim ~= right.vm_dim[2] or
        result.vm_dim ~= right.vm_dim[1] or
        not vornmath.utils.hasBakery('mul', {left.vm_storage, right.vm_storage, result.vm_storage})
        or not vornmath.utils.hasBakery('add', {result.vm_storage, result.vm_storage, result.vm_storage})
      )
      then
        return false
      end
      types[4] = nil
      return true
    end,
    create = function(types)
      local left_type = vornmath.metatables[types[1]]
      local right_type = vornmath.metatables[types[2]]
      local result_type = vornmath.metatables[types[3]]
      local width = result_type.vm_dim
      local depth = right_type.vm_dim[2]
      local mul = vornmath.utils.bake('mul', {left_type.vm_storage, right_type.vm_storage, result_type.vm_storage})
      local add = vornmath.utils.bake('add', {result_type.vm_storage, result_type.vm_storage, result_type.vm_storage})
      local make = vornmath.utils.bake(types[3], {'number'})
      local make_scratch = vornmath.utils.bake(result_type.vm_storage, {})
      local fill = vornmath.utils.bake('fill', {types[3], types[3]})
      return function(left, right, result)
        local temp = make(0)
        local value_scratch = make_scratch()
        for x = 1, width do
          for z = 1, depth do
            value_scratch = mul(left[z], right[x][z], value_scratch)
            temp[x] = add(temp[x], value_scratch, temp[x])
          end
        end
        fill(result, temp)
        return result
      end
    end,
    return_type = function(types) return types[3] end
  },
  { -- mul(matrix, vector, vector)}
    signature_check = function(types)
      if #types < 3 then return false end
      local left = vornmath.metatables[types[1]]
      local right = vornmath.metatables[types[2]]
      local result = vornmath.metatables[types[3]]
      if (left.vm_shape ~= 'matrix' or
        right.vm_shape ~= 'vector' or
        result.vm_shape ~= 'vector' or
        left.vm_dim[1] ~= right.vm_dim or
        left.vm_dim[2] ~= result.vm_dim or
        not vornmath.utils.hasBakery('mul', {left.vm_storage, right.vm_storage, result.vm_storage})
        or not vornmath.utils.hasBakery('add', {result.vm_storage, result.vm_storage, result.vm_storage})
      )
      then
        return false
      end
      types[4] = nil
      return true
    end,
    create = function(types)
      local left_type = vornmath.metatables[types[1]]
      local right_type = vornmath.metatables[types[2]]
      local result_type = vornmath.metatables[types[3]]
      local height = result_type.vm_dim
      local depth = left_type.vm_dim[1]
      local mul = vornmath.utils.bake('mul', {left_type.vm_storage, right_type.vm_storage, result_type.vm_storage})
      local add = vornmath.utils.bake('add', {result_type.vm_storage, result_type.vm_storage, result_type.vm_storage})
      local make = vornmath.utils.bake(types[3], {'number'})
      local make_scratch = vornmath.utils.bake(result_type.vm_storage, {})
      local fill = vornmath.utils.bake('fill', {types[3], types[3]})
      return function(left, right, result)
        local temp = make(0)
        local value_scratch = make_scratch()
        for y = 1, height do
          for z = 1, depth do
            value_scratch = mul(left[z][y], right[z], value_scratch)
            temp[y] = add(temp[y], value_scratch, temp[y])
          end
        end
        fill(result, temp)
        return result
      end
    end,
    return_type = function(types) return types[3] end
  },
  { -- mul(matrix, matrix)
    signature_check = function(types)
      if #types < 2 then return false end
      if #types > 2 then
        -- only nils after
        for i, typename in ipairs(types) do
          if i > 2 and typename ~= 'nil' then return false end
        end
      end
      local left = vornmath.metatables[types[1]]
      local right = vornmath.metatables[types[2]]
      if left.vm_shape ~= 'matrix' or right.vm_shape ~= 'matrix' then
        return false
      end
      local consensus_storage = vornmath.utils.consensusStorage({left.vm_storage, right.vm_storage})
      local result_type = vornmath.utils.findTypeByData('matrix', {right.vm_dim[1], left.vm_dim[2]}, consensus_storage)
      if vornmath.utils.hasBakery('mul', {types[1], types[2], result_type}) then
        types[3] = 'nil'
        types[4] = nil
        return true
      end
    end,
    create = function(types)
      local left = vornmath.metatables[types[1]]
      local right = vornmath.metatables[types[2]]
      local consensus_storage = vornmath.utils.consensusStorage({left.vm_storage, right.vm_storage})
      local result_type = vornmath.utils.findTypeByData('matrix', {right.vm_dim[1], left.vm_dim[2]}, consensus_storage)
      local make = vornmath.utils.bake(result_type, {})
      local action = vornmath.utils.bake('mul', {types[1], types[2], result_type})
      return function(a, b)
        local result = make()
        return action(a, b, result)
      end
    end,
    return_type = function(types)
      local left = vornmath.metatables[types[1]]
      local right = vornmath.metatables[types[2]]
      local consensus_storage = vornmath.utils.consensusStorage({left.vm_storage, right.vm_storage})
      return vornmath.utils.findTypeByData('matrix', {right.vm_dim[1], left.vm_dim[2]}, consensus_storage)
    end
  },
  { -- mul(vector, matrix)
    signature_check = function(types)
      if #types < 2 then return false end
      if #types > 2 then
        -- only nils after
        for i, typename in ipairs(types) do
          if i > 2 and typename ~= 'nil' then return false end
        end
      end
      local left = vornmath.metatables[types[1]]
      local right = vornmath.metatables[types[2]]
      if left.vm_shape ~= 'vector' or right.vm_shape ~= 'matrix' then
        return false
      end
      local consensus_storage = vornmath.utils.consensusStorage({left.vm_storage, right.vm_storage})
      local result_type = vornmath.utils.findTypeByData('vector', right.vm_dim[1], consensus_storage)
      if vornmath.utils.hasBakery('mul', {types[1], types[2], result_type}) then
        types[3] = 'nil'
        types[4] = nil
        return true
      end
    end,
    create = function(types)
      local left = vornmath.metatables[types[1]]
      local right = vornmath.metatables[types[2]]
      local consensus_storage = vornmath.utils.consensusStorage({left.vm_storage, right.vm_storage})
      local result_type = vornmath.utils.findTypeByData('vector', right.vm_dim[1], consensus_storage)
      local make = vornmath.utils.bake(result_type, {})
      local action = vornmath.utils.bake('mul', {types[1], types[2], result_type})
      return function(a, b)
        local result = make()
        return action(a, b, result)
      end
    end,
    return_type = function(types)
      local left = vornmath.metatables[types[1]]
      local right = vornmath.metatables[types[2]]
      local consensus_storage = vornmath.utils.consensusStorage({left.vm_storage, right.vm_storage})
      return vornmath.utils.findTypeByData('vector', right.vm_dim[1], consensus_storage)
    end
  },
  { -- mul(matrix, vector)
    signature_check = function(types)
      if #types < 2 then return false end
      if #types > 2 then
        -- only nils after
        for i, typename in ipairs(types) do
          if i > 2 and typename ~= 'nil' then return false end
        end
      end
      local left = vornmath.metatables[types[1]]
      local right = vornmath.metatables[types[2]]
      if left.vm_shape ~= 'matrix' or right.vm_shape ~= 'vector' then
        return false
      end
      local consensus_storage = vornmath.utils.consensusStorage({left.vm_storage, right.vm_storage})
      local result_type = vornmath.utils.findTypeByData('vector', left.vm_dim[2], consensus_storage)
      if vornmath.utils.hasBakery('mul', {types[1], types[2], result_type}) then
        types[3] = 'nil'
        types[4] = nil
        return true
      end
    end,
    create = function(types)
      local left = vornmath.metatables[types[1]]
      local right = vornmath.metatables[types[2]]
      local consensus_storage = vornmath.utils.consensusStorage({left.vm_storage, right.vm_storage})
      local result_type = vornmath.utils.findTypeByData('vector', left.vm_dim[2], consensus_storage)
      local make = vornmath.utils.bake(result_type, {})
      local action = vornmath.utils.bake('mul', {types[1], types[2], result_type})
      return function(a, b)
        local result = make()
        return action(a, b, result)
      end
    end,
    return_type = function(types)
      local left = vornmath.metatables[types[1]]
      local right = vornmath.metatables[types[2]]
      local consensus_storage = vornmath.utils.consensusStorage({left.vm_storage, right.vm_storage})
      return vornmath.utils.findTypeByData('matrix', {right.vm_dim[1], left.vm_dim[2]}, consensus_storage)
    end
  },
  { -- mul(quat, vec3, vec3)
    signature_check = vornmath.utils.clearingExactTypeCheck({'quat', 'vec3', 'vec3'}),
    create = function(types)
      local mul = vornmath.utils.bake('mul', {'quat', 'quat', 'quat'})
      local conj = vornmath.utils.bake('conj', {'quat', 'quat'})
      local qfill = vornmath.utils.bake('fill', {'quat', 'number', 'number', 'number', 'number'})
      local vfill = vornmath.utils.bake('fill', {'vec3', 'number', 'number', 'number'})
      local c = vornmath.quat()
      local p = vornmath.quat()
      return function(q, v, result)
        c = conj(q, c)
        p = qfill(p, 0, v[1], v[2], v[3])
        p = mul(q, p, p)
        p = mul(p, c, p)
        return vfill(result, p.b, p.c, p.d)
      end
    end,
    return_type = function(types) return 'vec3' end
  },
  { -- mul(quat, vec3)
  signature_check = vornmath.utils.clearingExactTypeCheck({'quat', 'vec3'}),
  create = function(types)
    local create = vornmath.utils.bake('vec3', {})
    local f = vornmath.utils.bake('mul', {'quat', 'vec3', 'vec3'})
    return function(q, v)
      local result = create()
      return f(q, v, result)
    end
  end,
  return_type = function(types) return 'vec3' end
},
  vornmath.utils.componentWiseExpander('mul', {'vector', 'scalar'}),
  vornmath.utils.componentWiseExpander('mul', {'scalar', 'vector'}),
  vornmath.utils.componentWiseExpander('mul', {'vector', 'vector'}),
  vornmath.utils.componentWiseExpander('mul', {'matrix', 'scalar'}),
  vornmath.utils.componentWiseExpander('mul', {'scalar', 'matrix'}),
  vornmath.utils.componentWiseReturnOnlys('mul', 2),
  vornmath.utils.twoMixedScalars('mul')
}

vornmath.bakeries.div = {
  { -- div(number, number)
    signature_check = vornmath.utils.clearingExactTypeCheck({'number', 'number', 'number'}),
    create = function(types)
      return function(x, y) return x / y end
    end,
    return_type = function(types) return 'number' end
  },
  { -- div(complex, number)
    signature_check = vornmath.utils.clearingExactTypeCheck({'complex', 'number', 'complex'}),
    create = function(types)
      local fill = vornmath.fill_complex_number_number
      return function(x, y, result)
        return fill(result, x.a / y, x.b / y)
      end
    end,
    return_type = function(types) return 'complex' end
  },
  { -- div(quat, number)
    signature_check = vornmath.utils.clearingExactTypeCheck({'quat', 'number', 'quat'}),
    create = function(types)
      local fill = vornmath.fill_quat_number_number_number_number
      return function(x, y, result)
        return fill(result, x.a / y, x.b / y, x.c / y, x.d / y)
      end
    end,
    return_type = function(types) return 'quat' end
  },
  { -- div(scalar, non-number scalar, combined)
    -- div I do special because unlike the other things, the straightforward one isn't the matched-types one.
    signature_check = function(types)
      local first = vornmath.metatables[types[1]]
      local second = vornmath.metatables[types[2]]
      if first.vm_shape ~= 'scalar' then return false end
      if second.vm_shape ~= 'scalar' then return false end
      if second.vm_shape == 'number' then return false end
      local combined_type = vornmath.utils.consensusStorage({types[1], types[2]})
      if types[3] ~= combined_type then return false end
      if vornmath.utils.hasBakery('sqabs', {types[2]}) and
         vornmath.utils.hasBakery('mul', {types[1], types[2], types[3]}) and
         vornmath.utils.hasBakery('conj', {types[2]}) and
         vornmath.utils.hasBakery('div', {types[3], 'number', types[3]}) then
        return true
      end
    end,
    create = function(types)
      local sqabs = vornmath.utils.bake('sqabs', {types[2]})
      local mul =  vornmath.utils.bake('mul', {types[1], types[2], types[3]})
      local conj = vornmath.utils.bake('conj', {types[2]})
      local div = vornmath.utils.bake('div', {types[3], 'number', types[3]})
      return function(x, y, result)
        local denominator = sqabs(y)
        result = mul(x, conj(y), result)
        result = div(result, denominator, result)
        return result
      end
    end,
    return_type = function(types) return types[3] end
  },
  vornmath.utils.componentWiseExpander('div', {'vector', 'scalar'}),
  vornmath.utils.componentWiseExpander('div', {'scalar', 'vector'}),
  vornmath.utils.componentWiseExpander('div', {'vector', 'vector'}),
  vornmath.utils.componentWiseExpander('div', {'matrix', 'scalar'}),
  vornmath.utils.componentWiseExpander('div', {'scalar', 'matrix'}),
  vornmath.utils.componentWiseExpander('div', {'matrix', 'matrix'}),
  vornmath.utils.componentWiseReturnOnlys('div', 2),
}

vornmath.bakeries.mod = {
  { -- mod(number, number)
    signature_check = vornmath.utils.clearingExactTypeCheck({'number', 'number'}),
    create = function(types)
      return function(x, y) return x % y end
    end,
    return_type = function(types) return 'number' end
  },
  vornmath.utils.componentWiseExpander('mod', {'vector', 'scalar'}),
  vornmath.utils.componentWiseExpander('mod', {'scalar', 'vector'}),
  vornmath.utils.componentWiseExpander('mod', {'vector', 'vector'}),
  vornmath.utils.componentWiseExpander('mod', {'matrix', 'scalar'}),
  vornmath.utils.componentWiseExpander('mod', {'scalar', 'matrix'}),
  vornmath.utils.componentWiseExpander('mod', {'matrix', 'matrix'}),
  vornmath.utils.componentWiseReturnOnlys('mod', 2),

}

vornmath.bakeries.pow = {
  { -- pow(number, number)
    signature_check = vornmath.utils.clearingExactTypeCheck({'number', 'number'}),
    create = function(types)
-- pow disappears in later versions (5.2+) because ^ replaces it
---@diagnostic disable-next-line: deprecated
      return math.pow or function(x,y) return x^y end
    end,
    return_type = function(types) return 'number' end
  },
  { -- pow(complex, complex, complex)
    signature_check = vornmath.utils.clearingExactTypeCheck({'complex', 'complex', 'complex'}),
    create = function(types)
      local fill = vornmath.fill_complex_number_number
      local log = vornmath.log_complex_nil_nil
      local exp = math.exp
      local sin = math.sin
      local cos = math.cos
      local mul = vornmath.mul_complex_complex
      return function(x, y, result)
        if y.a == 0 and y.b == 0 then return fill(result, 1, 0) end
        if x.a == 0 and x.b == 0 then return fill(result, 0, 0) end
        local w = log(x)
        w = mul(w, y, w)
        local size = exp(w.a)
        return fill(result, size * cos(w.b), size * sin(w.b))
      end
    end,
    return_type = function(types) return 'complex' end
  },
  { -- pow(quat, quat, quat)
    signature_check = vornmath.utils.clearingExactTypeCheck({'quat','quat','quat'}),
    create = function(types)
      local fill = vornmath.fill_quat_number_number_number_number
      local decompose = vornmath.axisDecompose_quat
      local log = vornmath.log_complex_nil_complex
      local exp = vornmath.exp_quat_quat
      local mul = vornmath.mul_quat_quat_quat
      local regenerate = vornmath.quat_complex_vec3
      local eq = vornmath.eq_quat_number
      return function(base, exponent, result)
        if eq(exponent, 0) then return fill(result, 1, 0, 0, 0) end
        if eq(base, 0) then return fill(result, 0, 0, 0, 0) end
        local c, a = decompose(base)
        if c.b == 0 then
          local _
          _, a = decompose(exponent)
          -- since log can come up with complex results for real inputs,
          -- I want to make sure that it does so in line with the other quaternion.
          -- this is how we do that.
        end
        c = log(c, nil, c)
        local logbase = regenerate(c, a)
        result = mul(logbase, exponent, result)
        result = exp(result, result)
        return result
      end
    end,
    return_type = function(types) return 'quat' end
  },
  vornmath.utils.componentWiseExpander('pow', {'vector', 'scalar'}),
  vornmath.utils.componentWiseExpander('pow', {'scalar', 'vector'}),
  vornmath.utils.componentWiseExpander('pow', {'vector', 'vector'}),
  vornmath.utils.componentWiseReturnOnlys('pow', 2),
  vornmath.utils.twoMixedScalars('pow'),
}

vornmath.bakeries.eq = {
  { -- eq(boolean, boolean)
    signature_check = vornmath.utils.clearingExactTypeCheck({'boolean', 'boolean'}),
    create = function(types)
      return function(x, y) return x == y end
    end,
    return_type = function(types) return 'boolean' end
  },
  { -- eq(number, number)
    signature_check = vornmath.utils.clearingExactTypeCheck({'number', 'number'}),
    create = function(types)
      return function(x, y) return x == y end
    end,
    return_type = function(types) return 'boolean' end
  },
  { -- eq(number, complex)
    signature_check = vornmath.utils.clearingExactTypeCheck({'number', 'complex'}),
    create = function(types)
      return function(x, y)
        return x == y.a and 0 == y.b
      end
    end,
    return_type = function(types) return 'boolean' end
  },
  { -- eq(complex, number)
    signature_check = vornmath.utils.clearingExactTypeCheck({'complex', 'number'}),
    create = function(types)
      return function(x, y)
        return x.a == y and x.b == 0
      end
    end,
    return_type = function(types) return 'boolean' end
  },
  { -- eq(complex, complex)
    signature_check = vornmath.utils.clearingExactTypeCheck({'complex', 'complex'}),
    create = function(types)
      return function(x, y)
        return x.a == y.a and x.b == y.b
      end
    end,
    return_type = function(types) return 'boolean' end
  },
  { -- eq(number, quat)
    signature_check = vornmath.utils.clearingExactTypeCheck({'number', 'quat'}),
    create = function(types)
      return function(x, y)
        return x == y.a and y.b == 0 and y.c == 0 and y.d == 0
      end
    end,
    return_type = function(types) return 'boolean' end
  },
  { -- eq(complex, quat)
    signature_check = vornmath.utils.clearingExactTypeCheck({'complex', 'quat'}),
    create = function(types)
      return function(x, y)
        return x.a == y.a and x.b == y.b and y.c == 0 and y.d == 0
      end
    end,
    return_type = function(types) return 'boolean' end
  },
  { -- eq(quat, quat)
    signature_check = vornmath.utils.clearingExactTypeCheck({'quat', 'quat'}),
    create = function(types)
      return function(x, y)
        return x == y.a and y.b == 0 and x.c == y.c and x.d == y.d
      end
    end,
    return_type = function(types) return 'boolean' end
  },
  { -- eq(quat, number)
    signature_check = vornmath.utils.clearingExactTypeCheck({'quat', 'number'}),
    create = function(types)
      return function(x, y)
        return x.a == y and x.b == 0 and x.c == 0 and x.d == 0
      end
    end,
    return_type = function(types) return 'boolean' end
  },
  { -- eq(quat, complex)
    signature_check = vornmath.utils.clearingExactTypeCheck({'quat', 'complex'}),
    create = function(types)
      return function(x, y)
        return x.a == y.a and x.b == y.b and x.c == 0 and x.d == 0
      end
    end,
    return_type = function(types) return 'boolean' end
  },

  { -- eq(vector, vector)
    signature_check = function(types)
      if #types < 2 then return false end
      local first = vornmath.metatables[types[1]]
      local second = vornmath.metatables[types[2]]
      if first.vm_shape ~= 'vector' or second.vm_shape ~= 'vector' then return false end
      if first.vm_dim ~= second.vm_dim then return false end
      if vornmath.utils.hasBakery('eq', {first.vm_storage, second.vm_storage}) then
        types[3] = nil
        return true
      end
    end,
    create = function(types)
      local first = vornmath.metatables[types[1]]
      local second = vornmath.metatables[types[2]]
      local equals = vornmath.utils.bake('eq', {first.vm_storage, second.vm_storage})
      local length = first.vm_dim
      return function(a, b)
        for i = 1,length do
          if not equals(a[i], b[i]) then return false end
        end
        return true
      end
    end,
    return_type = function(types) return 'boolean' end
  },
  { -- eq(matrix, matrix)
    signature_check = function(types)
      if #types < 2 then return false end
      local first = vornmath.metatables[types[1]]
      local second = vornmath.metatables[types[2]]
      if first.vm_shape ~= 'matrix' or second.vm_shape ~= 'matrix' then return false end
      if first.vm_dim[1] ~= second.vm_dim[1] or first.vm_dim[2] ~= second.vm_dim[2] then return false end
      if vornmath.utils.hasBakery('eq', {first.vm_storage, second.vm_storage}) then
        types[3] = nil
        return true
      end
    end,
    create = function(types)
      local first = vornmath.metatables[types[1]]
      local second = vornmath.metatables[types[2]]
      local equals = vornmath.utils.bake('eq', {first.vm_storage, second.vm_storage})
      local width = first.vm_dim[1]
      local height = first.vm_dim[2]
      return function(a, b)
        for x = 1, width do
          for y = 1, height do
            if not equals(a[x][y], b[x][y]) then return false end
          end
        end
        return true
      end
    end,
    return_type = function(types) return 'boolean' end
  }
}

vornmath.bakeries.tostring = {
  { -- tostring(boolean)
    signature_check = vornmath.utils.clearingExactTypeCheck({'boolean'}),
    create = function(types)
      return tostring
    end,
    return_type = function(types) return 'string' end
  },
  { -- tostring(number)
    signature_check = vornmath.utils.clearingExactTypeCheck({'number'}),
    create = function(types)
      return tostring
    end,
    return_type = function(types) return 'string' end
  },
  { -- tostring(complex)
    signature_check = vornmath.utils.clearingExactTypeCheck({'complex'}),
    create = function(types)
      return function(z)
        return tostring(z.a).. ' + ' .. tostring(z.b) .. 'i'
      end
    end,
    return_type = function(types) return 'string' end
  },
  { -- tostring(quat)
    signature_check = vornmath.utils.clearingExactTypeCheck({'quat'}),
    create = function(types)
      return function(z)
        return tostring(z.a).. ' + ' .. tostring(z.b) .. 'i + ' .. tostring(z.c) .. 'j + ' .. tostring(z.d) .. 'k'
      end
    end,
    return_type = function(types) return 'string' end
  },
  { -- tostring(vector)
    signature_check = function(types)
      local mt = vornmath.metatables[types[1]]
      return mt.vm_shape == 'vector'
    end,
    create = function(types)
      return function(v)
        local things = {}
        for _,x in ipairs(v) do
          table.insert(things, tostring(x))
        end
        return "<" .. table.concat(things, ', ') .. ">"
      end
    end,
    return_type = function(types) return 'string' end
  },
  { -- tostring(matrix)
    signature_check = function(types)
      local mt = vornmath.metatables[types[1]]
      return mt.vm_shape == 'matrix'
    end,
    create = function(types)
      local meta = vornmath.metatables[types[1]]
      local width = meta.vm_dim[1]
      local height = meta.vm_dim[2]
      return function(a)
        local rows = {}
        for y = 1, height do
          local row = {}
          for x = 1, width do
            row[x] = tostring(a[x][y])
          end
          rows[y] = table.concat(row, ', ')
        end
        return table.concat(rows, '\n')
      end
    end
  }
}

-- angle and trig

vornmath.bakeries.rad = {
  { -- rad(number)
    signature_check = vornmath.utils.nilFollowingExactTypeCheck({'number'}),
    create = function(types) return math.rad end,
    return_type = function(types) return 'number' end
  },
  { -- rad(other scalar)
    signature_check = function(types)
      if types[1] ~= types[2] or
         vornmath.metatables[types[1]].vm_shape ~= 'scalar' or
         not vornmath.utils.hasBakery('mul', {types[1], 'number', types[2]}) then
        return false
      end
      types[3] = nil
      return true
    end,
    create = function(types)
      local scale = math.pi / 180
      local mul = vornmath.utils.bake('mul', {types[1], 'number', types[2]})
      return function(phi, r)
        return mul(phi, scale, r)
      end
    end
  },
  vornmath.utils.componentWiseExpander('rad', {'vector'}),
  vornmath.utils.componentWiseReturnOnlys('rad', 1)
}

vornmath.bakeries.deg = {
  { -- deg(number)
    signature_check = vornmath.utils.nilFollowingExactTypeCheck({'number'}),
    create = function(types) return math.deg end,
    return_type = function(types) return 'number' end
  },
  { -- deg(other scalar)
    signature_check = function(types)
      if types[1] ~= types[2] or
         vornmath.metatables[types[1]].vm_shape ~= 'scalar' or
         not vornmath.utils.hasBakery('mul', {types[1], 'number', types[2]}) then
        return false
      end
      types[3] = nil
      return true
    end,
    create = function(types)
      local scale = 180 / math.pi
      local mul = vornmath.utils.bake('mul', {types[1], 'number', types[2]})
      return function(phi, r)
        return mul(phi, scale, r)
      end
    end
  },
  vornmath.utils.componentWiseExpander('deg', {'vector'}),
  vornmath.utils.componentWiseReturnOnlys('deg', 1)
}

vornmath.bakeries.sin = {
  { -- sin(number)
    signature_check = vornmath.utils.nilFollowingExactTypeCheck({'number'}),
    create = function(types) return math.sin end,
    return_type = function(types) return 'number' end
  },
  { -- sin(complex, complex)
    signature_check = vornmath.utils.clearingExactTypeCheck({'complex','complex'}),
    create = function(types)
      local sinh = vornmath.utils.bake('sinh', {'complex', 'complex'})
      local fill = vornmath.utils.bake('fill', {'complex', 'number', 'number'})
      return function(z, r)
        r = fill(r, -z.b, z.a)
        r = sinh(r,r)
        return fill(r, r.b, -r.a)
      end
    end
  },
  vornmath.utils.componentWiseExpander('sin', {'vector'}),
  vornmath.utils.quatOperatorFromComplex('sin'),
  vornmath.utils.componentWiseReturnOnlys('sin', 1)
}

vornmath.bakeries.cos = {
  { -- cos(number)
  signature_check = vornmath.utils.nilFollowingExactTypeCheck({'number'}),
  create = function(types) return math.cos end,
  return_type = function(types) return 'number' end
  },
  { -- cos(complex, complex)
    signature_check = vornmath.utils.clearingExactTypeCheck({'complex','complex'}),
    create = function(types)
      local cosh = vornmath.utils.bake('cosh', {'complex', 'complex'})
      local fill = vornmath.utils.bake('fill', {'complex', 'number', 'number'})
      return function(z, r)
        r = fill(r, -z.b, z.a)
        return cosh(r, r)
      end
    end
  },
  vornmath.utils.componentWiseExpander('cos', {'vector'}),
  vornmath.utils.quatOperatorFromComplex('cos'),
  vornmath.utils.componentWiseReturnOnlys('cos', 1)
}

vornmath.bakeries.tan = {
  { -- tan(number)
    signature_check = vornmath.utils.nilFollowingExactTypeCheck({'number'}),
    create = function(types) return math.tan end,
    return_type = function(types) return 'number' end
  },
  { -- tan(complex, complex)
    signature_check = vornmath.utils.clearingExactTypeCheck({'complex','complex'}),
    create = function(types)
      local tanh = vornmath.utils.bake('tanh', {'complex', 'complex'})
      local fill = vornmath.utils.bake('fill', {'complex', 'number', 'number'})
      return function(z, r)
        r = fill(r, -z.b, z.a)
        r = tanh(r,r)
        return fill(r, r.b, -r.a)
      end
    end
  },

  vornmath.utils.componentWiseExpander('tan', {'vector'}),
  vornmath.utils.quatOperatorFromComplex('tan'),
  vornmath.utils.componentWiseReturnOnlys('tan', 1)
}

vornmath.bakeries.asin = {
  { -- asin(number)
    signature_check = vornmath.utils.nilFollowingExactTypeCheck({'number'}),
    create = function(types)
      return math.asin
    end,
    return_type = function(types) return 'number' end
  },
  { -- asin(complex, complex)
    signature_check = vornmath.utils.clearingExactTypeCheck({'complex','complex'}),
    create = function(types)
      local mul = vornmath.utils.bake('mul', {'complex', 'complex', 'complex'})
      local asinh = vornmath.utils.bake('asinh', {'complex', 'complex'})
      local i = vornmath.complex(0, 1)
      local negi = -i
      return function(z, r)
        r = mul(z, i, r)
        r = asinh(r, r)
        return mul(r, negi, r)
      end

    end,
    return_type = function(types) return 'complex' end
  },
  vornmath.utils.componentWiseExpander('asin', {'vector'}),
  vornmath.utils.quatOperatorFromComplex('asin'),
  vornmath.utils.componentWiseReturnOnlys('asin', 1)
}

vornmath.bakeries.acos = {
  { -- acos(number)
    signature_check = vornmath.utils.clearingExactTypeCheck({'number'}),
    create = function(types)
      return math.acos
    end,
    return_type = function(types) return 'number' end
  },
  { -- acos(complex)
    signature_check = vornmath.utils.clearingExactTypeCheck({'complex','complex'}),
    create = function(types)
      -- TODO: large and non-finite results
      local sqrt = vornmath.utils.bake('sqrt', {'complex', 'complex'})
      local asinh = vornmath.utils.bake('asinh', {'number'})
      local atan = vornmath.utils.bake('atan', {'number', 'number'})
      local sub = vornmath.utils.bake('sub', {'number', 'complex', 'complex'})
      local add = vornmath.utils.bake('add', {'number', 'complex', 'complex'})
      local fill = vornmath.utils.bake('fill', {'complex', 'number', 'number'})

      local x = vornmath.complex()
      local y = vornmath.complex()
      return function(z, result)
        x = sub(1, z, x)
        x = sqrt(x, x)
        y = add(1, z, y)
        y = sqrt(y, y)
        return fill(result, 2 * atan(x.a, y.a), asinh(y.a * x.b - y.b * x.a))

      end
    end,
    return_type = function(types) return 'complex' end
  },
  vornmath.utils.componentWiseExpander('acos', {'vector'}),
  vornmath.utils.quatOperatorFromComplex('acos'),
  vornmath.utils.componentWiseReturnOnlys('acos', 1)
}

vornmath.bakeries.atan = {
  { -- atan(number)
    signature_check = vornmath.utils.nilFollowingExactTypeCheck({'number'}),
    create = function(types)
      return math.atan
    end,
    return_type = function(types) return 'number' end
  },
  { -- atan(number, number)
    signature_check = vornmath.utils.clearingExactTypeCheck({'number', 'number'}),
    create = function(types)
---@diagnostic disable-next-line: deprecated
      return math.atan2 or math.atan
    end,
    return_type = function(types) return 'number' end
  },
  { -- atan(complex, nil, complex)
    signature_check = vornmath.utils.clearingExactTypeCheck({'complex','nil','complex'}),
    create = function(types)
      local mul = vornmath.utils.bake('mul', {'complex', 'complex', 'complex'})
      local atanh = vornmath.utils.bake('atanh', {'complex', 'complex'})
      local i = vornmath.complex(0, 1)
      local negi = -i
      return function(z, _, r)
        r = mul(z, i, r)
        r = atanh(r, r)
        return mul(r, negi, r)
      end
    end,
    return_type = function(types) return 'complex' end
  },
  { -- atan(complex, complex, complex)
    signature_check = vornmath.utils.clearingExactTypeCheck({'complex','complex','complex'}),
    create = function(types)
      local atan1 = vornmath.utils.bake('atan', {'complex', 'nil', 'complex'})
      local pi = math.pi
      local pi2 = pi / 2
      local add = vornmath.utils.bake('add', {'complex', 'number', 'complex'})
      local div = vornmath.utils.bake('div', {'complex', 'complex', 'complex'})
      local eq = vornmath.utils.bake('eq', {'complex', 'number'})
      local fill = vornmath.utils.bake('fill', {'complex', 'number'})
      return function(n, d, r)
        if eq(d, 0) then
          if n.a > 0 or n.a == 0 and n.b > 0 then
            return fill(r,pi2)
          elseif n.a < 0 or n.a == 0 and n.b < 0 then
            return fill(r,-pi2)
          else -- n == 0
            return 0
          end
        end
        local correction
        if d.a >= 0 then
          correction = 0
        elseif n.a >= 0 then -- d.a < 0 and...
          correction = pi
        else -- d.a < 0 and n.a < 0
          correction = -pi
        end
        r = div(n, d, r)
        r = atan1(r, nil, r)
        return add(r, correction, r)
      end
    end,
    return_type = function(types) return 'complex' end
  },
  { -- atan(quat, nil, quat)
    signature_check = vornmath.utils.clearingExactTypeCheck({'quat','nil','quat'}),
    create = function(types)
      local axisDecompose = vornmath.utils.bake('axisDecompose', {'quat', 'complex', 'vec3'})
      local atanComplex = vornmath.utils.bake('atan', {'complex', 'nil', 'complex'})
      local fill = vornmath.utils.bake('fill', {'quat', 'complex', 'vec3'})
      local z = vornmath.complex()
      local v = vornmath.vec3()
      return function(q, _, r)
        z, v = axisDecompose(q, z, v)
        z = atanComplex(z, nil, z)
        return fill(r, z, v)
      end
    end,
    return_type = function(types) return 'quat' end
  },
  { -- atan(quat, quat, quat)
    signature_check = vornmath.utils.clearingExactTypeCheck({'quat','quat','quat'}),
    create = function(types)
      local atan1 = vornmath.utils.bake('atan', {'quat', 'nil', 'quat'})
      local pi = math.pi
      local pi2 = pi / 2
      local add = vornmath.utils.bake('add', {'quat', 'number', 'quat'})
      local div = vornmath.utils.bake('div', {'quat', 'quat', 'quat'})
      local eq = vornmath.utils.bake('eq', {'quat', 'number'})
      local fill = vornmath.utils.bake('fill', {'quat', 'number'})
      return function(n, d, r)
        if eq(d, 0) then
          if (n.a > 0 or
              n.a == 0 and n.b > 0 or
              n.a == 0 and n.b == 0 and n.c > 0 or
              n.a == 0 and n.b == 0 and n.c == 0 and n.d > 0) then
            return fill(r,pi2)
          elseif n.a < 0 or n.b < 0 or n.c < 0 or n.d < 0 then
            return fill(r,-pi2)
          else -- n == 0
            return 0
          end
        end
        local correction
        if d.a >= 0 then
          correction = 0
        elseif n.a >= 0 then -- d.a < 0 and...
          correction = pi
        else -- d.a < 0 and n.a < 0
          correction = -pi
        end
        r = div(n, d, r)
        r = atan1(r, nil, r)
        return add(r, correction, r)
      end
    end,
    return_type = function(types) return 'quat' end
  },
  vornmath.utils.componentWiseExpander('atan', {'vector', 'vector'}),
  vornmath.utils.componentWiseExpander('atan', {'vector', 'nil'}),
  vornmath.utils.componentWiseReturnOnlys('atan', 2),
  vornmath.utils.twoMixedScalars('atan'),
}

vornmath.bakeries.sinh = {
  {
    signature_check = vornmath.utils.nilFollowingExactTypeCheck({'number'}),
    create = function(types)
---@diagnostic disable-next-line: deprecated
      if math.sinh then return math.sinh end
      local exp = math.exp
      return function(x)
        return (exp(x) - exp(-x)) / 2
      end
    end,
    return_type = function(types) return 'number' end
  },
  {
    signature_check = vornmath.utils.nilFollowingExactTypeCheck({'complex', 'complex'}),
    create = function(types)
      local cos = math.cos
      local sin = math.sin
      local cosh = vornmath.utils.bake('cosh', {'number'})
      local sinh = vornmath.utils.bake('sinh', {'number'})
      local fill = vornmath.utils.bake('fill', {'complex', 'number', 'number'})
      return function(z, r)
        return fill(r, cos(z.b) * sinh(z.a), sin(z.b) * cosh(z.a))
      end
    end,
    return_type = function(types) return 'complex' end
  },
  vornmath.utils.componentWiseExpander('sinh', {'vector'}),
  vornmath.utils.quatOperatorFromComplex('sinh'),
  vornmath.utils.componentWiseReturnOnlys('sinh', 1)

}

vornmath.bakeries.cosh = {
  {
    signature_check = vornmath.utils.nilFollowingExactTypeCheck({'number'}),
    create = function(types)
---@diagnostic disable-next-line: deprecated
      if math.cosh then return math.cosh end
      local exp = math.exp
      return function(x)
        return (exp(x) + exp(-x)) / 2
      end
    end,
    return_type = function(types) return 'number' end
  },
  {
    signature_check = vornmath.utils.nilFollowingExactTypeCheck({'complex', 'complex'}),
    create = function(types)
      local cos = math.cos
      local sin = math.sin
      local cosh = vornmath.utils.bake('cosh', {'number'})
      local sinh = vornmath.utils.bake('sinh', {'number'})
      local fill = vornmath.utils.bake('fill', {'complex', 'number', 'number'})
      return function(z, r)
        return fill(r, cos(z.b) * cosh(z.a), sin(z.b) * sinh(z.a))
      end
    end,
    return_type = function(types) return 'complex' end
  },
  vornmath.utils.componentWiseExpander('cosh', {'vector'}),
  vornmath.utils.quatOperatorFromComplex('cosh'),
  vornmath.utils.componentWiseReturnOnlys('cosh', 1)

}

vornmath.bakeries.tanh = {
  {
    signature_check = vornmath.utils.nilFollowingExactTypeCheck({'number'}),
    create = function(types)
---@diagnostic disable-next-line: deprecated
      if math.tanh then return math.tanh end
      local exp = math.exp
      return function(x)
        local y = exp(2 * x)
        return (y - 1) / (y + 1)
      end
    end,
    return_type = function(types) return 'number' end
  },
  {
    signature_check = vornmath.utils.nilFollowingExactTypeCheck({'complex', 'complex'}),
    create = function(types)
      local tan = math.tan
      local cosh = vornmath.utils.bake('cosh', {'number'})
      local tanh = vornmath.utils.bake('tanh', {'number'})
      local fill = vornmath.utils.bake('fill', {'complex', 'number', 'number'})
      return function(z, r)
        local tx = tanh(z.a)
        local ty = tan(z.b)
        local cx = 1 / cosh(z.a)
        local txty = tx * ty
        local denom = 1 + txty * txty
        return fill(r, tx * (1 + ty * ty) / denom, ((ty / denom) * cx) * cx)
      end
    end,
    return_type = function(types) return 'complex' end
  },
  vornmath.utils.componentWiseExpander('sinh', {'vector'}),
  vornmath.utils.quatOperatorFromComplex('sinh'),
  vornmath.utils.componentWiseReturnOnlys('sinh', 1)

}

vornmath.bakeries.asinh = {
  { -- asinh(number)
    signature_check = vornmath.utils.nilFollowingExactTypeCheck({'number'}),
    create = function(types)
      return function(x)
        return math.log(x + math.sqrt(x*x + 1))
      end
    end,
    return_type = function(types) return 'number' end
  },
  { -- asinh(complex, complex)
    signature_check = vornmath.utils.clearingExactTypeCheck({'complex','complex'}),
    create = function(types)
      local fill = vornmath.utils.bake('fill', {'complex', 'number', 'number'})
      local sqrt = vornmath.utils.bake('sqrt', {'complex', 'complex'})
      local asinh = vornmath.utils.bake('asinh', {'number'})
      local atan = vornmath.utils.bake('atan', {'number', 'number'})
      local x, y = vornmath.complex(), vornmath.complex()
      return function(z, r)
        x = fill(x, 1 + z.b, -z.a)
        y = fill(y, 1 - z.b, z.a)
        x = sqrt(x, x)
        y = sqrt(y, y)
        return fill(r, asinh(x.a * y.b - y.a * x.b), atan(z.b, x.a * y.a - x.b * y.b))
      end
    end,
    return_type = function(types) return 'complex' end
  },
  vornmath.utils.componentWiseExpander('asinh', {'vector'}),
  vornmath.utils.quatOperatorFromComplex('asinh'),
  vornmath.utils.componentWiseReturnOnlys('asinh', 1)
}

vornmath.bakeries.acosh = {
  { -- acosh(number)
    signature_check = vornmath.utils.nilFollowingExactTypeCheck({'number'}),
    create = function(types)
      return function(x)
        return math.log(x + math.sqrt(x*x - 1))
      end
    end,
    return_type = function(types) return 'number' end
  },
  { -- acosh(complex, complex)
    signature_check = vornmath.utils.clearingExactTypeCheck({'complex','complex'}),
    create = function(types)
      local fill = vornmath.utils.bake('fill', {'complex', 'number', 'number'})
      local sqrt = vornmath.utils.bake('sqrt', {'complex', 'complex'})
      local asinh = vornmath.utils.bake('asinh', {'number'})
      local atan = vornmath.utils.bake('atan', {'number', 'number'})
      local x, y = vornmath.complex(), vornmath.complex()
      return function(z, r)
        x = fill(x, z.a - 1, z.b)
        y = fill(y, z.a + 1, z.b)
        x = sqrt(x, x)
        y = sqrt(y, y)
        return fill(r, asinh(x.a * y.a + x.b * y.b), 2 * atan(x.b, y.a))
      end
    end,
    return_type = function(types) return 'complex' end
  },
  vornmath.utils.componentWiseExpander('acosh', {'vector'}),
  vornmath.utils.quatOperatorFromComplex('acosh'),
  vornmath.utils.componentWiseReturnOnlys('acosh', 1)
}

vornmath.bakeries.atanh = {
  { -- atanh(number)
    signature_check = vornmath.utils.nilFollowingExactTypeCheck({'number'}),
    create = function(types)
      return function(x)
        return math.log((1 + x) / (1 - x)) / 2
      end
    end,
    return_type = function(types) return 'number' end
  },
  { -- atanh(complex, complex)
    signature_check = vornmath.utils.clearingExactTypeCheck({'complex','complex'}),
    create = function(types)
      local huge = math.huge
      local unm = vornmath.utils.bake('unm', {'complex', 'complex'})
      local mul = vornmath.utils.bake('mul', {'complex', 'number', 'complex'})
      local cfill = vornmath.utils.bake('fill', {'complex', 'complex'})
      local fill = vornmath.utils.bake('fill', {'complex', 'number', 'number'})
      local log = vornmath.utils.bake('log', {'number'})
      local atan = vornmath.utils.bake('atan', {'number', 'number'})
      local eq = vornmath.utils.bake('eq', {'complex', 'number'})
      return function(z, r)
        -- TODO: infinities, large numbers, small imaginaries
        local sign
        if z.a < 0 then
          r = unm(z, r)
          sign = -1
        else
          r = cfill(r, z)
          sign = 1
        end
        if eq(r,1) then
          r = fill(r, huge, 0)
          return mul(r,sign,r)
        end
        return fill(r,
          sign * log(1 + 4 * r.a/((1 - r.a)*(1-r.a) + r.b * r.b))/4,
          -sign * atan(-2 * r.b, (1 - r.a)*(1 + r.a) - r.b * r.b)/2)
      end
    end,
    return_type = function(types) return 'complex' end
  },
  vornmath.utils.componentWiseExpander('atanh', {'vector'}),
  vornmath.utils.quatOperatorFromComplex('atanh'),
  vornmath.utils.componentWiseReturnOnlys('atanh', 1)
}

-- exponential and logarithmic functions

vornmath.bakeries.exp = {
  { -- exp(number)
    signature_check = vornmath.utils.clearingExactTypeCheck({'number'}),
    create = function(types)
      return math.exp
    end,
    return_type = function(types) return 'number' end
  },
  { -- exp(complex)
    signature_check = vornmath.utils.clearingExactTypeCheck({'complex','complex'}),
    create = function(types)
      local fill = vornmath.fill_complex_number_number
      local sin = math.sin
      local cos = math.cos
      local exp = math.exp
      return function(z, result)
        local magnitude = exp(z.a)
        return fill(result, magnitude * cos(z.b), magnitude * sin(z.b))
      end
    end,
    return_type = function(types) return 'complex' end
  },
  vornmath.utils.componentWiseReturnOnlys('exp', 1),
  vornmath.utils.componentWiseExpander('exp', {'vector'}),
  vornmath.utils.quatOperatorFromComplex('exp')
}

vornmath.bakeries.exp2 = {
  {
    signature_check = function(types)
      if vornmath.utils.hasBakery('pow', {'number', types[1], types[2]}) then
        types[3] = nil
        return true
      end
    end,
    create = function(types)
      local pow = vornmath.utils.bake('pow', {'number', types[1], types[2]})
      return function(x,r)
        return pow(2, x, r)
      end
    end,
    return_type = function(types) return types[1] end
  }
}

vornmath.bakeries.log = {
  { -- log(number)
    signature_check = vornmath.utils.nilFollowingExactTypeCheck({'number'}),
    create = function(types)
      return math.log
    end,
    return_type = function(types) return 'number' end
  },
  { -- log(number, number)
    signature_check = vornmath.utils.clearingExactTypeCheck({'number', 'number'}),
    create = function(types)
      if math.log(2,2) ~= math.log(2) then -- does 2 parameter log exist in this version?
        return math.log
      else -- no? gotta make it myself
        local log = math.log
        return function(x,b)
          return log(x)/log(b)
        end
      end
    end,
    return_type = function(types) return 'number' end
  },
  { -- log(complex)
    signature_check = vornmath.utils.clearingExactTypeCheck({'complex', 'nil', 'complex'}),
    create = function(types)
      local arg = vornmath.arg_complex
      local abs = vornmath.abs_complex
      local log = math.log
      local fill = vornmath.fill_complex_number_number
      return function(z, _, result)
        return fill(result, log(abs(z)), arg(z))
      end
    end,
    return_type = function(types) return 'complex' end
  },
  { -- log(complex, complex)
    signature_check = vornmath.utils.clearingExactTypeCheck({'complex', 'complex', 'complex'}),
    create = function(types)
      local log = vornmath.utils.bake('log', {'complex', 'nil', 'complex'})
      local complex = vornmath.utils.bake('complex', {'nil'})
      local div = vornmath.utils.bake('div', {'complex', 'complex', 'complex'})
      local loga = complex()
      local logb = complex()
    return function(a, b, result)
        loga, logb = log(a, nil, loga), log(b, nil, logb)
        result = div(loga, logb, result)
        return result
      end
    end,
    return_type = function(types) return 'complex' end
  },
  { -- log(quat)
    signature_check = vornmath.utils.clearingExactTypeCheck({'quat', 'nil', 'quat'}),
    create = function(types)
      local log = vornmath.utils.bake('log', {'complex', 'nil', 'complex'})
      local axisDecompose = vornmath.utils.bake('axisDecompose', {'quat', 'complex', 'vec3'})
      local fill = vornmath.utils.bake('fill', {'quat', 'complex', 'vec3'})
      local z = vornmath.complex()
      local v = vornmath.vec3()
      return function(q, _, r)
        z, v = axisDecompose(q, z, v)
        z = log(z, nil, z)
        return fill(r, z, v)
      end
    end,
    return_type = function(types) return 'quat' end
  },
  { -- log(quat, quat)
    signature_check = vornmath.utils.clearingExactTypeCheck({'quat', 'quat', 'quat'}),
    create = function(types)
      local log = vornmath.utils.bake('log', {'quat', 'nil', 'quat'})
      local construct = vornmath.utils.bake('quat', {'nil'})
      local div = vornmath.utils.bake('div', {'quat', 'quat', 'quat'})
      local loga = construct()
      local logb = construct()
      return function(a, b, result)
        loga, logb = log(a, nil, loga), log(b, nil, logb)
        result = div(loga, logb, result)
        return result
      end
    end,
    return_type = function(types) return 'quat' end
  },
  vornmath.utils.componentWiseExpander('log', {'vector', 'scalar'}),
  vornmath.utils.componentWiseExpander('log', {'vector', 'vector'}),
  vornmath.utils.componentWiseExpander('log', {'vector', 'nil'}),
  vornmath.utils.componentWiseReturnOnlys('log', 2),
  vornmath.utils.twoMixedScalars('log'),
}

vornmath.bakeries.log10 = {
  {
    signature_check = function(types)
      if vornmath.utils.hasBakery('log', {types[1], 'number', types[2]}) then
        types[3] = nil
        return true
      end
    end,
    create = function(types)
      local log = vornmath.utils.bake('log', {types[1], 'number', types[2]})
      return function(x,r)
        return log(x, 10, r)
      end
    end,
    return_type = function(types) return types[1] end
  }
}

vornmath.bakeries.log2 = {
  {
    signature_check = function(types)
      if vornmath.utils.hasBakery('log', {types[1], 'number', types[2]}) then
        types[3] = nil
        return true
      end
    end,
    create = function(types)
      local log = vornmath.utils.bake('log', {types[1], 'number', types[2]})
      return function(x,r)
        return log(x, 2, r)
      end
    end,
    return_type = function(types) return types[1] end
  }
}


vornmath.bakeries.sqrt = {
  { -- sqrt(number)
    signature_check = vornmath.utils.clearingExactTypeCheck({'number'}),
    create = function(types)
      return math.sqrt
    end
  },
  { -- sqrt(complex)
    signature_check = vornmath.utils.clearingExactTypeCheck({'complex', 'complex'}),
    create = function(types)
      local eq = vornmath.utils.bake('eq', {'complex', 'number'})
      local fill = vornmath.utils.bake('fill', {'complex', 'number','number'})
      local abs = vornmath.utils.bake('abs', {'number'})
      local sqrt = vornmath.utils.bake('sqrt', {'number'})
      local hypot = vornmath.utils.bake('hypot', {'number', 'number'})
      local copysign = vornmath.utils.bake('copysign', {'number', 'number'})

      return function(z, r)

        -- TODO infinities

        local s, d, ax, ay

        if eq(z, 0) then return fill(r, 0, 0) end

        ax = abs(z.a) / 8
        ay = abs(z.b)

        -- TODO tiny z values

        s = 2 * sqrt(ax + hypot(ax, ay/8))
        d = ay / (2 * s);

        if z.a >= 0 then
            return fill(r, s, copysign(d, z.b))
        else
            return fill(r, d, copysign(s, z.b))
        end
      end
    end,
    return_type = function(types) return 'complex' end
  },
  vornmath.utils.componentWiseReturnOnlys('sqrt', 1),
  vornmath.utils.componentWiseExpander('sqrt', {'vector'}),
  vornmath.utils.quatOperatorFromComplex('sqrt')
 
}

vornmath.bakeries.inversesqrt = {
  {
    signature_check = function(types)
      if vornmath.utils.hasBakery('sqrt', types) then
        types[3] = nil
        return true
      end
    end,
    create = function(types)
      local sqrt = vornmath.utils.bake('sqrt', types)
      local div = vornmath.utils.bake('div', {'number', types[1], types[2]})
      return function(x,r)
        return div(1, sqrt(x, r), r)
      end
    end,
    return_type = function(types) return types[1] end
  }
}

vornmath.bakeries.hypot = {
  {
    signature_check = vornmath.utils.clearingExactTypeCheck({'number', 'number'}),
    create = function(types)
      return function(a,b)
        -- TODO: big numbers
        return math.sqrt(a*a + b*b)
      end
    end,
    return_type = function(types) return 'number' end
  },
  {
    signature_check = function(types)
      if types[1] ~= types[2] or types[1] ~= types[3] then return false end
      if vornmath.utils.hasBakery('sqabs', {types[1], types[1]}) and vornmath.utils.hasBakery('sqrt', {types[1], types[1]}) then
        types[4] = nil
        return true
      end
    end,
    create = function(types)
      local sqabs = vornmath.utils.bake('sqabs', {types[1], types[1]})
      local sqrt = vornmath.utils.bake('sqrt', {types[1], types[1]})
      local add = vornmath.utils.bake('add', {types[1], types[1]})
      local as = vornmath[types[1]]()
      local bs = vornmath[types[1]]()
      return function(a,b,r)
        as = sqabs(a, as)
        bs = sqabs(b, bs)
        r = add(as, bs, r)
        return sqrt(r, r)
      end
    end,
    return_type = function(types) return types[3] end
  },
  vornmath.utils.componentWiseReturnOnlys('hypot', 2),
  vornmath.utils.componentWiseExpander('hypot', {'vector', 'vector'}),
}

-- complex and quaternion functions

vornmath.bakeries.arg = {
  { -- arg(number)
    signature_check = vornmath.utils.clearingExactTypeCheck({'number'}),
    create = function(types)
      return function(x) return x >= 0 and 0 or math.pi end
    end,
    return_type = function(types) return 'number' end
  },
  { -- arg(complex)
    signature_check = vornmath.utils.clearingExactTypeCheck({'complex'}),
    create = function(types)
      local atan = vornmath.utils.bake('atan', {'number', 'number'})
      return function(z)
        if z.b == 0 and z.a == 0 then return 0 end
        return atan(z.b, z.a)
      end
    end,
    return_type = function(types) return 'number' end
  },
  { -- arg(quat)
    signature_check = vornmath.utils.clearingExactTypeCheck({'quat'}),
    create = function(types)
      local carg = vornmath.utils.bake('arg', {'complex'})
      local decompose = vornmath.utils.bake('axisDecompose', {'quat', 'complex', 'vec3'})
      local z = vornmath.complex()
      local _ = vornmath.vec3()
      return function(q)
        z, _ = decompose(q,z,_)
        return carg(z)
      end
    end
  },
  vornmath.utils.componentWiseExpander('arg', {'vector'}, true)
}

vornmath.bakeries.axisDecompose = {
  { -- axisDecompose(quat)
    signature_check = vornmath.utils.clearingExactTypeCheck({'quat', 'complex', 'vec3'}),
    create = function(types)
      local fill_complex = vornmath.fill_complex_number_number
      local fill_vec3 = vornmath.fill_vec3_number_number_number
      local length = vornmath.length_vec3
      local div = vornmath.div_vec3_number_vec3
      return function(z, cpx, axis)
        axis = fill_vec3(axis, z.b, z.c, z.d)
        -- do this instead of normalizing: I need both length and normal
        local l = length(axis)
        if l == 0 then
          axis = fill_vec3(axis, 1, 0, 0) -- make something up.
          -- some operators - log is the big one - can create complex results
          -- from "real" inputs.  I want to make sure that the quat version
          -- succeeds too, so I'm going to pretend that there's a "correct"
          -- direction.
        else
          axis = div(axis, l, axis)
        end
        cpx = fill_complex(cpx, z.a, l)
        return cpx, axis
      end
    end,
    return_type = function(types) return 'complex', 'vec3' end
  },
  { -- return-only
    signature_check = vornmath.utils.nilFollowingExactTypeCheck({'quat'}),
    create = function(types)
      local make_complex = vornmath.utils.bake('complex', {})
      local make_vec3 = vornmath.utils.bake('vec3', {})
      local axisDecompose = vornmath.utils.bake('axisDecompose', {'quat', 'complex', 'vec3'})
      return function(z)
        local cpx = make_complex()
        local axis = make_vec3()
        return axisDecompose(z, cpx, axis)
      end
    end
  }
}

vornmath.bakeries.conj = {
  { -- conj(number)
    signature_check = vornmath.utils.clearingExactTypeCheck({'number'}),
    create = function(types)
      return function(x) return x end
    end,
    return_type = function(types) return 'number' end
  },
  { -- conj(complex)
    signature_check = vornmath.utils.clearingExactTypeCheck({'complex', 'complex'}),
    create = function(types)
      local fill = vornmath.fill_complex_number_number
      return function(x, result)
        return fill(result, x.a, -x.b)
      end
    end,
    return_type = function(types) return 'complex' end
  },
  { -- conj(quat)
    signature_check = vornmath.utils.clearingExactTypeCheck({'quat', 'quat'}),
    create = function(types)
      local fill = vornmath.fill_quat_number_number_number_number
      return function(x, result)
        return fill(result, x.a, -x.b, -x.c, -x.d)
      end
    end,
    return_type = function(types) return 'quat' end
  },
  vornmath.utils.componentWiseExpander('conj', {'vector'}),
  vornmath.utils.componentWiseExpander('conj', {'matrix'}),
  vornmath.utils.componentWiseReturnOnlys('conj', 1),
}

-- common functions

vornmath.bakeries.abs = {
  { -- abs(number)
    signature_check = vornmath.utils.clearingExactTypeCheck({'number'}),
    create = function(types)
      return math.abs
    end,
    return_type = function(types) return 'number' end
  },
  { -- abs(complex)
    signature_check = vornmath.utils.clearingExactTypeCheck({'complex'}),
    create = function(types)
      local sqrt = math.sqrt
      return function(x, result)
        return sqrt(x.a * x.a + x.b * x.b)
      end
    end,
    return_type = function(types) return 'number' end
  },
  { -- abs(quat)
    signature_check = vornmath.utils.clearingExactTypeCheck({'quat'}),
    create = function(types)
      local sqrt = math.sqrt
      return function(x, result)
        return sqrt(x.a * x.a + x.b * x.b + x.c * x.c + x.d * x.d)
      end
    end,
    return_type = function(types) return 'number' end
  },
  vornmath.utils.componentWiseExpander('abs', {'vector'}, 'number'),
  vornmath.utils.componentWiseReturnOnlys('abs', 1, 'number')
}

vornmath.bakeries.sqabs = {
  { -- sqabs(number)
    signature_check = vornmath.utils.clearingExactTypeCheck({'number'}),
    create = function(types)
      return function(x, result)
        return x * x
      end
    end,
    return_type = function(types) return 'number' end
  },
  { -- sqabs(complex)
    signature_check = vornmath.utils.clearingExactTypeCheck({'complex'}),
    create = function(types)
      local sqrt = math.sqrt
      return function(x, result)
        return x.a * x.a + x.b * x.b
      end
    end,
    return_type = function(types) return 'number' end
  },
  { -- sqabs(quat)
    signature_check = vornmath.utils.clearingExactTypeCheck({'quat'}),
    create = function(types)
      local sqrt = math.sqrt
      return function(x, result)
        return x.a * x.a + x.b * x.b + x.c * x.c + x.d * x.d
      end
    end,
    return_type = function(types) return 'number' end
  },
  vornmath.utils.componentWiseExpander('sqabs', {'vector'}, 'number'),
  vornmath.utils.componentWiseReturnOnlys('sqabs', 1, 'number')
}

vornmath.bakeries.sign = {
  {
    signature_check = vornmath.utils.clearingExactTypeCheck({'number'}),
    create = function(types)
      local abs = math.abs
      return function(x)
        if x ~= 0 then return x / abs(x) end
        return 0
      end
    end,
    return_type = function(types) return 'number' end
  },
  {
    signature_check = vornmath.utils.clearingExactTypeCheck({'complex', 'complex'}),
    create = function(types)
      local eq = vornmath.utils.bake('eq', {'complex', 'complex'})
      local abs = vornmath.utils.bake('abs', {'complex', 'number'})
      local div = vornmath.utils.bake('div', {'complex', 'number', 'complex'})
      local fill = vornmath.utils.bake('fill', {'complex'})
      local zero = vornmath.complex()
      return function(x, r)
        if eq(x, zero) then
          return fill(r)
        end
        local magnitude = abs(x)
        return div(x, magnitude, r)
      end
    end,

  },
  vornmath.utils.componentWiseExpander('sign', {'vector', 'vector'}),
  vornmath.utils.componentWiseReturnOnlys('sign', 1),
  vornmath.utils.quatOperatorFromComplex('sign')
}

vornmath.bakeries.copysign = {
  {
    signature_check = vornmath.utils.clearingExactTypeCheck({'number', 'number'}),
    create = function(types)
      return function(magnitude,sign)
        local result = math.abs(magnitude)
        if sign >= 0 then
          return result
        else
          return -result
        end
      end
    end,
    return_type = function(types) return 'number' end
  },
  vornmath.utils.componentWiseExpander('copysign', {'vector', 'vector'}),
  vornmath.utils.componentWiseReturnOnlys('copysign', 2)
}

vornmath.bakeries.floor = {
  { -- floor(number)
    signature_check = vornmath.utils.clearingExactTypeCheck({'number'}),
    create = function(types) return math.floor end,
    return_type = function(types) return 'number' end
  },
  vornmath.utils.componentWiseExpander('floor', {'vector'}),
  vornmath.utils.componentWiseReturnOnlys('floor', 1),
}

vornmath.bakeries.ceil = {
  { -- ceil(number)
    signature_check = vornmath.utils.clearingExactTypeCheck({'number'}),
    create = function(types) return math.ceil end,
    return_type = function(types) return 'number' end
  },
  vornmath.utils.componentWiseExpander('ceil', {'vector'}),
  vornmath.utils.componentWiseReturnOnlys('ceil', 1),
}

vornmath.bakeries.trunc = {
  { -- trunc(number)
    signature_check = vornmath.utils.clearingExactTypeCheck({'number'}),
    create = function(types)
      return function(x)
        if x < 0 then
          return math.ceil(x)
        else
          return math.floor(x)
        end
      end
    end,
    return_type = function(types) return 'number' end
  },
  vornmath.utils.componentWiseExpander('trunc', {'vector'}),
  vornmath.utils.componentWiseReturnOnlys('trunc', 1),
}

vornmath.bakeries.round = {
  { -- round(number)
    signature_check = vornmath.utils.clearingExactTypeCheck({'number'}),
    create = function(types)
      local floor = math.floor
      return function(x)
        return floor(x+0.5)
      end
    end,
    return_type = function(types) return 'number' end
  },
  vornmath.utils.componentWiseExpander('round', {'vector'}),
  vornmath.utils.componentWiseReturnOnlys('round', 1),
}

vornmath.bakeries.roundEven = {
  { -- roundEven(number)
    signature_check = vornmath.utils.clearingExactTypeCheck({'number'}),
    create = function(types)
      local floor = math.floor
      return function(x)
        x = x + 0.5
        local f = floor(x)
        if f == x and f % 2 == 1 then
          return f - 1
        end
        return f
      end
    end,
    return_type = function(types) return 'number' end
  },
  vornmath.utils.componentWiseExpander('roundEven', {'vector'}),
  vornmath.utils.componentWiseReturnOnlys('roundEven', 1),
}

vornmath.bakeries.fract = {
  {
    signature_check = vornmath.utils.nilFollowingExactTypeCheck({'number'}),
    create = function(types)
      return function(x)
        local _,y = math.modf(x)
        return y
      end
    end,
    return_type = function(types) return 'number' end
  },
  vornmath.utils.componentWiseExpander('fract', {'vector'}),
  vornmath.utils.componentWiseReturnOnlys('fract', 1),
}

vornmath.bakeries.modf = {
  {
    signature_check = vornmath.utils.nilFollowingExactTypeCheck({'number'}),
    create = function(types)
      return math.modf
    end,
    return_type = function(types) return 'number', 'number' end
  },
  { -- vector
    signature_check = function(types)
      local meta = vornmath.metatables[types[1]]
      if meta.vm_shape ~= 'vector' or meta.vm_storage ~= 'number' then return false end
      if types[2] ~= types[1] or types[3] ~= types[1] then return false end
      types[4] = nil
      return true
    end,
    create = function(types)
      local d = vornmath.metatables[types[1]].vm_dim
      local modf = vornmath.utils.bake('modf', {'number'})
      return function(x, whole, frac)
        for i = 1,d do
          whole[i], frac[i] = modf(x[i])
        end
        return whole, frac
      end
    end,
    return_type = function(types) return types[1], types[1] end
  },
  { -- return-only
    signature_check = function(types)
      if types[2] and types[2] ~= 'nil' or types[3] and types[3] ~= 'nil' then return false end
      if vornmath.utils.hasBakery('modf', {types[1], types[1], types[1]}) then
        types[2] = nil
        return true
      end
    end,
    create = function(types)
      local modf = vornmath.utils.bake('modf', {types[1], types[1], types[1]})
      local construct = vornmath.utils.bake(types[1], {})
      return function(x)
        local whole = construct()
        local frac = construct()
        return modf(x, whole, frac)
      end
    end,
    return_type = function(types) return types[1], types[1] end
  }
}

vornmath.bakeries.fmod = {
  { -- fmod(number, number)
    signature_check = vornmath.utils.clearingExactTypeCheck({'number', 'number'}),
    create = function(types) return math.fmod end,
    return_type = function(types) return 'number' end
  },
  vornmath.utils.componentWiseExpander('fmod', {'vector', 'scalar'}),
  vornmath.utils.componentWiseExpander('fmod', {'scalar', 'vector'}),
  vornmath.utils.componentWiseExpander('fmod', {'vector', 'vector'}),
  vornmath.utils.componentWiseReturnOnlys('fmod', 2),
}

vornmath.bakeries.min = {
  { -- min(number)
    signature_check = vornmath.utils.clearingExactTypeCheck({'number', 'number'}),
    create = function(types)
      return function(a,b)
        return math.min(a,b) -- gotta do it this way because math.min is variadic
      end
    end,
    return_type = function(types) return 'number' end
  },
  vornmath.utils.componentWiseExpander('min', {'scalar', 'vector'}),
  vornmath.utils.componentWiseExpander('min', {'vector', 'scalar'}),
  vornmath.utils.componentWiseExpander('min', {'vector', 'vector'}),
  vornmath.utils.componentWiseReturnOnlys('min', 2)
}

vornmath.bakeries.max = {
  { -- max(number)
    signature_check = vornmath.utils.clearingExactTypeCheck({'number', 'number'}),
    create = function(types)
      return function(a,b)
        return math.max(a,b)
      end
    end,
    return_type = function(types) return 'number' end
  },
  vornmath.utils.componentWiseExpander('max', {'scalar', 'vector'}),
  vornmath.utils.componentWiseExpander('max', {'vector', 'scalar'}),
  vornmath.utils.componentWiseExpander('max', {'vector', 'vector'}),
  vornmath.utils.componentWiseReturnOnlys('max', 2)
}

vornmath.bakeries.clamp = {
  { -- clamp(number, number, number)
    signature_check = vornmath.utils.clearingExactTypeCheck({'number', 'number', 'number'}),
    create = function(types)
      local min = math.min
      local max = math.max
      return function(x, lo, hi)
        return min(max(x, lo), hi)
      end
    end,
    return_type = function(types) return 'number' end
  },
  vornmath.utils.componentWiseExpander('clamp', {'vector', 'vector', 'vector'}),
  vornmath.utils.componentWiseExpander('clamp', {'vector', 'number', 'number'}),
  vornmath.utils.componentWiseReturnOnlys('clamp', 3),
}

vornmath.bakeries.mix = {
  { -- mix(scalar, scalar, scalar)
    signature_check = function(types)
      if #types < 4 then return false end
      for i = 1,4 do
        if vornmath.metatables[types[i]].vm_shape ~= 'scalar' then return false end
      end
      if not (vornmath.utils.hasBakery('mul', {types[1], types[3]}) and
              vornmath.utils.hasBakery('mul', {types[2], types[3]})) then
        return false
      end
      local at_type = vornmath.utils.returnType('mul', {types[1], types[3]})
      local bt_type = vornmath.utils.returnType('mul', {types[2], types[3]})
      if not vornmath.utils.hasBakery('add', {at_type, bt_type, types[4]}) then
        return false
      end
      types[5] = nil
      return true
    end,
    create = function(types)
      local at_type = vornmath.utils.returnType('mul', {types[1], types[3]})
      local bt_type = vornmath.utils.returnType('mul', {types[2], types[3]})
      local leftmul = vornmath.utils.bake('mul', {types[1], types[3], at_type})
      local rightmul = vornmath.utils.bake('mul', {types[2], types[3], bt_type})
      local add = vornmath.utils.bake('add', {at_type, bt_type, types[4]})
      local sub = vornmath.utils.bake('sub', {types[3], types[3], types[3]})
      local at = vornmath[at_type]()
      local bt = vornmath[bt_type]()
      local s = vornmath[types[3]]()
      local one = vornmath[types[3]](1)
      return function(a,b,t,r)
        s = sub(one, t, s)
        at = leftmul(a,s,at)
        bt = rightmul(b,t,bt)
        return add(at, bt, r)
      end
    end,
    return_type = function(types) return types[4] end
  },
  vornmath.utils.componentWiseExpander('mix', {'vector', 'vector', 'vector'}),
  vornmath.utils.componentWiseExpander('mix', {'vector', 'vector', 'scalar'}),
  vornmath.utils.componentWiseReturnOnlys('mix', 3),
  { -- boolean vector version
    signature_check = function(types)
      if #types < 4 then return false end
      if types[4] ~= vornmath.utils.componentWiseConsensusType({types[1], types[2]}) then return false end
      local mixes = vornmath.metatables[types[3]]
      local out = vornmath.metatables[types[4]]
      if mixes.vm_shape ~= 'vector' or mixes.vm_storage ~= 'boolean' or mixes.vm_dim ~= out.vm_dim then return false end
      types[5] = nil
      return true
    end,
    create = function(types)
      local out_type = vornmath.metatables[types[4]]
      local left_storage = vornmath.metatables[types[1]].vm_storage
      local right_storage = vornmath.metatables[types[2]].vm_storage
      local size = out_type.vm_dim
      local out_storage = out_type.vm_storage
      local left_fill = vornmath.utils.bake('fill', {out_storage, left_storage})
      local right_fill = vornmath.utils.bake('fill', {out_storage, right_storage})
      return function(left, right, mixer, out)
        for i = 1,size do
          if mixer[i] then
            out[i] = right_fill(out[i], right[i])
          else
            out[i] = left_fill(out[i], left[i])
          end
        end
        return out
      end
    end
  },
  {
    signature_check = function(types)
      if #types < 3 then return false end
      if types[4] and types[4] ~= 'nil' then return false end
      if vornmath.metatables[types[3]].vm_storage ~= 'boolean' then return false end
      local out_type = vornmath.utils.componentWiseConsensusType({types[1], types[2]})
      if not out_type then return false end
      if vornmath.utils.hasBakery('mix', {types[1], types[2], types[3], out_type}) then
        types[4] = 'nil'
        types[5] = nil
        return true
      end
    end,
    create = function(types)
      local out_type = vornmath.utils.componentWiseConsensusType({types[1], types[2]})
      local construct = vornmath.utils.bake(out_type, {})
      local f = vornmath.utils.bake('mix', {types[1], types[2], types[3], out_type})
      return function(a,b,t)
        local r = construct()
        return f(a,b,t,r)
      end
    end,
    return_type = function(types)
      return vornmath.utils.componentWiseConsensusType({types[1], types[2]})
    end
  }
}

vornmath.bakeries.step = {
  {
    signature_check = vornmath.utils.clearingExactTypeCheck({'number', 'number'}),
    create = function(types)
      return function(edge,x)
        if x < edge then
          return 0
        else
          return 1
        end
      end
    end,
    return_type = function(types) return 'number' end
  },
  vornmath.utils.componentWiseExpander('step', {'scalar', 'vector'}),
  vornmath.utils.componentWiseExpander('step', {'vector', 'vector'}),
  vornmath.utils.componentWiseReturnOnlys('step', 2)
}

vornmath.bakeries.smoothStep = {
  {
    signature_check = vornmath.utils.clearingExactTypeCheck({'number', 'number', 'number'}),
    create = function(types)
      local clamp = vornmath.utils.bake('clamp', {'number', 'number', 'number'})
      return function(lo, hi, x)
        local t = clamp((x-lo)/(hi-lo), 0, 1)
        return t * t * (3 - 2 * t)
      end
    end,
    return_type = function(types) return 'number' end
  },
  vornmath.utils.componentWiseExpander('smoothStep', {'scalar', 'scalar', 'vector'}),
  vornmath.utils.componentWiseExpander('smoothStep', {'vector', 'vector', 'vector'}),
  vornmath.utils.componentWiseReturnOnlys('smoothStep', 3)
}

vornmath.bakeries.isnan = {
  {
    signature_check = function(types)
      return vornmath.metatables[types[1]].vm_shape == 'scalar'
    end,
    create = function(types)
      return function(n)
        return n ~= n
      end
    end
  },
  vornmath.utils.componentWiseExpander('isnan', {'vector'}, 'boolean'),
  vornmath.utils.componentWiseReturnOnlys('isnan', 1, 'boolean')
}

vornmath.bakeries.isinf = {
  {
    signature_check = vornmath.utils.clearingExactTypeCheck({'number'}),
    create = function(types)
      local inf = math.huge
      return function(n)
        return n == inf or n == -inf
      end
    end
  },
  {
  signature_check = vornmath.utils.clearingExactTypeCheck({'complex'}),
    create = function(types)
      local inf = math.huge
      return function(n)
        return n.a == inf or n.a == -inf or n.b == inf or n.b == -inf
      end
    end
  },
  {
    signature_check = vornmath.utils.clearingExactTypeCheck({'quat'}),
    create = function(types)
      local inf = math.huge
      return function(n)
        return (n.a == inf or n.a == -inf or
                n.b == inf or n.b == -inf or
                n.c == inf or n.c == -inf or
                n.d == inf or n.d == -inf)
      end
    end
  },
  vornmath.utils.componentWiseExpander('isinf', {'vector'}, 'boolean'),
  vornmath.utils.componentWiseReturnOnlys('isinf', 1, 'boolean')

}

vornmath.bakeries.fma = {
  { -- mix(scalar, scalar, scalar)
    signature_check = function(types)
      if #types < 4 then return false end
      for i = 1,4 do
        if vornmath.metatables[types[i]].vm_shape ~= 'scalar' then return false end
      end
      if not vornmath.utils.hasBakery('mul', {types[1], types[2]}) then return false end
      local mul_type = vornmath.utils.returnType('mul', {types[1], types[2]})
      if not vornmath.utils.hasBakery('add', {mul_type, types[3], types[4]}) then return false end
      types[5] = nil
      return true
    end,
    create = function(types)
      local scratch_type = vornmath.utils.returnType('mul', {types[1], types[2]})
      local mul = vornmath.utils.bake('mul', {types[1], types[2], scratch_type})
      local add = vornmath.utils.bake('add', {scratch_type, types[3], types[4]})
      local scratch = vornmath[scratch_type]()
      return function(a,b,c,r)
        scratch = mul(a,b,scratch)
        return add(scratch,c,r)
      end
    end,
    return_type = function(types) return types[4] end
  },
  vornmath.utils.componentWiseReturnOnlys('fma', 3),
  vornmath.utils.componentWiseExpander('fma', {'vector', 'vector', 'vector'})
}

vornmath.bakeries.frexp = {
  {
    signature_check = vornmath.utils.nilFollowingExactTypeCheck({'number'}),
    create = function(types)
---@diagnostic disable-next-line: deprecated
      if math.frexp then return math.frexp end
      -- this implementation of frexp stolen from ToxicFrog's vstruct under MIT license.
      local abs,floor,log = math.abs,math.floor,math.log
      local log2 = log(2)
      return function(x)
        if x == 0 then return 0,0 end
        local e = floor(log(abs(x)) / log2)
        if e > 0 then
          -- Why not x / 2^e? Because for large-but-still-legal values of e this
          -- ends up rounding to inf and the wheels come off.
          x = x * 2^-e
        else
          x = x / 2^e
        end
        -- Normalize to the range [0.5,1)
        if abs(x) >= 1.0 then
          x,e = x/2,e+1
        end
        return x,e
      end
    end,
    return_type = function(types) return 'number' end
  },
  { -- vector
    signature_check = function(types)
      local meta = vornmath.metatables[types[1]]
      if meta.vm_shape ~= 'vector' or meta.vm_storage ~= 'number' then return false end
      if types[2] ~= types[1] or types[3] ~= types[1] then return false end
      types[4] = nil
      return true
    end,
    create = function(types)
      local d = vornmath.metatables[types[1]].vm_dim
      local frexp = vornmath.utils.bake('frexp', {'number'})
      return function(x, mantissa, exponent)
        for i = 1,d do
          mantissa[i], exponent[i] = frexp(x[i])
        end
        return mantissa, exponent
      end
    end,
    return_type = function(types) return types[1], types[1] end
  },
  { -- return-only
    signature_check = function(types)
      if types[2] and types[2] ~= 'nil' or types[3] and types[3] ~= 'nil' then return false end
      if vornmath.utils.hasBakery('frexp', {types[1], types[1], types[1]}) then
        types[2] = nil
        return true
      end
    end,
    create = function(types)
      local frexp = vornmath.utils.bake('frexp', {types[1], types[1], types[1]})
      local construct = vornmath.utils.bake(types[1], {})
      return function(x)
        local mantissa = construct()
        local exponent = construct()
        return frexp(x, mantissa, exponent)
      end
    end,
    return_type = function(types) return types[1], types[1] end
  }
}

vornmath.bakeries.ldexp = {
  { -- ldexp(number, number)
    signature_check = vornmath.utils.clearingExactTypeCheck({'number', 'number'}),
    create = function(types)
---@diagnostic disable-next-line: deprecated
      if math.ldexp then return math.ldexp end
      return function(mantissa, exponent)
        return mantissa * 2 ^ exponent
      end
    end,
    return_type = function(types) return 'number' end
  },
  vornmath.utils.componentWiseExpander('ldexp', {'vector', 'vector'}),
  vornmath.utils.componentWiseReturnOnlys('ldexp', 2),
}

-- geometric functions

vornmath.bakeries.length = {
  {
    signature_check = function(types)
      local meta = vornmath.metatables[types[1]]
      if meta.vm_shape == 'vector' and meta.vm_storage ~= 'boolean' then
        types[2] = nil
        return true
      end
    end,
    create = function(types)
      local meta = vornmath.metatables[types[1]]
      local sqabs = vornmath.utils.bake('sqabs', {meta.vm_storage})
      local dim = meta.vm_dim
      local sqrt = math.sqrt
      return function(x)
        local result = 0
        for i = 1,dim do
          result = result + sqabs(x[i])
        end
        return sqrt(result)
      end
    end,
    return_type = function(types) return 'number' end
  }
}

vornmath.bakeries.distance = {
  {
    signature_check = function(types)
      if vornmath.utils.hasBakery('sub', {types[1], types[2]}) and
         vornmath.utils.hasBakery('length', {vornmath.utils.componentWiseConsensusType(types)}) then
        types[3] = nil
        return true
      end
    end,
    create = function(types)
      local composite_type = vornmath.utils.returnType('sub', types)
      local sub = vornmath.utils.bake('sub', {types[1], types[2], composite_type})
      local length = vornmath.utils.bake('length', {composite_type})
      local scratch = vornmath[composite_type]()
      return function(a, b)
        scratch = sub(a, b, scratch)
        return length(scratch)
      end
    end
  }
}

vornmath.bakeries.dot = {
  { -- dot(vec, vec, out_type)
    signature_check = function(types)
      if #types < 3 then return false end
      -- can I multiply these vectors together?
      if not vornmath.utils.hasBakery('mul', {types[1], types[2]}) then return false end
      local mul_result = vornmath.utils.returnType('mul', {types[1], types[2]})
      local mul_meta = vornmath.metatables[mul_result]
      if mul_meta.vm_storage ~= types[3] then return false end
      types[4] = nil
      return true
    end,
    create = function(types)
      local mul_result = vornmath.utils.returnType('mul', {types[1], types[2]})
      local mul = vornmath.utils.bake('mul', {types[1], types[2], mul_result})
      local add = vornmath.utils.bake('add', {types[3], types[3], types[3]})
      local d = vornmath.metatables[types[1]].vm_dim
      local fill = vornmath.utils.bake('fill', {types[3]})
      local conjscratch = vornmath[types[2]]()
      local scratch = vornmath[mul_result]()
      return function(a, b, r)
        r = fill(r)
        conjscratch = vornmath.conj(b, conjscratch)
        scratch = mul(a, conjscratch, scratch)
        for i = 1,d do
          r = add(r, scratch[i], r)
        end
        return r
      end
    end,
    return_type = function(types) return types[3] end
  },
  { -- return-onlys
    signature_check = function(types)
      if #types < 2 then return false end
      for i = 3,#types do
        if types[i] ~= 'nil' and types[i] ~= nil then return false end
      end
      if not vornmath.utils.hasBakery('mul', {types[1], types[2]}) then return false end
      local mul_result = vornmath.utils.returnType('mul', {types[1], types[2]})
      local mul_meta = vornmath.metatables[mul_result]
      if not vornmath.utils.hasBakery('dot', {types[1], types[2], mul_meta.vm_storage}) then return false end
      types[3] = 'nil'
      types[4] = nil
      return true
    end,
    create = function(types)
      local mul_result = vornmath.utils.returnType('mul', {types[1], types[2]})
      local out_type = vornmath.metatables[mul_result].vm_storage
      local dot = vornmath.utils.bake('dot', {types[1], types[2], out_type})
      local construct = vornmath.utils.bake(out_type, {})
      return function(a,b)
        local r = construct()
        return dot(a,b,r)
      end
    end,
    return_type = function(types)
      local mul_result = vornmath.utils.returnType('mul', {types[1], types[2]})
      return vornmath.metatables[mul_result].vm_storage
    end
  }
}

vornmath.bakeries.cross = {
  {
    signature_check = function(types)
      if #types < 3 then return false end
      local first_meta = vornmath.metatables[types[1]]
      local second_meta = vornmath.metatables[types[2]]
      local third_meta = vornmath.metatables[types[3]]
      if first_meta.vm_shape ~= 'vector' or first_meta.vm_dim ~= 3 or
          second_meta.vm_shape ~= 'vector' or second_meta.vm_dim ~= 3 or
          not vornmath.utils.hasBakery('mul', types) then -- cross product is really a sum of multiplications of swizzles
        return false
      end
      types[4] = nil
      return true
    end,
    create = function(types)
      local first_meta = vornmath.metatables[types[1]]
      local second_meta = vornmath.metatables[types[2]]
      local third_meta = vornmath.metatables[types[3]]
      local final_type = third_meta.vm_storage
      local mul = vornmath.utils.bake('mul', {first_meta.vm_storage, second_meta.vm_storage, final_type})
      local sub = vornmath.utils.bake('sub', {final_type, final_type, final_type})
      local fill = vornmath.utils.bake('fill', {types[3], types[3]})
      local scratch_vec = vornmath[types[3]]()
      local scratch_thing = vornmath[final_type]()
      return function(a, b, r)
        scratch_vec[1] = mul(a[2], b[3], scratch_vec[1])
        scratch_thing  = mul(a[3], b[2], scratch_thing)
        scratch_vec[1] = sub(scratch_vec[1], scratch_thing, scratch_vec[1])
        scratch_vec[2] = mul(a[3], b[1], scratch_vec[2])
        scratch_thing  = mul(a[1], b[3], scratch_thing)
        scratch_vec[2] = sub(scratch_vec[2], scratch_thing, scratch_vec[2])
        scratch_vec[3] = mul(a[1], b[2], scratch_vec[3])
        scratch_thing  = mul(a[2], b[1], scratch_thing)
        scratch_vec[3] = sub(scratch_vec[3], scratch_thing, scratch_vec[3])
        return fill(r, scratch_vec)
      end
    end
  },
  vornmath.utils.componentWiseReturnOnlys('cross',2)
}

vornmath.bakeries.normalize = {
  {
    signature_check = function(types)
      if #types < 2 then return false end
      if types[1] ~= types[2] then return false end
      local first_meta = vornmath.metatables[types[1]]
      if first_meta.vm_shape ~= 'vector' then return false end
      if vornmath.utils.hasBakery('length', {types[1]}) then
        types[3] = nil
        return true
      end
    end,
    create = function(types)
      local len = vornmath.utils.bake('length', {types[1]})
      local div = vornmath.utils.bake('div', {types[1], 'number', types[2]})
      return function(a, r)
        local l = len(a)
        return div(a, l, r)
      end
    end
  },
  vornmath.utils.componentWiseReturnOnlys('normalize', 1)
}

vornmath.bakeries.faceForward = {
  {
    signature_check = function(types)
      if #types < 4 then return false end
      if types[1] ~= types[2] or types[1] ~= types[3] or types[1] ~= types[4] then return false end
      local first_meta = vornmath.metatables[types[1]]
      if first_meta.vm_shape ~= 'vector' or first_meta.vm_storage ~= 'number' then
        return false
      end
      types[5] = nil
      return true
    end,
    create = function(types)
      local dot = vornmath.utils.bake('dot', {types[1], types[1]})
      local unm = vornmath.utils.bake('unm', {types[1], types[1]})
      local fill = vornmath.utils.bake('fill', {types[1], types[1]})
      return function(n, i, nref, r)
        if dot(nref, i) >= 0 then
          return unm(n,r)
        else
          return fill(r,n)
        end
      end
    end,
    return_type = function(types) return types[4] end
  },
  vornmath.utils.componentWiseReturnOnlys('faceForward', 3)
}

vornmath.bakeries.reflect = {
  {
    signature_check = function(types)
      if #types < 3 then return false end
      if vornmath.utils.hasBakery('dot', {types[2], types[1]}) and
         vornmath.utils.hasBakery('add', types) then
        return true
      end
    end,
    create = function(types)
      local dot_result_type = vornmath.utils.returnType('dot', {types[2], types[1]})
      local dot = vornmath.utils.bake('dot', {types[2], types[1], dot_result_type})
      local mul_result_type = vornmath.utils.returnType('mul', {dot_result_type, types[2]})
      local mul = vornmath.utils.bake('mul', {dot_result_type, types[2], mul_result_type})
      local scalar_mul = vornmath.utils.bake('mul', {'number', dot_result_type, dot_result_type})
      local sub = vornmath.utils.bake('sub', {types[1], mul_result_type, types[3]})
      local scratch = vornmath[dot_result_type]()
      local scratch_vec = vornmath[mul_result_type]()
      return function(i, n, r)
        scratch = dot(n, i, scratch)
        scratch = scalar_mul(2, scratch, scratch)
        scratch_vec = mul(scratch, n, scratch_vec)
        return sub(i, scratch_vec, r)
      end
    end,
    return_type = function(types) return types[3] end
  },
  vornmath.utils.componentWiseReturnOnlys('reflect', 2)
}

vornmath.bakeries.refract = {
  {
    signature_check = function(types)
      if types[1] ~= types[2] or types[1] ~= types[4] then return false end
      local meta = vornmath.metatables[types[1]]
      if meta.vm_shape == 'vector' and meta.vm_storage == 'number' and types[3] == 'number' then
        types[5] = nil
        return true
      end
    end,
    create = function(types)
      -- okay so I don't actually care about non-number ones
      -- so I can be a little bit less picky about targeting complexes
      -- so standard builtin arithmetic ops will do nicely for all that work
      local dot = vornmath.utils.bake('dot', {types[1], types[2]})
      local sqrt = math.sqrt
      local emptyfill = vornmath.utils.bake('fill', {types[4]})
      local mul = vornmath.utils.bake('mul', {types[1], 'number', types[1]})
      local sub = vornmath.utils.bake('sub', {types[1], types[1], types[1]})
      local scratch = vornmath[types[4]]()
      return function(i, n, eta, r)
        local cosine = dot(n, i)
        local k = 1 - eta * eta * (1 - cosine * cosine)
        if k < 0 then return emptyfill(r) end
        local n_influence = eta * cosine + sqrt(k)
        scratch = mul(i, eta, scratch)
        r = mul(n, n_influence, r)
        return sub(scratch, r, r)
      end
    end,
    return_type = function(types) return types[4] end
  },
  vornmath.utils.componentWiseReturnOnlys('refract', 3)
}

-- matrix functions

vornmath.bakeries.matrixCompMult = {
  vornmath.utils.componentWiseExpander('mul', {'matrix', 'matrix'}),
  vornmath.utils.componentWiseReturnOnlys('matrixCompMult', 2)
}

vornmath.bakeries.outerProduct = {
  { -- outerProduct(vector, vector, matrix)}
    signature_check = function(types)
      if #types < 3 then return false end
      local left = vornmath.metatables[types[1]]
      local right = vornmath.metatables[types[2]]
      local result = vornmath.metatables[types[3]]
      if (left.vm_shape ~= 'vector' or
        right.vm_shape ~= 'vector' or
        result.vm_shape ~= 'matrix' or
        left.vm_dim ~= result.vm_dim[2] or
        result.vm_dim[1] ~= right.vm_dim or
        not vornmath.utils.hasBakery('mul', {left.vm_storage, right.vm_storage, result.vm_storage})
        or not vornmath.utils.hasBakery('add', {result.vm_storage, result.vm_storage, result.vm_storage})
      )
      then
        return false
      end
      types[4] = nil
      return true
    end,
    create = function(types)
      local left_type = vornmath.metatables[types[1]]
      local right_type = vornmath.metatables[types[2]]
      local result_type = vornmath.metatables[types[3]]
      local width = result_type.vm_dim[1]
      local height = result_type.vm_dim[2]
      local mul = vornmath.utils.bake('mul', {left_type.vm_storage, right_type.vm_storage, result_type.vm_storage})
      return function(left, right, result)
        for x = 1, width do
          for y = 1, height do
            result[x][y] = mul(left[y], right[x], result[x][y])
          end
        end
        return result
      end
    end,
    return_type = function(types) return types[3] end
  },
  { -- outerProduct(vector, vector)
    signature_check = function(types)
      if #types < 2 then return false end
      if #types > 2 then
        -- only nils after
        for i, typename in ipairs(types) do
          if i > 2 and typename ~= 'nil' then return false end
        end
      end
      local left = vornmath.metatables[types[1]]
      local right = vornmath.metatables[types[2]]
      if left.vm_shape ~= 'vector' or right.vm_shape ~= 'vector' then
        return false
      end
      local consensus_storage = vornmath.utils.consensusStorage({left.vm_storage, right.vm_storage})
      local result_type = vornmath.utils.findTypeByData('matrix', {right.vm_dim, left.vm_dim}, consensus_storage)
      if vornmath.utils.hasBakery('outerProduct', {types[1], types[2], result_type}) then
        types[3] = 'nil'
        types[4] = nil
        return true
      end
    end,
    create = function(types)
      local left = vornmath.metatables[types[1]]
      local right = vornmath.metatables[types[2]]
      local consensus_storage = vornmath.utils.consensusStorage({left.vm_storage, right.vm_storage})
      local result_type = vornmath.utils.findTypeByData('matrix', {right.vm_dim, left.vm_dim}, consensus_storage)
      local make = vornmath.utils.bake(result_type, {})
      local action = vornmath.utils.bake('outerProduct', {types[1], types[2], result_type})
      return function(a, b)
        local result = make()
        return action(a, b, result)
      end
    end,
    return_type = function(types)
      local left = vornmath.metatables[types[1]]
      local right = vornmath.metatables[types[2]]
      local consensus_storage = vornmath.utils.consensusStorage({left.vm_storage, right.vm_storage})
      return vornmath.utils.findTypeByData('matrix', {right.vm_dim[1], left.vm_dim[2]}, consensus_storage)
    end
  },

}

vornmath.bakeries.transpose = {
  { -- transpose(mataxb, matbxa)
    signature_check = function(types)
      if #types < 2 then return false end
      local first_meta = vornmath.metatables[types[1]]
      local second_meta = vornmath.metatables[types[2]]
      if first_meta.vm_shape == 'matrix' and
         second_meta.vm_shape == 'matrix' and
         first_meta.vm_storage == second_meta.vm_storage and
         first_meta.vm_dim[1] == second_meta.vm_dim[2] and
         first_meta.vm_dim[2] == second_meta.vm_dim[1] then
        types[3] = nil
        return true
      end
    end,
    create = function(types)
      local meta = vornmath.metatables[types[1]]
      local fill = vornmath.utils.bake('fill', {meta.vm_storage, meta.vm_storage})
      local clone = vornmath.utils.bake('fill', {types[1], types[1]})
      local cols = meta.vm_dim[1]
      local rows = meta.vm_dim[2]
      local scratch = vornmath[types[1]]()
      return function(m, target)
        scratch = clone(scratch, m) -- do thiscloning so transposing a square matrix onto itself is safe
        for c = 1,cols do
          for r = 1,rows do
            target[r][c] = fill(target[r][c], scratch[c][r])
          end
        end
        return target
      end
    end,
    return_type = function(types) return types[2] end
  },
  { -- return onlys
    signature_check = function(types)
      if #types < 1 then return false end
      if types[2] and types[2] ~= 'nil' then return false end
      local meta = vornmath.metatables[types[1]]
      if meta.vm_shape ~= 'matrix' then return false end
      local second_dim = {meta.vm_dim[2], meta.vm_dim[1]}
      local second_type = vornmath.utils.findTypeByData('matrix', second_dim, meta.vm_storage)
      if vornmath.utils.hasBakery('transpose', {types[1], second_type}) then
        types[2] = 'nil'
        types[3] = nil
        return true
      end
    end,
    create = function(types)
      local meta = vornmath.metatables[types[1]]
      local second_dim = {meta.vm_dim[2], meta.vm_dim[1]}
      local second_type = vornmath.utils.findTypeByData('matrix', second_dim, meta.vm_storage)
      local f = vornmath.utils.bake('transpose', {types[1], second_type})
      local construct = vornmath.utils.bake(second_type, {})
      return function(m)
        local result = construct()
        return f(m, result)
      end
    end,
    return_type = function(types)
      local meta = vornmath.metatables[types[1]]
      local second_dim = {meta.vm_dim[2], meta.vm_dim[1]}
      return vornmath.utils.findTypeByData('matrix', second_dim, meta.vm_storage)
    end
  }
}

vornmath.bakeries.determinant = {
  { -- determinant(mat2x2, scalar)
    signature_check = function(types)
      if #types < 2 then return false end
      local meta = vornmath.metatables[types[1]]
      if meta.vm_shape == 'matrix' and
         meta.vm_dim[1] == 2 and
         meta.vm_dim[2] == 2 and
         meta.vm_storage == types[2] then
        types[3] = nil
        return true
      end
    end,
    create = function(types)
      local mul = vornmath.utils.bake('mul', {types[2], types[2], types[2]})
      local sub = vornmath.utils.bake('sub', {types[2], types[2], types[2]})
      local scratch = vornmath[types[2]]()
      return function(m, r)
        r = mul(m[1][1], m[2][2], r)
        scratch = mul(m[1][2], m[2][1], scratch)
        return sub(r, scratch, r)
      end
    end,
    return_type = function(types) return types[2] end
  },
  { -- determinant(mat3x3, scalar)
    signature_check = function(types)
      if #types < 2 then return false end
      local meta = vornmath.metatables[types[1]]
      if meta.vm_shape == 'matrix' and
         meta.vm_dim[1] == 3 and
         meta.vm_dim[2] == 3 and
         meta.vm_storage == types[2] then
        types[3] = nil
        return true
      end
    end,
    create = function(types)
      local fill = vornmath.utils.bake('fill', {types[2]})
      local mul = vornmath.utils.bake('mul', {types[2], types[2], types[2]})
      local add = vornmath.utils.bake('add', {types[2], types[2], types[2]})
      local sub = vornmath.utils.bake('sub', {types[2], types[2], types[2]})
      local scratch = vornmath[types[2]]()
      return function(m, r)
        r = fill(r)
        scratch = mul(m[1][1], m[2][2], scratch)
        scratch = mul(scratch, m[3][3], scratch)
        r = add(r, scratch, r)
        scratch = mul(m[1][2], m[2][3], scratch)
        scratch = mul(scratch, m[3][1], scratch)
        r = add(r, scratch, r)
        scratch = mul(m[1][3], m[2][1], scratch)
        scratch = mul(scratch, m[3][2], scratch)
        r = add(r, scratch, r)
        scratch = mul(m[1][1], m[2][3], scratch)
        scratch = mul(scratch, m[3][2], scratch)
        r = sub(r, scratch, r)
        scratch = mul(m[1][2], m[2][1], scratch)
        scratch = mul(scratch, m[3][3], scratch)
        r = sub(r, scratch, r)
        scratch = mul(m[1][3], m[2][2], scratch)
        scratch = mul(scratch, m[3][1], scratch)
        r = sub(r, scratch, r)
        return r
      end
    end,
    return_type = function(types) return types[2] end
  },
  { -- determinant(mat4x4, scalar)
    signature_check = function(types)
      if #types < 2 then return false end
      local meta = vornmath.metatables[types[1]]
      if meta.vm_shape == 'matrix' and
         meta.vm_dim[1] == 4 and
         meta.vm_dim[2] == 4 and
         meta.vm_storage == types[2] then
        types[3] = nil
        return true
      end
    end,
    create = function(types)
      local fill = vornmath.utils.bake('fill', {types[2], types[2]})
      local mul = vornmath.utils.bake('mul', {types[2], types[2], types[2]})
      local add = vornmath.utils.bake('add', {types[2], types[2], types[2]})
      local sub = vornmath.utils.bake('sub', {types[2], types[2], types[2]})
      local scratch = vornmath[types[2]]()
      local scratch_2 = vornmath[types[2]]()
      local scratch_3 = vornmath[types[2]]()
      local scratch_4 = vornmath[types[2]]()
      local scratch_5 = vornmath[types[2]]()
      local scratch_6 = vornmath[types[2]]()

      local low_12 = vornmath[types[2]]()
      local low_13 = vornmath[types[2]]()
      local low_14 = vornmath[types[2]]()
      local low_23 = vornmath[types[2]]()
      local low_24 = vornmath[types[2]]()
      local low_34 = vornmath[types[2]]()
      return function(m, det)
        -- cover the bottom rows with pairs
        low_34 = sub(mul(m[3][3], m[4][4], scratch),  mul(m[4][3], m[3][4], scratch_2), low_34)
        low_24 = sub(mul(m[2][3], m[4][4], scratch),  mul(m[4][3], m[2][4], scratch_2), low_24)
        low_14 = sub(mul(m[1][3], m[4][4], scratch),  mul(m[4][3], m[1][4], scratch_2), low_14)
        low_23 = sub(mul(m[2][3], m[3][4], scratch),  mul(m[3][3], m[2][4], scratch_2), low_23)
        low_13 = sub(mul(m[1][3], m[3][4], scratch),  mul(m[3][3], m[1][4], scratch_2), low_13)
        low_12 = sub(mul(m[1][3], m[2][4], scratch),  mul(m[2][3], m[1][4], scratch_2), low_12)
        scratch = mul(m[1][1], add(sub(mul(m[2][2], low_34, scratch_2), mul(m[3][2], low_24, scratch_3), scratch_4), mul(m[4][2], low_23, scratch_5), scratch_6), scratch)
        det = fill(det, scratch)
        scratch = mul(m[2][1], add(sub(mul(m[1][2], low_34, scratch_2), mul(m[3][2], low_14, scratch_3), scratch_4), mul(m[4][2], low_13, scratch_5), scratch_6), scratch)
        det = sub(det, scratch, det)

        scratch = mul(m[3][1], add(sub(mul(m[1][2], low_24, scratch_2), mul(m[2][2], low_14, scratch_3), scratch_4), mul(m[4][2], low_12, scratch_5), scratch_6), scratch)
        det = add(det, scratch, det)

        scratch = mul(m[4][1], add(sub(mul(m[1][2], low_23, scratch_2), mul(m[2][2], low_13, scratch_3), scratch_4), mul(m[3][2], low_12, scratch_5), scratch_6), scratch)
        return sub(det, scratch, det)
      end
    end,
    return_type = function(types) return types[2] end
  },
  { -- return-onlys
    signature_check = function(types)
      if #types < 1 or types[2] and types[2] ~= 'nil' then return false end
      local meta = vornmath.metatables[types[1]]
      if vornmath.utils.hasBakery('determinant', {types[1], meta.vm_storage}) then
          types[2] = 'nil'
          types[3] = nil
          return true
      end
    end,
    create = function(types)
      local meta = vornmath.metatables[types[1]]
      local f = vornmath.utils.bake('determinant', {types[1], meta.vm_storage})
      local construct = vornmath.utils.bake(meta.vm_storage, {})
      return function(m)
        local r = construct()
        return f(m, r)
      end
    end
  }
}

vornmath.bakeries.inverse = {
  { -- inverse(mat2x2, mat2x2)
    signature_check = function(types)
      if #types < 2 or types[1] ~= types[2] then return false end
      local meta = vornmath.metatables[types[1]]
      if meta.vm_shape == 'matrix' and meta.vm_dim[1] == 2 and meta.vm_dim[2] == 2 then
        types[3] = nil
        return true
      end
    end,
    create = function(types)
      local meta = vornmath.metatables[types[1]]
      local det = vornmath.utils.bake('determinant', {types[1], meta.vm_storage})
      local div = vornmath.utils.bake('div', {types[1], meta.vm_storage, types[1]})
      local unm = vornmath.utils.bake('unm', {meta.vm_storage, meta.vm_storage})
      local fill = vornmath.utils.bake('fill', {meta.vm_storage, meta.vm_storage})
      local scratch = vornmath[types[1]]()
      local d = vornmath[meta.vm_storage]()
      return function(m, r)
        d = det(m, d)
        scratch[1][1] = fill(scratch[1][1], m[2][2])
        scratch[1][2] = unm(m[1][2], scratch[1][2])
        scratch[2][1] = unm(m[2][1], scratch[2][1])
        scratch[2][2] = fill(scratch[2][2], m[1][1])
        return div(scratch, d, r)
      end
    end
  },
  { -- inverse(mat3x3, mat3x3)
    signature_check = function(types)
      if #types < 2 or types[1] ~= types[2] then return false end
      local meta = vornmath.metatables[types[1]]
      if meta.vm_shape == 'matrix' and meta.vm_dim[1] == 3 and meta.vm_dim[2] == 3 then
        types[3] = nil
        return true
      end
    end,
    create = function(types)
      local meta = vornmath.metatables[types[1]]
      local det = vornmath.utils.bake('determinant', {types[1], meta.vm_storage})
      local div = vornmath.utils.bake('div', {types[1], meta.vm_storage, types[1]})
      local mul = vornmath.utils.bake('mul', {meta.vm_storage, meta.vm_storage, meta.vm_storage})
      local sub = vornmath.utils.bake('sub', {meta.vm_storage, meta.vm_storage, meta.vm_storage})
      local scratch = vornmath[types[1]]()
      local scratch_num = vornmath[meta.vm_storage]()
      local scratch_num_2 = vornmath[meta.vm_storage]()
      local d = vornmath[meta.vm_storage]()
      return function(m, r)
        d = det(m, d)
        scratch[1][1] = sub(mul(m[2][2], m[3][3], scratch_num),  mul(m[2][3], m[3][2], scratch_num_2), scratch[1][1])
        scratch[1][2] = sub(mul(m[3][2], m[1][3], scratch_num),  mul(m[3][3], m[1][2], scratch_num_2), scratch[1][2])
        scratch[1][3] = sub(mul(m[1][2], m[2][3], scratch_num),  mul(m[1][3], m[2][2], scratch_num_2), scratch[1][3])
        scratch[2][1] = sub(mul(m[2][3], m[3][1], scratch_num),  mul(m[2][1], m[3][3], scratch_num_2), scratch[2][1])
        scratch[2][2] = sub(mul(m[3][3], m[1][1], scratch_num),  mul(m[3][1], m[1][3], scratch_num_2), scratch[2][2])
        scratch[2][3] = sub(mul(m[1][3], m[2][1], scratch_num),  mul(m[1][1], m[2][3], scratch_num_2), scratch[2][3])
        scratch[3][1] = sub(mul(m[2][1], m[3][2], scratch_num),  mul(m[2][2], m[3][1], scratch_num_2), scratch[3][1])
        scratch[3][2] = sub(mul(m[3][1], m[1][2], scratch_num),  mul(m[3][2], m[1][1], scratch_num_2), scratch[3][2])
        scratch[3][3] = sub(mul(m[1][1], m[2][2], scratch_num),  mul(m[1][2], m[2][1], scratch_num_2), scratch[3][3])
        return div(scratch, d, r)
      end
    end
  },
  { -- inverse(mat4x4, mat4x4)
    signature_check = function(types)
      if #types < 2 or types[1] ~= types[2] then return false end
      local meta = vornmath.metatables[types[1]]
      if meta.vm_shape == 'matrix' and meta.vm_dim[1] == 4 and meta.vm_dim[2] == 4 then
        types[3] = nil
        return true
      end
    end,
    create = function(types)
      local meta = vornmath.metatables[types[1]]
      local det = vornmath.utils.bake('determinant', {types[1], meta.vm_storage})
      local div = vornmath.utils.bake('div', {types[1], meta.vm_storage, types[1]})
      local mul = vornmath.utils.bake('mul', {meta.vm_storage, meta.vm_storage, meta.vm_storage})
      local sub = vornmath.utils.bake('sub', {meta.vm_storage, meta.vm_storage, meta.vm_storage})
      local add = vornmath.utils.bake('add', {meta.vm_storage, meta.vm_storage, meta.vm_storage})
      local s = vornmath[types[1]]()
      local make = vornmath[meta.vm_storage]
      local s1, s2, s3, s4 = make(), make(), make(), make()
      local lo12, lo13, lo14 = make(), make(), make()
      local lo23, lo24, lo34 = make(), make(), make()
      local hi12, hi13, hi14 = make(), make(), make()
      local hi23, hi24, hi34 = make(), make(), make()
      local d = make()
      return function(m, r)
        d = det(m, d)
        lo12 = sub(mul(m[1][3], m[2][4], s1), mul(m[2][3], m[1][4], s2), lo12)
        lo13 = sub(mul(m[1][3], m[3][4], s1), mul(m[3][3], m[1][4], s2), lo13)
        lo14 = sub(mul(m[1][3], m[4][4], s1), mul(m[4][3], m[1][4], s2), lo14)

        lo23 = sub(mul(m[2][3], m[3][4], s1), mul(m[3][3], m[2][4], s2), lo23)
        lo24 = sub(mul(m[2][3], m[4][4], s1), mul(m[4][3], m[2][4], s2), lo24)
        lo34 = sub(mul(m[3][3], m[4][4], s1), mul(m[4][3], m[3][4], s2), lo34)

        hi12 = sub(mul(m[1][1], m[2][2], s1), mul(m[2][1], m[1][2], s2), hi12)
        hi13 = sub(mul(m[1][1], m[3][2], s1), mul(m[3][1], m[1][2], s2), hi13)
        hi14 = sub(mul(m[1][1], m[4][2], s1), mul(m[4][1], m[1][2], s2), hi14)

        hi23 = sub(mul(m[2][1], m[3][2], s1), mul(m[3][1], m[2][2], s2), hi23)
        hi24 = sub(mul(m[2][1], m[4][2], s1), mul(m[4][1], m[2][2], s2), hi24)
        hi34 = sub(mul(m[3][1], m[4][2], s1), mul(m[4][1], m[3][2], s2), hi34)

        s[1][1] = add(sub(mul(m[4][2], lo23, s1), mul(m[3][2], lo24, s2), s4), mul(m[2][2], lo34, s3), s[1][1]) 
        s[1][2] = sub(sub(mul(m[3][2], lo14, s1), mul(m[4][2], lo13, s2), s4), mul(m[1][2], lo34, s3), s[1][2])
        s[1][3] = add(sub(mul(m[1][2], lo24, s1), mul(m[2][2], lo14, s2), s4), mul(m[4][2], lo12, s3), s[1][3]) 
        s[1][4] = sub(sub(mul(m[2][2], lo13, s1), mul(m[1][2], lo23, s2), s4), mul(m[3][2], lo12, s3), s[1][4])
        
        s[2][1] = sub(sub(mul(m[3][1], lo24, s1), mul(m[4][1], lo23, s2), s4), mul(m[2][1], lo34, s3), s[2][1])
        s[2][2] = add(sub(mul(m[4][1], lo13, s1), mul(m[3][1], lo14, s2), s4), mul(m[1][1], lo34, s3), s[2][2]) 
        s[2][3] = sub(sub(mul(m[2][1], lo14, s1), mul(m[1][1], lo24, s2), s4), mul(m[4][1], lo12, s3), s[2][3])
        s[2][4] = add(sub(mul(m[1][1], lo23, s1), mul(m[2][1], lo13, s2), s4), mul(m[3][1], lo12, s3), s[2][4]) 
        
        s[3][1] = add(sub(mul(m[4][4], hi23, s1), mul(m[3][4], hi24, s2), s4), mul(m[2][4], hi34, s3), s[3][1]) 
        s[3][2] = sub(sub(mul(m[3][4], hi14, s1), mul(m[4][4], hi13, s2), s4), mul(m[1][4], hi34, s3), s[3][2])
        s[3][3] = add(sub(mul(m[1][4], hi24, s1), mul(m[2][4], hi14, s2), s4), mul(m[4][4], hi12, s3), s[3][3]) 
        s[3][4] = sub(sub(mul(m[2][4], hi13, s1), mul(m[1][4], hi23, s2), s4), mul(m[3][4], hi12, s3), s[3][4])
        
        s[4][1] = sub(sub(mul(m[3][3], hi24, s1), mul(m[4][3], hi23, s2), s4), mul(m[2][3], hi34, s3), s[4][1])
        s[4][2] = add(sub(mul(m[4][3], hi13, s1), mul(m[3][3], hi14, s2), s4), mul(m[1][3], hi34, s3), s[4][2]) 
        s[4][3] = sub(sub(mul(m[2][3], hi14, s1), mul(m[1][3], hi24, s2), s4), mul(m[4][3], hi12, s3), s[4][3])
        s[4][4] = add(sub(mul(m[1][3], hi23, s1), mul(m[2][3], hi13, s2), s4), mul(m[3][3], hi12, s3), s[4][4]) 
        
        return div(s, d, r)
      end
    end
  },

  vornmath.utils.componentWiseReturnOnlys('inverse', 1)

}

-- vector relational functions

vornmath.bakeries.equal = {
  vornmath.utils.componentWiseExpander('eq', {'vector', 'vector'}, 'boolean'),
  vornmath.utils.componentWiseReturnOnlys('equal', 2, 'boolean')
}

vornmath.bakeries.notEqual = {
  {
    signature_check = function(types)
      if #types < 2 then return false end
      for i = 1,2 do
        if vornmath.metatables[types[i]].vm_shape ~= 'scalar' then return false end
      end
      return vornmath.utils.hasBakery('eq', types)
    end,
    create = function(types)
      local eq = vornmath.utils.bake('eq', types)
      return function(a,b) return not eq(a,b) end
    end,
    return_type = function(types) return 'boolean' end
  },
  vornmath.utils.componentWiseExpander('notEqual', {'vector', 'vector'}, 'boolean'),
  vornmath.utils.componentWiseReturnOnlys('notEqual', 2, 'boolean')
}

vornmath.bakeries.greaterThan = {
  {
    signature_check = vornmath.utils.clearingExactTypeCheck({'number', 'number'}),
    create = function(types)
      return function(a,b) return a > b end
    end,
    return_type = function(types) return 'boolean' end
  },
  vornmath.utils.componentWiseExpander('greaterThan', {'vector', 'vector'}, 'boolean'),
  vornmath.utils.componentWiseReturnOnlys('greaterThan', 2, 'boolean')
}

vornmath.bakeries.greaterThanEqual = {
  {
    signature_check = vornmath.utils.clearingExactTypeCheck({'number', 'number'}),
    create = function(types)
      return function(a,b) return a >= b end
    end,
    return_type = function(types) return 'boolean' end
  },
  vornmath.utils.componentWiseExpander('greaterThanEqual', {'vector', 'vector'}, 'boolean'),
  vornmath.utils.componentWiseReturnOnlys('greaterThanEqual', 2, 'boolean')
}

vornmath.bakeries.lessThan = {
  {
    signature_check = vornmath.utils.clearingExactTypeCheck({'number', 'number'}),
    create = function(types)
      return function(a,b) return a < b end
    end,
    return_type = function(types) return 'boolean' end
  },
  vornmath.utils.componentWiseExpander('lessThan', {'vector', 'vector'}, 'boolean'),
  vornmath.utils.componentWiseReturnOnlys('lessThan', 2, 'boolean')
}

vornmath.bakeries.lessThanEqual = {
  {
    signature_check = vornmath.utils.clearingExactTypeCheck({'number', 'number'}),
    create = function(types)
      return function(a,b) return a <= b end
    end,
    return_type = function(types) return 'boolean' end
  },
  vornmath.utils.componentWiseExpander('lessThanEqual', {'vector', 'vector'}, 'boolean'),
  vornmath.utils.componentWiseReturnOnlys('lessThanEqual', 2, 'boolean')
}

vornmath.bakeries.all = {
  {
    signature_check = function(types)
      if #types < 1 then return false end
      local first = vornmath.metatables[types[1]]
      if first.vm_storage ~= 'boolean' or first.vm_shape ~= 'vector' then return false end
      types[2] = nil
      return true
    end,
    create = function(types)
      local n = vornmath.metatables[types[1]].vm_dim
      return function(v)
        for i = 1,n do
          if not v[i] then return false end
        end
        return true
      end
    end,
    return_type = function(types) return 'boolean' end
  }
}

vornmath.bakeries.any = {
  {
    signature_check = function(types)
      if #types < 1 then return false end
      local first = vornmath.metatables[types[1]]
      if first.vm_storage ~= 'boolean' or first.vm_shape ~= 'vector' then return false end
      types[2] = nil
      return true
    end,
    create = function(types)
      local n = vornmath.metatables[types[1]].vm_dim
      return function(v)
        for i = 1,n do
          if v[i] then return true end
        end
        return false
      end
    end,
    return_type = function(types) return 'boolean' end
  }
}

vornmath.bakeries.logicalAnd = {
  {
    signature_check = vornmath.utils.clearingExactTypeCheck({'boolean', 'boolean'}),
    create = function(types)
      return function(a,b)
        return a and b
      end
    end,
    return_type = function(types) return 'boolean' end
  },
  vornmath.utils.componentWiseExpander('logicalAnd', {'vector', 'vector'}),
  vornmath.utils.componentWiseReturnOnlys('logicalAnd', 2)
}

vornmath.bakeries.logicalOr = {
  {
    signature_check = vornmath.utils.clearingExactTypeCheck({'boolean', 'boolean'}),
    create = function(types)
      return function(a,b)
        return a or b
      end
    end,
    return_type = function(types) return 'boolean' end
  },
  vornmath.utils.componentWiseExpander('logicalOr', {'vector', 'vector'}),
  vornmath.utils.componentWiseReturnOnlys('logicalOr', 2)
}

vornmath.bakeries.logicalNot = {
  {
    signature_check = vornmath.utils.clearingExactTypeCheck({'boolean'}),
    create = function(types)
      return function(a)
        return not a
      end
    end,
    return_type = function(types) return 'boolean' end
  },
  vornmath.utils.componentWiseExpander('logicalNot', {'vector'}),
  vornmath.utils.componentWiseReturnOnlys('logicalNot', 1)
}
-- pseudometatables for non-numerics

vornmath.metatables['nil'] = {
  vm_type = 'nil',
  vm_shape = 'nil',
  vm_dim = 0,
  vm_storage = 'nil'
}

vornmath.metatables['string'] = {
  vm_type = 'string',
  vm_shape = 'string',
  vm_dim = 1,
  vm_storage = 'string'
}

setmetatable(vornmath.metatables['nil'], vornmath.metameta)
setmetatable(vornmath.metatables['string'], vornmath.metameta)

-- so it turns out that __unm is called with two copies of the thing to negate
-- This breaks outvar detection and causes `-a` to actually mutate a when possible.
-- I have to work around this by only accepting one thing!

do
  local unm = vornmath.unm
  vornmath.utils.unmProxy = function(a) return unm(a) end
end

-- metatable setup

for _, scalar_name in ipairs({'boolean', 'number', 'complex', 'quat'}) do
  vornmath.metatables[scalar_name] = {
    vm_type = scalar_name,
    vm_shape = 'scalar',
    vm_dim = 1,
    vm_storage = scalar_name,
    __eq = vornmath.eq,
    __add = vornmath.add,
    __sub = vornmath.sub,
    __mul = vornmath.mul,
    __div = vornmath.div,
    __mod = vornmath.mod,
    __unm = vornmath.utils.unmProxy,
    __pow = vornmath.pow,
    __tostring = vornmath.tostring,
  }
  setmetatable(vornmath.metatables[scalar_name], vornmath.metameta)
end

for _, scalar_name in ipairs({'boolean', 'number', 'complex'}) do
  for vector_size = 2,4 do
    local typename = SCALAR_PREFIXES[scalar_name] .. 'vec' .. tostring(vector_size)
    vornmath.metatables[typename] = {
      vm_type = typename,
      vm_shape = 'vector',
      vm_dim = vector_size,
      vm_storage = scalar_name,
      __eq = vornmath.eq,
      __add = vornmath.add,
      __sub = vornmath.sub,
      __mul = vornmath.mul,
      __div = vornmath.div,
      __mod = vornmath.mod,
      __unm = vornmath.utils.unmProxy,
      __pow = vornmath.pow,
      __tostring = vornmath.tostring,
      __index = vornmath.utils.swizzleGetter,
      __newindex = vornmath.utils.swizzleSetter,
      getters = {},
      setters = {}
    }
    setmetatable(vornmath.metatables[typename], vornmath.metameta)
  end
end

for _, scalar_name in ipairs({'number', 'complex'}) do
  for width = 2,4 do
    for height = 2,4 do
      local typename = SCALAR_PREFIXES[scalar_name] .. 'mat' .. tostring(width) .. 'x' .. tostring(height)
      vornmath.metatables[typename] = {
        vm_type = typename,
        vm_shape = 'matrix',
        vm_dim = {width, height},
        vm_storage = scalar_name,
        __eq = vornmath.eq,
        __add = vornmath.add,
        __sub = vornmath.sub,
        __mul = vornmath.mul,
        __div = vornmath.div,
        __mod = vornmath.mod,
        __unm = vornmath.utils.unmProxy,
        __pow = vornmath.pow,
        __tostring = vornmath.tostring,
        }
        setmetatable(vornmath.metatables[typename], vornmath.metameta)
      end
    vornmath[SCALAR_PREFIXES[scalar_name] .. 'mat' .. tostring(width)] = vornmath[SCALAR_PREFIXES[scalar_name] .. 'mat' .. tostring(width) .. 'x' .. tostring(width)]
  end
end

-- implicit conversions

vornmath.implicit_conversions = {
  boolean = {boolean = {vornmath.boolean_boolean, vornmath.fill_boolean_boolean}},
  number = {number = {vornmath.number_number, vornmath.fill_number_number}},
  complex = {
    number = {vornmath.complex_number_nil, vornmath.fill_complex_number_nil},
    complex = {vornmath.complex_complex, vornmath.fill_complex_complex}
  },
  quat = {
    number = {vornmath.quat_number_nil, vornmath.fill_quat_number_nil},
    complex = {vornmath.quat_complex_nil, vornmath.fill_quat_complex_nil},
    quat = {vornmath.quat_quat, vornmath.fill_quat_quat}
  }
}

return vornmath