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
vornmath.metatables = {}
vornmath.metameta = {
  __index = function(metatable, thing)
    -- process the thing to get the name.
    -- the name should just be the first word of the name.
    local name = string.match(thing, '[^_]+')
    return function(...) return vornmath.utils.bakeByCall(name, ...)(...) end
  end
}

function vornmath.utils.hasBakery(function_name, types)
  local available_bakeries = vornmath.bakeries[function_name]
  if not available_bakeries then return nil end
  for _, bakery in ipairs(available_bakeries) do
    if bakery.signature_check(types) then return bakery end
  end
  return false
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
  vornmath.utils.buildProxies(function_name, types)
  return result
end

function vornmath.utils.bakeByCall(name, ...)
  local types = {}
  for i = 1, select('#', ...) do
    types[i] = vornmath.type(select(i, ...))
  end
  local f = vornmath.utils.bake(name, types)
  return f
end

function vornmath.utils.buildProxies(function_name, types)
  local built_name = '_' .. function_name
  if not rawget(vornmath, function_name) then
    local existing_name = built_name
    vornmath[function_name] = function(...) return vornmath.getmetatable(select(1, ...))[existing_name](...) end
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
      vornmath.metatables[type_name][existing_name] = function(...) return vornmath.getmetatable(select(select_index, ...))[next_name](...) end
    end
  end
  vornmath.metatables[types[#types]][built_name] = vornmath[function_name .. '_' .. table.concat(types, '_')]
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
      vornmath[index] = function(...) return vornmath.getmetatable(select(1, ...))[proxy_index](...) end
      return vornmath[index]
    end
  end
}

setmetatable(vornmath, vornmath.utils.vm_meta)

function vornmath.type(obj)
  local mt = getmetatable(obj)
  return (mt and mt.vm_type) or type(obj)
end

function vornmath.getmetatable(obj)
  local mt = getmetatable(obj)
  if mt and mt.vm_type then
    return mt
  else
    return vornmath.metatables[type(obj)]
  end
end

function vornmath.constructCheck(typename)
  local vmtype = vornmath.type
  local construct = vornmath[typename .. '_nil']
  return function(thing)
    if thing == nil then
      return construct()
    elseif vmtype(thing) == typename then
      return thing
    else
      error("invalid assign-type target: expected " .. typename .. ", got " .. vmtype(thing))
    end
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

function vornmath.utils.justNilTypeCheck(types)
  if not types[1] then
    types[1] = 'nil' -- I have to edit type lists that need to include a nil.
  end
  return types[1] == 'nil'
end

function vornmath.utils.clearingExactTypeCheck(correct_types)
  return function(types)
    for i,t in ipairs(correct_types) do
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
        z.a, z.b, z.c, z.d = cpx.a, cpx.b * axis[1], cpx.b * axis[2], cpx.c * axis[3]
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
      local fill = vornmath['fill_' .. storage .. '_nil']
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
      if not vornmath.implicit_conversions[first.vm_storage][second.vm_storage] then return false end
      if not types[3] then types[3] = 'nil' end
      return types[3] == 'nil'
    end,
    create = function(types)
      local first = vornmath.metatables[types[1]]
      local second = vornmath.metatables[types[2]]
      local fill = vornmath.implicit_conversions[first.vm_storage][second.vm_storage][2]
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
      local nilfill = vornmath['fill_' .. storage .. '_nil']
      local numfill = vornmath['fill_' .. storage .. '_number']
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
      if not vornmath.implicit_conversions[first.vm_storage][second.vm_storage] then return false end
      if not types[3] then types[3] = 'nil' end
      return types[3] == 'nil'
    end,
    create = function(types)
      local first = vornmath.metatables[types[1]]
      local second = vornmath.metatables[types[2]]
      local nilfill = vornmath['fill_' .. first.vm_storage .. '_nil']
      local valfill = vornmath.implicit_conversions[first.vm_storage][second.vm_storage][2]
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
      local nilfill = vornmath['fill_' .. first.vm_storage .. '_nil']
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

function vornmath.utils.generic_constructor(typename)
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
      local constructor = vornmath[typename .. '_nil']
      local fill_name = 'fill_' .. typename .. '_' .. table.concat(types, '_')
      local fill = vornmath[fill_name]
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
  vornmath.utils.generic_constructor('boolean')
}

vornmath.bakeries.number = {
  { -- number()
    signature_check = vornmath.utils.justNilTypeCheck,
    create = function(types)
      return function() return 0 end
    end,
    return_type = function(types) return 'number' end
  },
  vornmath.utils.generic_constructor('number')
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
  vornmath.utils.generic_constructor('complex')
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
  vornmath.utils.generic_constructor('quat')
}


function vornmath.utils.vector_nil_constructor(storage,d)
  local typename = SCALAR_PREFIXES[storage] .. 'vec' .. d
  return { -- vecd()
    signature_check = vornmath.utils.justNilTypeCheck,
    create = function(types)
      local mt = vornmath.metatables[typename]
      local constructor = vornmath[storage .. '_nil']
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
      vornmath.utils.vector_nil_constructor(storage, d),
      vornmath.utils.generic_constructor(SCALAR_PREFIXES[storage] .. 'vec' .. d)
    }
  end
end

function vornmath.utils.matrix_nil_constructor(storage,w,h)
  local prefix = SCALAR_PREFIXES[storage]
  local typename = prefix .. 'mat' .. w .. 'x' .. h
  return {
    signature_check = vornmath.utils.justNilTypeCheck,
    create = function(types)
      local mt = vornmath.metatables[typename]
      local vec = vornmath[prefix .. 'vec' .. h .. '_nil']
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
        vornmath.utils.matrix_nil_constructor(storage, w, h),
        vornmath.utils.generic_constructor(typename)
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

function vornmath.utils.scalarReturnOnlys(function_name, arity)
  return {
    signature_check = function(types)
      if #types < arity then return false end
      if #types > arity then
        for i, typename in ipairs(types) do
          if i > arity and typename ~= nil then return false end
        end
      end
      for _, typename in ipairs(types) do
        local meta = vornmath.metatables[typename]
        if meta.vm_shape ~= 'scalar' then return false end
      end
      local big_type = vornmath.utils.consensusStorage(types)
      local full_types = {}
      for i, typename in ipairs(types) do
        full_types[i] = typename
      end
      full_types[arity + 1] = big_type
      if vornmath.utils.hasBakery(function_name, full_types) then
        table.insert(types, 'nil')
        return true
      end
    end,
    create = function(types)
      local big_type = vornmath.utils.consensusStorage(types)
      local full_types = {}
      local letters = {}
      for i = 1,arity do
        full_types[i] = types[i]
        letters[i] = LETTERS[i]
      end
      full_types[arity + 1] = big_type
      local f = vornmath.utils.bake(function_name, full_types)
      local create = vornmath.utils.bake(big_type, {})
      local letter_glom = table.concat(letters, ', ')
      local code = [[
        local f = select(1, ...)
        local create = select(2, ...)
        return function(]] .. letter_glom .. [[)
          return f(]] .. letter_glom .. [[, create())
        end
      ]]
      return load(code)(f, create)
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
  vornmath.utils.scalarReturnOnlys('add',2),
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
  vornmath.utils.scalarReturnOnlys('unm', 1),
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
  vornmath.utils.scalarReturnOnlys('sub', 2),
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
  vornmath.utils.scalarReturnOnlys('mul', 2),
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
  vornmath.utils.scalarReturnOnlys('div', 2),
}

vornmath.bakeries.mod = {
  { -- mod(number, number)
    signature_check = vornmath.utils.clearingExactTypeCheck({'number', 'number'}),
    create = function(types)
      return function(x, y) return x % y end
    end,
    return_type = function(types) return 'number' end
  }
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
      local consensus_operator = vornmath['eq_' .. first.vm_storage .. '_' .. second.vm_storage]
      if consensus_operator then
        types[3] = nil
        return true
      end
    end,
    create = function(types)
      local first = vornmath.metatables[types[1]]
      local second = vornmath.metatables[types[2]]
      local consensus_operator = vornmath['eq_' .. first.vm_storage .. '_' .. second.vm_storage]
      local length = first.vm_dim
      return function(a, b)
        for i = 1,length do
          if not consensus_operator(a[i], b[i]) then return false end
        end
        return true
      end
    end,
    return_type = function(types) return 'boolean' end
  }
}

vornmath.bakeries.lt = {
  { -- lt(number, number)
    signature_check = vornmath.utils.clearingExactTypeCheck({'number', 'number'}),
    create = function(types)
      return function(x, y) return x < y end
    end,
    return_type = function(types) return 'boolean' end
  },
}

vornmath.bakeries.atan = {
  { -- atan(number)
    signature_check = vornmath.utils.clearingExactTypeCheck({'number', 'nil'}),
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
}

-- TODO: quat, outvars
vornmath.bakeries.log = {
  { -- log(number)
    signature_check = vornmath.utils.clearingExactTypeCheck({'number', 'number'}),
    create = function(types)
      return math.log
    end,
    return_type = function(types) return 'number' end
  },
  { -- log(complex)
    signature_check = vornmath.utils.clearingExactTypeCheck({'complex', 'complex'}),
    create = function(types)
      local cc = vornmath.constructCheck('complex')
      local arg = vornmath.arg_complex
      local abs = vornmath.abs_complex
      local real_log = math.log
      local fill = vornmath.fill_complex_number_number
      return function(z, result)
        result = cc(result)
        return fill(result, real_log(abs(z)), arg(z))
      end
    end,
    return_type = function(types) return 'complex' end
  },
  vornmath.utils.quatOperatorFromComplex('log'),
  vornmath.utils.scalarReturnOnlys('log', 1)
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
        return atan(z.b, z.a)
      end
    end,
    return_type = function(types) return 'number' end
  }
}

--TODO: split outvars
vornmath.bakeries.axisDecompose = {
  { -- axisDecompose(quat)
    signature_check = vornmath.utils.clearingExactTypeCheck({'quat'}),
    create = function(types)
      local cc_complex = vornmath.constructCheck('complex')
      local cc_vec3 = vornmath.constructCheck('vec3')
      local fill_complex = vornmath.fill_complex_number_number
      local fill_vec3 = vornmath.fill_vec3_number_number_number
      local length = vornmath.length_vec3
      local div = vornmath.div_vec3_number
      return function(z, cpx, axis)
        cpx = cc_complex(cpx)
        axis = cc_vec3(axis)
        axis = fill_vec3(axis, z.b, z.c, z.d)
        -- do this instead of normalizing: I need both length and normal
        local l = length(axis)
        axis = div(axis, l, axis)
        cpx = fill_complex(cpx, z.a, l)
        return cpx, axis
      end
    end,
    return_type = function(types) return 'complex', 'vec3' end
  }
}

-- TODO: outvars
vornmath.bakeries.exp = {
  { -- exp(number)
    signature_check = vornmath.utils.clearingExactTypeCheck({'number'}),
    create = function(types)
      return math.exp
    end,
    return_type = function(types) return 'number' end
  },
  { -- exp(complex)
    signature_check = vornmath.utils.clearingExactTypeCheck({'complex'}),
    create = function(types)
      local cc = vornmath.constructCheck('complex')
      local fill = vornmath.fill_complex_number_number
      local sin = math.sin
      local cos = math.cos
      local exp = math.exp
      return function(z, result)
        result = cc(result)
        return fill(result, exp(z.a) * sin(z.b), exp(z.a) * cos(z.b))
      end
    end,
    return_type = function(types) return 'complex' end
  },
--  vornmath.utils.quatOperatorFromComplex(vornmath.exp_complex)
}

-- TODO: outvars
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
  { -- pow(number, complex)
    signature_check = vornmath.utils.clearingExactTypeCheck({'number', 'complex'}),
    create = function(types)
      local cc = vornmath.constructCheck('complex')
      local fill = vornmath.fill_complex_number_number
      local log = math.log
      local exp = math.exp
      local sin = math.sin
      local cos = math.cos
      local pi = math.pi
      return function(x, y, result)
        result = cc(result)
        local bonus_argument = 0
        if y.a == 0 and y.b == 0 then return fill(result, 1, 0) end
        if x == 0 then return fill(result, 0, 0) end
        if x < 0 then
          x = -x
          bonus_argument = pi
        end
        local w = log(x)
        local argument = y.b * w + bonus_argument
        local size = exp(y.a * w)
        return fill(result, size * cos(argument), size * sin(argument))
      end
    end,
    return_type = function(types) return 'complex' end
  },
  { -- pow(complex, number)
    signature_check = vornmath.utils.clearingExactTypeCheck({'complex', 'number'}),
    create = function(types)
      local cc = vornmath.constructCheck('complex')
      local fill = vornmath.fill_complex_number_number
      local log = vornmath.log_complex
      local exp = math.exp
      local sin = math.sin
      local cos = math.cos
      return function(x, y, result)
        result = cc(result)
        if y == 0 then return fill(result, 1, 0) end
        if x.a == 0 and x.b == 0 then return fill(result, 0, 0) end
        local w = log(x)
        local argument = y * w.b
        local size = exp(y * w.a)
        return fill(result, size * cos(argument), size * sin(argument))
      end
    end,
    return_type = function(types) return 'boolean' end
  },
  { -- pow(complex, complex)
    signature_check = vornmath.utils.clearingExactTypeCheck({'complex', 'complex'}),
    create = function(types)
      local cc = vornmath.constructCheck('complex')
      local fill = vornmath.fill_complex_number_number
      local log = vornmath.log_complex
      local exp = math.exp
      local sin = math.sin
      local cos = math.cos
      local mul = vornmath.mul_complex_complex
      return function(x, y, result)
        result = cc(result)
        if y.a == 0 and y.b == 0 then return fill(result, 1, 0) end
        if x.a == 0 and x.b == 0 then return fill(result, 0, 0) end
        local w = log(x)
        w = mul(w, y, w)
        local size = exp(w.a)
        return fill(result, size * cos(w.b), size * sin(w.b))
      end
    end,
    return_type = function(types) return 'complex' end
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
  }
}

-- TODO: outvars
vornmath.bakeries.mix = {
  { -- mix(scalar, scalar, scalar)  
    signature_check = function(types)
      for i = 1,3 do
        local mt = vornmath.metatables[types[i]]
        if mt.vm_shape ~= 'scalar' then
          return false
        end
      end
      types[4] = nil
      return true
    end,
    create = function(types)
      local left_type = vornmath.utils.consensusStorage({types[1], types[3]})
      local right_type = vornmath.utils.consensusStorage({types[2], types[3]})
      local final_type = vornmath.utils.consensusStorage({left_type, right_type})
      local cc = vornmath.constructCheck(final_type)
      local sub = vornmath['sub_number_' .. types[3]]
      local add = vornmath['add_' .. left_type .. '_' .. right_type]
      local left_mul = vornmath['mul_' .. types[1] .. '_' .. types[3]]
      local right_mul = vornmath['mul_' .. types[2] .. '_' .. types[3]]
      local fill = vornmath['fill_' .. final_type .. '_' .. final_type]
      return function(a, b, t, result)
        result = cc(result)
        local total = add(left_mul(a, sub(1, t)), right_mul(b, t))
        result = fill(result, total)
        return result
      end
    end
  },
  return_type = function(types)
    local cs = vornmath.utils.consensusStorage
    return cs({cs({types[1], types[3]}), cs({types[2], types[3]})}) end
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
-- TODO: outvars
vornmath.bakeries.conj = {
  { -- conj(number)
    signature_check = vornmath.utils.clearingExactTypeCheck({'number'}),
    create = function(types)
      return function(x) return x end
    end,
    return_type = function(types) return 'number' end
  },
  { -- conj(complex)
    signature_check = vornmath.utils.clearingExactTypeCheck({'complex'}),
    create = function(types)
      local cc = vornmath.constructCheck('complex')
      local fill = vornmath.fill_complex_number_number
      return function(x, result)
        result = cc(result)
        return fill(result, x.a, -x.b)
      end
    end,
    return_type = function(types) return 'complex' end
  },
  { -- conj(quat)
    signature_check = vornmath.utils.clearingExactTypeCheck({'quat'}),
    create = function(types)
      local cc = vornmath.constructCheck('complex')
      local fill = vornmath.fill_quat_number_number
      return function(x, result)
        result = cc(result)
        return fill(result, x.a, -x.b, -x.c, -x.d)
      end
    end,
    return_type = function(types) return 'quat' end
  }
}

vornmath.bakeries.length = {
  signature_check = function(types)
    if vornmath.metatables[types[1]].vm_shape == 'vector' then
      types[2] = nil
      return true
    end
  end,
  create = function(types)
    local value = vornmath.metatables[types[1]].vm_storage
    
  end,
  return_type = function(types) return 'number' end
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
  function vornmath.utils.unm_proxy(a) return unm(a) end
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
    __unm = vornmath.utils.unm_proxy,
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
      __unm = vornmath.utils.unm_proxy,
      __pow = vornmath.pow,
      __tostring = vornmath.tostring,
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
        __unm = vornmath.utils.unm_proxy,
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
