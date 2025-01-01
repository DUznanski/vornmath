local vm = require('vornmath')

local instructions = [[drag circle: move control point
mouse wheel: adjust control weight
]]

local bezier = {}

local POWER = 2^(1/3)
local MAX_POWER = 8
local CONTROL_RADIUS = 30
local CONTROL_FILL = {0,0.5,0}
local WHITE = {1,1,1}
local SEGMENT_COUNT = 128

local control_points = {
    vm.vec3(100,100,1),
    vm.vec3(200,500,1),
    vm.vec3(1000,200,2),
    vm.vec3(700,300,1)
}

local active_index

local function legalize_control_point(p)
    local z = p.z
    p = vm.div(p, z, p)
    p = vm.clamp(p, vm.vec3(0,0,1), vm.vec3(800,600,1), p)
    z = vm.clamp(z, 1/MAX_POWER, MAX_POWER)
    p = vm.mul(p, z, p)
    return p
end

local function move_control_point(i, new_x, new_y)
    local p = control_points[i]
    p.x = new_x * p.z
    p.y = new_y * p.z
    legalize_control_point(p)
end

local function change_control_weight(i, clicks)
    local p = control_points[i]
    p = vm.mul(p, POWER ^ clicks, p)
    legalize_control_point(p)
end

local function near_control_point(x, y)
    local target = vm.vec2(x,y)
    for i,p in ipairs(control_points) do
        if vm.distance(vm.vec2(x,y), p.xy / p.z) <= CONTROL_RADIUS then
            return i
        end
    end
end

local function draw_control_point(i)
    local p = control_points[i]
    local z = p.z
    p = p / z
    local weight_radius = CONTROL_RADIUS * (z / MAX_POWER) ^ (1/3)
    love.graphics.setColor(CONTROL_FILL)
    love.graphics.circle("fill", p.x, p.y, weight_radius)
    love.graphics.setColor(WHITE)
    love.graphics.circle("line", p.x, p.y, CONTROL_RADIUS)
end

local function draw_curve()
    local points = {}
    for i = 0, SEGMENT_COUNT do
        local old_controls = control_points
        local new_controls = {}
        local t = i / SEGMENT_COUNT
        while #old_controls > 1 do
            for j = 1,#old_controls - 1 do
                new_controls[j] = vm.mix(old_controls[j], old_controls[j+1], t)
            end
            old_controls = new_controls
            new_controls = {}
        end
        local p = old_controls[1]
        points[2*i+1] = p.x / p.z
        points[2*i + 2] = p.y / p.z
    end
    love.graphics.line(points)
end

function bezier:enter()

end

function bezier:exit()

end

function bezier:update(dt)

end

function bezier:draw()
    love.graphics.print(instructions)
    for i = 1,4 do
        draw_control_point(i)
    end
    draw_curve()
end

function bezier:mousepressed(x, y, button, isTouch)
    if button == 1 then
        active_index = near_control_point(x, y)
    end
end

function bezier:mousereleased(x, y, button, isTouch)
    if button == 1 then
        active_index = nil
    end
end

function bezier:mousemoved(x, y)
    if active_index then
        move_control_point(active_index, x, y)
    end
end

function bezier:wheelmoved(x, y)
    local target = near_control_point(love.mouse.getPosition())
    if target then
        change_control_weight(target, y)        
    end
end

return bezier