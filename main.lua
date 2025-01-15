local states = {}

states.demo = require('demo.demo')
states.tesseract = require('demo.tesseract')
states.mandelbrot = require('demo.mandelbrot')
states.geodesic = require('demo.geodesic')
states.bezier = require('demo.bezier')
states.prism = require('demo.prism')

local state = "demo"

function change_state(new_state)
    if states[state].exit then states[state]:exit() end
    state = new_state
    if states[state].enter then states[state]:enter() end
end

function love.update(dt)
    if states[state].update then states[state]:update(dt) end
end

function love.draw()
    if states[state].draw then states[state]:draw() end
end

function love.keypressed(key, scancode, keyrepeat)
    if scancode == 'escape' then
        if state == 'demo' then love.event.quit() end
        change_state("demo")
    end
    if states[state].keypressed then states[state]:keypressed(key, scancode, keyrepeat) end
end

function love.mousepressed(x, y, button, isTouch)
    if states[state].mousepressed then states[state]:mousepressed(x,y,button,isTouch) end
end

function love.mousereleased(x, y, button, isTouch)
    if states[state].mousereleased then states[state]:mousereleased(x,y,button,isTouch) end
end

function love.mousemoved(x, y, dx, dy)
    if states[state].mousemoved then states[state]:mousemoved(x,y,dx,dy) end
end

function love.wheelmoved(x, y)
    if states[state].wheelmoved then states[state]:wheelmoved(x,y) end
end