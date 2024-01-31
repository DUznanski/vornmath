--[[
MIT License

Copyright (c) 2022-2024 Dan Uznanski

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

-- unpack gets changed into table.unpack in later versions (5.2+)
---@diagnostic disable-next-line: deprecated
local unpack = unpack or table.unpack

-- these are used to name generic parameters for functions that accept a different
-- number of arguments based on type

local LETTERS = {'a','b','c','d','e','f','g','h','i','j','k','l','m','n','o','p'}

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
  __index = function(metatable, thing)
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
        vornmath.bakeries[name] = bakery
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
  local final_name
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

function vornmath.utils.componentWiseReturnOnlys(function_name, arity)
  return {
    signature_check = function(types)
      if #types > arity then
        -- since we're targeting a specific arity only nils after that
        for i, typename in ipairs(types) do
          if i > arity and typename ~= 'nil' then return false end
        end
      end
      local big_type = vornmath.utils.componentWiseConsensusType(types)
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
      local big_type = vornmath.utils.componentWiseConsensusType(types)
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
    end
  }
end

function vornmath.utils.componentWiseConsensusType(types)
  local shape, dim, storage
  for i, typename in ipairs(types) do
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
  storage = vornmath.utils.consensusStorage(types)
  return vornmath.utils.findTypeByData(shape, dim, storage)
end

vornmath.utils.vm_meta = {
  __index = function(vornmath, index)
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
      return vornmath.utils.bake(name, types)
    else
      -- instead, bake *only* the proxy.
      if not vornmath.bakeries[index] then error("unknown vornmath function `" .. index .. "`.") end
      local proxy_index = '_' .. index
      vornmath[index] = function(...) return vornmath.utils.getmetatable(select(1, ...))[proxy_index](...) end
      return vornmath[index]
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

do
  local TYPE_HIERARCHY = {
    number = 1,
    complex = 2,
    quat = 3
  }

  function vornmath.utils.consensusStorage(types)
    -- this will need to change when I no longer have a single hierarchy of types
    local consensus_size = 0
    local consensus_type
    for _,typename in ipairs(types) do
      if typename ~= 'nil' then
        local storage = vornmath.metatables[typename].vm_storage
        if TYPE_HIERARCHY[storage] > consensus_size then
          consensus_type = storage
          consensus_size = TYPE_HIERARCHY[storage]
        end
      end
    end
    return consensus_type
  end
end

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

local function swizzleReadBakery(function_name)
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
          local source = vornmath.metatables[types[1]]
          local construct = vornmath.utils.bake(source.vm_storage, {})
          local read = vornmath.utils.bake(function_name, {types[1], source.vm_storage})
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
          local source = vornmath.metatables[types[1]]
          local target_type = vornmath.utils.findTypeByData('vector', target_dimension, source.vm_storage)
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

table.insert(vornmath.metabakeries, swizzleReadBakery)

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
  }
}

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

for _,storage in ipairs({'boolean', 'number', 'complex'}) do
  for d = 2,4 do
    vornmath.bakeries[SCALAR_PREFIXES[storage] .. 'vec' .. d] = {
      vornmath.utils.vectorNilConstructor(storage, d),
      vornmath.utils.genericConstructor(SCALAR_PREFIXES[storage] .. 'vec' .. d)
    }
  end
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


function vornmath.utils.componentWiseVectorScalar(function_name)
  return {
    signature_check = function(types)
      if #types < 3 then return false end
      local first_meta = vornmath.metatables[types[1]]
      local second_meta = vornmath.metatables[types[2]]
      local third_meta = vornmath.metatables[types[3]]
      if (first_meta.vm_shape ~= 'vector'
       or second_meta.vm_shape ~= 'scalar'
       or third_meta.vm_shape ~= 'vector'
       or first_meta.vm_dim ~= third_meta.vm_dim) then
        return false
      end
      if vornmath.utils.hasBakery(function_name, {first_meta.vm_storage, second_meta.vm_storage, third_meta.vm_storage}) then
        types[4] = nil
        return true
      end
    end,
    create = function(types)
      local first_meta = vornmath.metatables[types[1]]
      local second_meta = vornmath.metatables[types[2]]
      local third_meta = vornmath.metatables[types[3]]
      local dim = first_meta.vm_dim
      local f = vornmath.utils.bake(function_name, {first_meta.vm_storage, second_meta.vm_storage, third_meta.vm_storage})
      return function(a,b,c)
        for i = 1,dim do
          c[i] = f(a[i],b,c[i])
        end
        return c
      end
    end,
    return_type = function(types)
    end
  }
end

function vornmath.utils.componentWiseScalarVector(function_name)
  return {
    signature_check = function(types)
      if #types < 3 then return false end
      local first_meta = vornmath.metatables[types[1]]
      local second_meta = vornmath.metatables[types[2]]
      local third_meta = vornmath.metatables[types[3]]
      if (first_meta.vm_shape ~= 'scalar'
       or second_meta.vm_shape ~= 'vector'
       or third_meta.vm_shape ~= 'vector'
       or second_meta.vm_dim ~= third_meta.vm_dim) then
        return false
      end
      if vornmath.utils.hasBakery(function_name, {first_meta.vm_storage, second_meta.vm_storage, third_meta.vm_storage}) then
        types[4] = nil
        return true
      end
    end,
    create = function(types)
      local first_meta = vornmath.metatables[types[1]]
      local second_meta = vornmath.metatables[types[2]]
      local third_meta = vornmath.metatables[types[3]]
      local dim = second_meta.vm_dim
      local f = vornmath.utils.bake(function_name, {first_meta.vm_storage, second_meta.vm_storage, third_meta.vm_storage})
      return function(a,b,c)
        for i = 1,dim do
          c[i] = f(a,b[i],c[i])
        end
        return c
      end
    end,
    return_type = function(types)
    end
  }
end

function vornmath.utils.componentWiseVectorVector(function_name)
  return {
    signature_check = function(types)
      if #types < 3 then return false end
      local first_meta = vornmath.metatables[types[1]]
      local second_meta = vornmath.metatables[types[2]]
      local third_meta = vornmath.metatables[types[3]]
      if (first_meta.vm_shape ~= 'vector'
       or second_meta.vm_shape ~= 'vector'
       or third_meta.vm_shape ~= 'vector'
       or first_meta.vm_dim ~= second_meta.vm_dim
       or first_meta.vm_dim ~= third_meta.vm_dim) then
        return false
      end
      if vornmath.utils.hasBakery(function_name, {first_meta.vm_storage, second_meta.vm_storage, third_meta.vm_storage}) then
        types[4] = nil
        return true
      end
    end,
    create = function(types)
      local first_meta = vornmath.metatables[types[1]]
      local second_meta = vornmath.metatables[types[2]]
      local third_meta = vornmath.metatables[types[3]]
      local dim = first_meta.vm_dim
      local f = vornmath.utils.bake(function_name, {first_meta.vm_storage, second_meta.vm_storage, third_meta.vm_storage})
      return function(a,b,c)
        for i = 1,dim do
          c[i] = f(a[i],b[i],c[i])
        end
        return c
      end
    end,
    return_type = function(types)
    end
  }
end

function vornmath.utils.componentWiseVector(function_name)
  return {
    signature_check = function(types)
      if #types < 2 then return false end
      local first_meta = vornmath.metatables[types[1]]
      local second_meta = vornmath.metatables[types[2]]
      if (first_meta.vm_shape ~= 'vector'
       or second_meta.vm_shape ~= 'vector'
       or first_meta.vm_dim ~= second_meta.vm_dim) then
        return false
      end
      if vornmath.utils.hasBakery(function_name, {first_meta.vm_storage, second_meta.vm_storage}) then
        types[3] = nil
        return true
      end
    end,
    create = function(types)
      local first_meta = vornmath.metatables[types[1]]
      local second_meta = vornmath.metatables[types[2]]
      local dim = first_meta.vm_dim
      local f = vornmath.utils.bake(function_name, {first_meta.vm_storage, second_meta.vm_storage})
      return function(a,b)
        for i = 1,dim do
          b[i] = f(a[i],b[i])
        end
        return b
      end
    end,
    return_type = function(types)
    end
  }
end

function vornmath.utils.componentWiseVectorNil(function_name)
  return {
    signature_check = function(types)
      if #types < 3 then return false end
      if types[2] ~= 'nil' then return false end
      local first_meta = vornmath.metatables[types[1]]
      local second_meta = vornmath.metatables[types[3]]
      if (first_meta.vm_shape ~= 'vector'
       or second_meta.vm_shape ~= 'vector'
       or first_meta.vm_dim ~= second_meta.vm_dim) then
        return false
      end
      if vornmath.utils.hasBakery(function_name, {first_meta.vm_storage, second_meta.vm_storage}) then
        types[4] = nil
        return true
      end
    end,
    create = function(types)
      local first_meta = vornmath.metatables[types[1]]
      local second_meta = vornmath.metatables[types[3]]
      local dim = first_meta.vm_dim
      local f = vornmath.utils.bake(function_name, {first_meta.vm_storage, second_meta.vm_storage})
      return function(a,_,b)
        for i = 1,dim do
          b[i] = f(a[i],nil,b[i])
        end
        return b
      end
    end,
    return_type = function(types)
    end
  }
end

function vornmath.utils.componentWiseMatrix(function_name)
  return {
    signature_check = function(types)
      if #types < 2 then return false end
      local first_meta = vornmath.metatables[types[1]]
      local second_meta = vornmath.metatables[types[2]]
      if (first_meta.vm_shape ~= 'matrix'
       or second_meta.vm_shape ~= 'matrix'
       or first_meta.vm_dim[1] ~= second_meta.vm_dim[1]
       or first_meta.vm_dim[2] ~= second_meta.vm_dim[2]) then
        return false
      end
      if vornmath.utils.hasBakery(function_name, {first_meta.vm_storage, second_meta.vm_storage}) then
        types[3] = nil
        return true
      end
    end,
    create = function(types)
      local first_meta = vornmath.metatables[types[1]]
      local second_meta = vornmath.metatables[types[2]]
      local width = first_meta.vm_dim[1]
      local height = first_meta.vm_dim[2]
      local f = vornmath.utils.bake(function_name, {first_meta.vm_storage, second_meta.vm_storage})
      return function(a,b)
        for x = 1,width do
          for y = 1,height do
              b[x][y] = f(a[x][y],b[x][y])
            end
          end
        return b
      end
    end,
    return_type = function(types)
    end
  }
end

function vornmath.utils.componentWiseMatrixScalar(function_name)
  return {
    signature_check = function(types)
      if #types < 3 then return false end
      local first_meta = vornmath.metatables[types[1]]
      local second_meta = vornmath.metatables[types[2]]
      local third_meta = vornmath.metatables[types[3]]
      if (first_meta.vm_shape ~= 'matrix'
       or second_meta.vm_shape ~= 'scalar'
       or third_meta.vm_shape ~= 'matrix'
       or first_meta.vm_dim[1] ~= third_meta.vm_dim[1]
       or first_meta.vm_dim[2] ~= third_meta.vm_dim[2]) then
        return false
      end
      if vornmath.utils.hasBakery(function_name, {first_meta.vm_storage, second_meta.vm_storage, third_meta.vm_storage}) then
        types[4] = nil
        return true
      end
    end,
    create = function(types)
      local first_meta = vornmath.metatables[types[1]]
      local second_meta = vornmath.metatables[types[2]]
      local third_meta = vornmath.metatables[types[3]]
      local width = first_meta.vm_dim[1]
      local height = first_meta.vm_dim[2]
      local f = vornmath.utils.bake(function_name, {first_meta.vm_storage, second_meta.vm_storage, third_meta.vm_storage})
      return function(a,b,c)
        for x = 1,width do
          for y = 1,height do
              c[x][y] = f(a[x][y],b, c[x][y])
            end
          end
        return c
      end
    end,
    return_type = function(types)
    end
  }
end

function vornmath.utils.componentWiseScalarMatrix(function_name)
  return {
    signature_check = function(types)
      if #types < 3 then return false end
      local first_meta = vornmath.metatables[types[1]]
      local second_meta = vornmath.metatables[types[2]]
      local third_meta = vornmath.metatables[types[3]]
      if (first_meta.vm_shape ~= 'scalar'
       or second_meta.vm_shape ~= 'matrix'
       or third_meta.vm_shape ~= 'matrix'
       or second_meta.vm_dim[1] ~= third_meta.vm_dim[1]
       or second_meta.vm_dim[2] ~= third_meta.vm_dim[2]) then
        return false
      end
      if vornmath.utils.hasBakery(function_name, {first_meta.vm_storage, second_meta.vm_storage, third_meta.vm_storage}) then
        types[4] = nil
        return true
      end
    end,
    create = function(types)
      local first_meta = vornmath.metatables[types[1]]
      local second_meta = vornmath.metatables[types[2]]
      local third_meta = vornmath.metatables[types[3]]
      local width = second_meta.vm_dim[1]
      local height = second_meta.vm_dim[2]
      local f = vornmath.utils.bake(function_name, {first_meta.vm_storage, second_meta.vm_storage, third_meta.vm_storage})
      return function(a,b,c)
        for x = 1,width do
          for y = 1,height do
              c[x][y] = f(a,b[x][y], c[x][y])
            end
          end
        return c
      end
    end,
    return_type = function(types)
    end
  }
end

function vornmath.utils.componentWiseMatrixMatrix(function_name)
  return {
    signature_check = function(types)
      if #types < 3 then return false end
      local first_meta = vornmath.metatables[types[1]]
      local second_meta = vornmath.metatables[types[2]]
      local third_meta = vornmath.metatables[types[3]]
      if (first_meta.vm_shape ~= 'matrix'
       or second_meta.vm_shape ~= 'matrix'
       or third_meta.vm_shape ~= 'matrix'
       or first_meta.vm_dim[1] ~= second_meta.vm_dim[1]
       or first_meta.vm_dim[2] ~= second_meta.vm_dim[2]
        or first_meta.vm_dim[1] ~= third_meta.vm_dim[1]
        or first_meta.vm_dim[2] ~= third_meta.vm_dim[2]) then
         return false
      end
      if vornmath.utils.hasBakery(function_name, {first_meta.vm_storage, second_meta.vm_storage, third_meta.vm_storage}) then
        types[4] = nil
        return true
      end
    end,
    create = function(types)
      local first_meta = vornmath.metatables[types[1]]
      local second_meta = vornmath.metatables[types[2]]
      local third_meta = vornmath.metatables[types[3]]
      local width = first_meta.vm_dim[1]
      local height = first_meta.vm_dim[2]
      local f = vornmath.utils.bake(function_name, {first_meta.vm_storage, second_meta.vm_storage, third_meta.vm_storage})
      return function(a,b,c)
        for x = 1,width do
          for y = 1,height do
              c[x][y] = f(a[x][y],b[x][y], c[x][y])
            end
          end
        return c
      end
    end,
    return_type = function(types)
    end
  }
end


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
  vornmath.utils.componentWiseVectorScalar('add'),
  vornmath.utils.componentWiseScalarVector('add'),
  vornmath.utils.componentWiseVectorVector('add'),
  vornmath.utils.componentWiseMatrixScalar('add'),
  vornmath.utils.componentWiseScalarMatrix('add'),
  vornmath.utils.componentWiseMatrixMatrix('add'),
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
  vornmath.utils.componentWiseVector('unm'),
  vornmath.utils.componentWiseMatrix('unm'),
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
  vornmath.utils.componentWiseVectorScalar('sub'),
  vornmath.utils.componentWiseScalarVector('sub'),
  vornmath.utils.componentWiseVectorVector('sub'),
  vornmath.utils.componentWiseMatrixScalar('sub'),
  vornmath.utils.componentWiseScalarMatrix('sub'),
  vornmath.utils.componentWiseMatrixMatrix('sub'),
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
        types[3] = nil
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
        types[3] = nil
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
        types[3] = nil
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
  vornmath.utils.componentWiseVectorScalar('mul'),
  vornmath.utils.componentWiseScalarVector('mul'),
  vornmath.utils.componentWiseVectorVector('mul'),
  vornmath.utils.componentWiseMatrixScalar('mul'),
  vornmath.utils.componentWiseScalarMatrix('mul'),
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
  vornmath.utils.componentWiseVectorScalar('div'),
  vornmath.utils.componentWiseScalarVector('div'),
  vornmath.utils.componentWiseVectorVector('div'),
  vornmath.utils.componentWiseMatrixScalar('div'),
  vornmath.utils.componentWiseScalarMatrix('div'),
  vornmath.utils.componentWiseMatrixMatrix('div'),
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
  vornmath.utils.componentWiseVectorScalar('mod'),
  vornmath.utils.componentWiseScalarVector('mod'),
  vornmath.utils.componentWiseVectorVector('mod'),
  vornmath.utils.componentWiseMatrixScalar('mod'),
  vornmath.utils.componentWiseScalarMatrix('mod'),
  vornmath.utils.componentWiseMatrixMatrix('mod'),
  vornmath.utils.componentWiseReturnOnlys('mod', 2),

}

vornmath.bakeries.eq = {
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
  vornmath.utils.componentWiseVectorVector('atan'),
  vornmath.utils.componentWiseVectorNil('atan'),
  vornmath.utils.componentWiseReturnOnlys('atan', 2),
}

-- TODO: quat
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
      local log = vornmath.log_complex_nil_complex
      local complex = vornmath.complex_nil
      local div = vornmath.div_complex_complex_complex
      return function(a, b, result)
        local loga = complex()
        local logb = complex()
        loga, logb = log(a, nil, loga), log(b, nil, logb)
        result = div(loga, logb, result)
        return result
      end
    end,
    return_type = function(types) return 'complex' end
  },
  vornmath.utils.componentWiseVectorScalar('log'),
  vornmath.utils.componentWiseVectorVector('log'),
  vornmath.utils.componentWiseVectorNil('log'),
  vornmath.utils.componentWiseReturnOnlys('log', 2),
  vornmath.utils.twoMixedScalars('log'),
}

-- TODO: quat
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
      local atan = vornmath.atan_number_number
      return function(z)
        if z.b == 0 and z.a == 0 then return 0 end
        return atan(z.b, z.a)
      end
    end,
    return_type = function(types) return 'number' end
  }
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
  vornmath.utils.componentWiseVector('exp'),
  vornmath.utils.quatOperatorFromComplex('exp')
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
  vornmath.utils.componentWiseVectorScalar('pow'),
  vornmath.utils.componentWiseScalarVector('pow'),
  vornmath.utils.componentWiseVectorVector('pow'),
  vornmath.utils.componentWiseReturnOnlys('pow', 2),
  vornmath.utils.twoMixedScalars('pow'),
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
  -- sqabs doesn't need a "return only" thing because it is always number returns anyway
}

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

  }
  -- same here
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
  vornmath.utils.componentWiseVector('conj'),
  vornmath.utils.componentWiseMatrix('conj'),
  vornmath.utils.componentWiseReturnOnlys('conj', 1),
}

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
        __unm = vornmath.utils.unmProxy,
        __pow = vornmath.pow,
        __tostring = vornmath.tostring,
        }
        setmetatable(vornmath.metatables[typename], vornmath.metameta)
      end
    vornmath[SCALAR_PREFIXES[scalar_name] .. 'mat' .. tostring(width)] = vornmath[SCALAR_PREFIXES[scalar_name] .. 'mat' .. tostring(width) .. 'x' .. tostring(width)]
  end
end

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