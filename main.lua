local states = {}

states.demo = require('demo.demo')
--states.tesseract = require('demo.tesseract')
states.mandelbrot = require('demo.mandelbrot')

local state = "demo"

function change_state(new_state)
    states[state]:exit()
    state = new_state
    states[state]:enter()
end

function love.update(dt)
    states[state]:update(dt)
end

function love.draw()
    states[state]:draw()
end

function love.keypressed(key, scancode, keyrepeat)
    if scancode == 'escape' then
        change_state("demo")
    end
    states[state]:keypressed(key, scancode, keyrepeat)
end