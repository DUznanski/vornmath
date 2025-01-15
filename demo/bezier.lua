local vm = require('vornmath')

local instructions = [[drag circle: move control point
mouse wheel: adjust control weight
]]

local bezier = {}

local POWER = 2^(1/3) -- value to multiply the weight by when ticking the wheel up
local MAX_WEIGHT = 8 -- maximum possible weight (and 1/minimum possible weight)
local CONTROL_RADIUS = 30 -- size of the circle
local CONTROL_FILL = {0,0.5,0} -- color of the weight control
local WHITE = {1,1,1} -- white
local SEGMENT_COUNT = 512 -- number of segments to draw

local edge_x, edge_y = love.graphics.getDimensions()
local TOP_LEFT = vm.vec3(0,0,1 / MAX_WEIGHT) -- the extents of the window.
local BOTTOM_RIGHT = vm.vec3(edge_x, edge_y, MAX_WEIGHT)

-- the starting control points.  The third coordinate is weight.
local control_points = {
    vm.vec3(100,100,1),
    vm.vec3(200,500,1),
    vm.vec3(500,100,2),
    vm.vec3(700,300,1)
}

-- used with the mouse events to decide what we're moving
local active_index

local function legalize_control_point(p)
    vm.clamp(p, TOP_LEFT, BOTTOM_RIGHT, p) -- clamp it to the screen
end

local function move_control_point(i, new_x, new_y)
    local p = control_points[i]
    p.x = new_x
    p.y = new_y
    legalize_control_point(p)
end

local function change_control_weight(i, clicks)
    local p = control_points[i]
    p.z = p.z * POWER ^ clicks
    legalize_control_point(p)
end

local function near_control_point(x, y)
    local target = vm.vec2(x,y)
    for i,p in ipairs(control_points) do
        if vm.distance(target, p.xy) <= CONTROL_RADIUS then
            return i
        end
    end
end

local function draw_control_point(i)
    local p = control_points[i]
    -- we represent the weight as a "sphere" with the corresponding volume
    -- this makes the weight value look natural
    local weight_radius = CONTROL_RADIUS * (p.z / MAX_WEIGHT) ^ (1/3)
    love.graphics.setColor(CONTROL_FILL)
    love.graphics.circle("fill", p.x, p.y, weight_radius)
    love.graphics.setColor(WHITE)
    love.graphics.circle("line", p.x, p.y, CONTROL_RADIUS)
end

local function draw_curve()
    local points = {}
    for i = 0, SEGMENT_COUNT do
        local old_controls = {}
        for j, p in ipairs(control_points) do
            old_controls[j] = vm.vec3(p.xy * p.z, p.z) -- convert the point to homogeneous coordinates
        end
        local new_controls = {}
        local t = i / SEGMENT_COUNT
        -- this is de Casteljau's algorithm:
        -- reduce the number of control points by lerping consecutive pairs,
        -- until we're down to just one.
        while #old_controls > 1 do
            for j = 1, #old_controls - 1 do
                new_controls[j] = vm.mix(old_controls[j], old_controls[j+1], t)
            end
            old_controls = new_controls
            new_controls = {}
        end
        local p = old_controls[1]
        -- then we project the coordinates onto the plane and add them to the polyline.
        points[2*i + 1] = p.x / p.z
        points[2*i + 2] = p.y / p.z
    end
    love.graphics.line(points)
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