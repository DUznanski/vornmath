local vm = require('vornmath')

local center = vm.complex(-0.65,0.425)

local radius = 0.075


local mandelbrot = {}

function mandelbrot:enter()
  local w, h = love.graphics.getDimensions()
  self.my_canvas = love.graphics.newCanvas(w*2, h*2)
  local small_side = vm.min(w, h)
  local scaling = vm.cvec2(1, vm.complex(0,1)) * radius / small_side
  local offset = -vm.vec2(w, h)
  self.cells = {}
  for x_index = 0, w*2-1 do
    for y_index = 0, h*2-1 do
      local location = vm.vec2(x_index, y_index) + 0.5
      local z = vm.dot(location + offset, scaling) + center
      local c = vm.complex()
      local cell = {loc = location, z = z, c = c}
      table.insert(self.cells, cell)
    end
  end
  self.killed_cells = {}
  self.n = 0
end

-- These five functions all have the same basic functionality.
-- You can use operators or functions to access the operator math.
-- For functions, you can get pre-baked dispatch, avoiding type checking.
-- You can also get in-place versions of the function, avoiding creating new
-- tables every time you do stuff.
-- It's a *lot* faster to do both of these but it has a tendency to make stuff
-- harder to read, so make sure you're sure this is a problem; right here I'm
-- handling like 3.6 million complex numbers per frame so it pays off, but in
-- reality this kind of work is best done on the GPU regardless, so...

local function update_cell_operators(cell)
  local c, z = cell.c, cell.z
  cell.c = c * c + z
end

local update_cell_functions
do
  local add = vm.add
  local mul = vm.mul
  update_cell_functions = function(cell)
    local c, z = cell.c, cell.z
    cell.c = add(mul(c, c), z)
  end
end

local update_cell_functions_dispatch
do
  local add = vm.utils.bake('add', {'complex', 'complex'})
  local mul = vm.utils.bake('mul', {'complex', 'complex'})
  update_cell_functions_dispatch = function(cell)
    local c, z = cell.c, cell.z
    cell.c = add(mul(c, c), z)
  end
end

local update_cell_functions_modifying
do
  local add = vm.add
  local mul = vm.mul
  update_cell_functions_modifying = function(cell)
    local c, z = cell.c, cell.z
    cell.c = add(mul(c, c, c), z, c)
  end
end

local update_cell_functions_dispatch_modifying
do
  local add = vm.utils.bake('add', {'complex', 'complex', 'complex'})
  local mul = vm.utils.bake('mul', {'complex', 'complex', 'complex'})
  update_cell_functions_dispatch_modifying = function(cell)
    local c, z = cell.c, cell.z
    cell.c = add(mul(c, c, c), z, c)
  end
end

-- pick which one you want here.

local update_cell = update_cell_functions_dispatch_modifying

function mandelbrot:update(dt)
  for _,cell in ipairs(self.cells) do
    if not cell.dead then
      update_cell(cell)
      if vm.abs(cell.c) > 2 then
        cell.dead = true
        table.insert(self.killed_cells, cell)
      end
    end
  end
  self.n = self.n + 1
  print(self.n,dt)
end

local function choose_color(n)
  local r,g,b
  if n < 50 then
    r,g,b = n / 50, 0, 0
  elseif n < 100 then
    r, g, b = 1, (n - 50) / 50, 0
  elseif n < 125 then
    r, g, b = 1, 1, (n - 100) / 25
  else
    r, g, b = 1, 1, 1
  end
  return {r,g,b}
end

function mandelbrot:draw()
  love.graphics.setCanvas(self.my_canvas)
  love.graphics.setColor(choose_color(self.n))
  for _,cell in ipairs(self.killed_cells) do
    love.graphics.points(cell.loc[1], cell.loc[2])
  end
  self.killed_cells = {}
  love.graphics.setCanvas()
  love.graphics.scale(0.5)
  love.graphics.draw(self.my_canvas)
end

function mandelbrot:keypressed(key, scancode, keyrepeat)

end

function mandelbrot:exit()
end

return mandelbrot