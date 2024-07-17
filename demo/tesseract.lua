local vm = require('vornmath')

local tesseract = {}

function tesseract:enter()
    local colors = {
        {0xff/255, 0x9c/255, 0x8e/255, 1},
        {0xff/255, 0xd9/255, 0x7b/255, 1},
        {0xaf/255, 0xff/255, 0xbb/255, 1},
        {0x62/255, 0xeb/255, 0xff/255, 1},
        {0x91/255, 0xae/255, 0xff/255, 1},
        {0xff/255, 0xb7/255, 0xfb/255, 1}
    }
    local directions = vm.vec4(1,4,16,64)
    local single_cube = {}
    local color_index = 0
    -- okay so we have to build the model.
    -- pick a pair of directions that this face follows
    for i = 1,3 do
        for j = i+1, 4 do
            local spares = {}
            -- figure out which two we didn't pick
            for sp = 1,4 do
                if sp ~= i and sp ~= j then table.insert(spares, sp) end
            end
            -- make the two triangles where the spares don't matter
            local iward, jward, kward, lward = directions[i], directions[j], directions[spares[1]], directions[spares[2]]

            local two_tris = {1, 1 + iward, 1 + iward + jward, 1, 1 + jward, 1 + iward + jward}
            -- then duplicate them into the spares locations
            for k_flag = 0,1 do
                for l_flag = 0,1 do
                    for _,vertex in ipairs(two_tris) do
                        table.insert(single_cube, vertex + k_flag * kward + l_flag * lward + color_index * 256)
                    end
                end
            end
            color_index = color_index + 1
        end
    end
    -- now the tricky part: put cubes in for corners *and* edges.
    local direction_vectors = {vm.vec4(1,0,0,0), vm.vec4(0,1,0,0), vm.vec4(0,0,1,0), vm.vec4(0,0,0,1)}
    local corner_vectors = {vm.vec4(0)}
    for _, dir in ipairs(direction_vectors) do
        local current_length = #corner_vectors
        for i = 1,current_length do
            table.insert(corner_vectors, corner_vectors[i] + dir * 2)
        end
    end
    
    -- with these, now I can add the edges...
    local current_length = #corner_vectors
    for i, dir in ipairs(direction_vectors) do
        for below = 1, current_length do
            if corner_vectors[below][i] == 0 then
                table.insert(corner_vectors, corner_vectors[below] + dir)
            end
        end
    end

    -- these are really just used to make indices though so we'll convert back from thingy to index
    local corner_indices = {}
    for _, corner in ipairs(corner_vectors) do
        table.insert(corner_indices, vm.dot(directions, corner))
    end
    -- and then add them to the cube indices from earlier
    local all_triangles = {}
    for _, corner_index in ipairs(corner_indices) do
        for _, cube_index in ipairs(single_cube) do
            table.insert(all_triangles, cube_index + corner_index)
        end
    end
    -- and finally we need the actual coordinates
    local vertices = {}
    local actual_coordinates = {-1, -15/16, 15/16, 1}
    for _,color in ipairs(colors) do
        for _,x in ipairs(actual_coordinates) do
            for _,y in ipairs(actual_coordinates) do
                for _,z in ipairs(actual_coordinates) do
                    for _,w in ipairs(actual_coordinates) do
                        local vertex = {x,y,z,w}
                        for _,c in ipairs(color) do
                            table.insert(vertex, c)
                        end
                        table.insert(vertices, vertex)
                    end
                end
            end
        end
    end
    self.vertices = vertices
    self.triangles = all_triangles
    self.world_from_model = vm.mat4()
    self.w_distance = 2
    -- build the camera here.
    local camera_position = vm.vec3(4,2,8)
    local gravity_up = vm.vec3(0,1,0)
    local camera_forward = -vm.normalize(camera_position)
    local camera_right = vm.normalize(vm.cross(gravity_up, camera_forward))
    local camera_up = vm.normalize(vm.cross(camera_forward, camera_right))
    local camera_aim = vm.mat4(vm.transpose(vm.mat3(camera_right, camera_up, camera_forward)))
    local camera_translate = vm.mat4(1,0,0,0, 0,1,0,0, 0,0,1,0, -camera_position, 1)
    local distance_to_center = vm.length(camera_position)
    local fov_radius = 3
    local near = distance_to_center - fov_radius
    local far = distance_to_center + fov_radius
    local screen = vm.vec2(love.graphics.getDimensions())
    local aspect_ratio = screen / math.min(screen.x, screen.y)
    local field_of_view = distance_to_center / (fov_radius * aspect_ratio)
    local perspective = vm.mat4(field_of_view.x,0,0,0, 0,field_of_view.y,0,0, 0,0,far/(2*fov_radius),1, 0,0,-near*far/(2*fov_radius),0)
    self.camera_matrix = perspective * camera_aim * camera_translate
    self.persepective_shader = love.graphics.newShader('demo/tesseract.vert')
    self.persepective_shader:send('WORLD_FROM_MODEL', "column", self.world_from_model)
    self.persepective_shader:send('HYPER_DISTANCE', self.w_distance)
    self.persepective_shader:send('VIEW_FROM_WORLD', "column", self.camera_matrix)
    self.mesh = love.graphics.newMesh({{"VertexPosition", "float", 4},{"VertexColor", "float", 4}}, self.vertices, "triangles", "static")
    self.mesh:setVertexMap(self.triangles)
    love.graphics.setDepthMode("less",true)
end

local function hyper_rotation(dt, upkey, downkey, axis_1, axis_2, rotation_matrix)
    local i = vm.complex(0,1)
    local multiplier = 0
    if love.keyboard.isScancodeDown(upkey) then multiplier = multiplier + 1 end
    if love.keyboard.isScancodeDown(downkey) then multiplier = multiplier - 1 end
    local angle = i ^ (dt * multiplier)
    local mat = vm.mat4()
    mat[axis_1][axis_1] = angle.a
    mat[axis_2][axis_2] = angle.a
    mat[axis_1][axis_2] = angle.b
    mat[axis_2][axis_1] = -angle.b
    rotation_matrix = vm.mul(mat, rotation_matrix, rotation_matrix)
    return rotation_matrix
end

function tesseract:update(dt)
    self.world_from_model = hyper_rotation(dt, 'd', 'a', 1, 3, self.world_from_model)
    self.world_from_model = hyper_rotation(dt, 's', 'w', 2, 3, self.world_from_model)
    self.world_from_model = hyper_rotation(dt, 'e', 'q', 1, 2, self.world_from_model)
    self.world_from_model = hyper_rotation(dt, 'j', 'l', 1, 4, self.world_from_model)
    self.world_from_model = hyper_rotation(dt, 'i', 'k', 2, 4, self.world_from_model)
    self.world_from_model = hyper_rotation(dt, 'o', 'u', 3, 4, self.world_from_model)
    -- update the world from model matrix based on keypresses
    -- send that matrix to my shader
    self.persepective_shader:send('WORLD_FROM_MODEL', "column", self.world_from_model)
end

local instructions = [[
ws, ad, qe, ik, jl, uo: rotate the cube in space
r: reset the cube's rotation
]]

function tesseract:draw()
    love.graphics.print(instructions)
    love.graphics.setShader(self.persepective_shader)
    love.graphics.draw(self.mesh)
    love.graphics.setShader()
end

function tesseract:exit()
    love.graphics.setShader()
end

function tesseract:keypressed(key, scancode)
    if scancode == 'r' then
        self.world_from_model = vm.mat4()
    end
end

return tesseract