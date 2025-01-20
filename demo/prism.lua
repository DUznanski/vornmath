local vm = require('vornmath')

local prism = {}

local LEFT_TARGET = vm.vec2(100,100)
local LEFT_NORMAL = vm.vec2(math.cos(math.rad(-150)), math.sin(math.rad(-150)))
local RIGHT_NORMAL = vm.vec2(math.cos(math.rad(150)), math.sin(math.rad( 150)))
local CAUCHY_A = 1.6700 -- the A value for Cauchy's equation
local CAUCHY_B = 0.00743 -- the B value
local VIOLET_END = 0.380 -- wavelength of the violet end of the spectrum image, in μm
local RED_END = 0.750 -- "" "" red end "" ""
local TRIANGLE_APEX = LEFT_TARGET + 50*vm.vec2(1,-math.sqrt(3))
local TRIANGLE_LEFT_CORNER = LEFT_TARGET - 50 * vm.vec2(1,-math.sqrt(3))
local TRIANGLE_RIGHT_CORNER = TRIANGLE_LEFT_CORNER + vm.vec2(200,0)
local LINES = 200
local LEFT_SCREEN_SOURCE = vm.vec2(0,0)
local SCREEN_EDGE_NORMAL = vm.vec2(1,0)
local RIGHT_SCREEN_SOURCE = vm.vec2(800,600)

local function refractive_index(wavelength)
    return CAUCHY_A + CAUCHY_B / wavelength^2
end

local function lightray_line_intersect(ray_source, ray_along, line_source, line_normal)
    local ray_normal = vm.normalize(vm.vec2(-ray_along.y, ray_along.x))
    local ray_distance = vm.dot(ray_source, ray_normal)
    local ray_hesse = vm.vec3(ray_normal, -ray_distance)
    line_normal = vm.normalize(line_normal)
    local line_distance = vm.dot(line_source, line_normal)
    local line_hesse = vm.vec3(line_normal, -line_distance)
    local intersection_result = vm.cross(ray_hesse, line_hesse)
    return intersection_result.xy / intersection_result.z
end

-- first things first: where is my start point?
-- I want to pass through the prism exactly horizontal for the central wavelength, so

local central_wavelength = (VIOLET_END + RED_END) / 2
local due_left = vm.vec2(-1,0)
local central_index = refractive_index(central_wavelength)
local incident_vector = -vm.refract(due_left, -LEFT_NORMAL, central_index) -- negative so it's going right for later calculations

-- given that I can figure out what my ray looks like


local starting_point = lightray_line_intersect(LEFT_TARGET, incident_vector, LEFT_SCREEN_SOURCE, SCREEN_EDGE_NORMAL)

local rainbow
local rainbow_width
function prism:enter()
    rainbow = love.image.newImageData('demo/spectrum.png')
    rainbow_width = rainbow:getWidth()
end

function prism:draw()
    love.graphics.line(starting_point.x, starting_point.y, LEFT_TARGET.x, LEFT_TARGET.y)
    love.graphics.line(
        TRIANGLE_APEX.x, TRIANGLE_APEX.y,
        TRIANGLE_LEFT_CORNER.x, TRIANGLE_LEFT_CORNER.y,
        TRIANGLE_RIGHT_CORNER.x, TRIANGLE_RIGHT_CORNER.y,
        TRIANGLE_APEX.x, TRIANGLE_APEX.y
    )
    love.graphics.setBlendMode('add')
    for i = 0,LINES do
        local t = i / LINES
        local wavelength = vm.mix(VIOLET_END, RED_END, t)
        local rainbow_target = vm.round(vm.mix(0, rainbow_width - 1, t))
        love.graphics.setColor(vm.vec4(rainbow:getPixel(rainbow_target, 0))/3)
        local ior = refractive_index(wavelength)
        local crossing_vector = vm.refract(incident_vector, LEFT_NORMAL, 1/ior)
        local exit_point = lightray_line_intersect(LEFT_TARGET, crossing_vector, TRIANGLE_APEX, RIGHT_NORMAL)
        local exit_vector = vm.refract(crossing_vector, RIGHT_NORMAL, ior)
        local right_point = lightray_line_intersect(exit_point, exit_vector, RIGHT_SCREEN_SOURCE, SCREEN_EDGE_NORMAL)

        love.graphics.line(
            LEFT_TARGET.x, LEFT_TARGET.y,
            exit_point.x, exit_point.y,
            right_point.x, right_point.y
        )
    end
    love.graphics.setBlendMode('alpha')
    love.graphics.setColor(1,1,1)
end

return prism
