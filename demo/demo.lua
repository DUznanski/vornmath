local demo = {}

local menu_text = [[
1. mandelbrot (give it a moment it has to think a lot at the start)
2. tesseract
3. geodesic
]]

function demo:enter()

end

function demo:exit()

end

function demo:update(dt)

end

function demo:draw()
    love.graphics.print(menu_text)
end

function demo:keypressed(key, scancode, keyrepeat)
    if scancode == '1' then change_state("mandelbrot") end
    if scancode == '2' then change_state("tesseract") end
    if scancode == '3' then change_state("geodesic") end
end

return demo