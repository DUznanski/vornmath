local vm = require('vornmath')

local DETAIL = 10
local STEPS = DETAIL * 3
local WIDTH = STEPS + 1
local WHOLE_FACE_SIZE = WIDTH * (WIDTH + 1) / 2

local geodesic = {}

local PHI = (1 + math.sqrt(5)) / 2

-- every coordinate we make is going in a big array

local function index_from_coordinates(face, u, v)
    local v_offset = ((2*WIDTH + 1) * v - v * v) / 2
    return (face - 1) * WHOLE_FACE_SIZE + v_offset + u + 1
end

local function annotated_vertex(corner, center)
    return {
        corner[1], corner[2], corner[3], 1,
        center[1], center[2], center[3],
        center[1], center[2], center[3]
    }
end

local function index_triangle(t, base, offset_1, offset_2)
    table.insert(t, base)
    table.insert(t, base + offset_1)
    table.insert(t, base + offset_2)
end

function geodesic:enter()
    local p = vm.normalize(vm.vec3(1, PHI, 0))
    local negate_x = vm.vec3(-1,1,1)
    local negate_y = vm.vec3(1,-1,1)
    local negate_z = vm.vec3(1,1,-1)
    local corners = {
        p.xyz,            --  small  big    0
        p.zxy,            --  0      small  big
        p.yzx,            --  big    0      small
        p.xyz * negate_x, -- -small  big    0
        p.yzx * negate_x, -- -big    0      small
        p.xyz * negate_y, --  small -big    0
        p.zxy * negate_y, --  0     -small  big
        p.zxy * negate_z, --  0      small -big
        p.yzx * negate_z, --  big    0     -small
        -p.xyz,       -- -small -big    0
        -p.zxy,       --  0     -small -big
        -p.yzx        -- -big    0     -small
    }

    local big_triangles = { -- indices into the vertices pile; each triad is the corners of one of the big triangles
        {1,2,3}, {1,3,9}, {1,4,2}, {1,8,4}, {1,9,8},
        {2,4,5}, {2,5,7}, {2,7,3}, {3,6,9}, {3,7,6},
        {4,8,12}, {4,12,5}, {5,10,7}, {5,12,10}, {6,7,10},
        {6,10,11}, {6,11,9}, {8,9,11}, {8,11,12}, {10,12,11}
    }

    self.vertices = {}
    self.vertex_indices = {}
    for face_id, face in ipairs(big_triangles) do
        -- what are the quats that rotate between the corners?
        local a = corners[face[1]]
        local b = corners[face[2]]
        local c = corners[face[3]]
        local ab_rotation = vm.quat(a,b)
        local bc_rotation = vm.quat(b,c)
        local ca_rotation = vm.quat(c,a)
        local ab_points = {}
        local bc_points = {}
        local ca_points = {}
        for i = 0, STEPS do
            ab_points[i] = ab_rotation^(i/STEPS) * a
            bc_points[i] = bc_rotation^(i/STEPS) * b
            ca_points[i] = ca_rotation^(i/STEPS) * c
        end
        local a_circles = {}
        local b_circles = {}
        local c_circles = {}
        for i = 0, STEPS - 1 do
            -- A neat trick: a great circle on the unit sphere can be described
            -- by the cross product of two points on the circle, which gives the axis
            -- and a point on two great circles can be described by the cross product
            -- of the axes of the two great circles.
            a_circles[i] = vm.normalize(vm.cross(ab_points[STEPS - i], ca_points[i]))
            b_circles[i] = vm.normalize(vm.cross(bc_points[STEPS - i], ab_points[i]))
            c_circles[i] = vm.normalize(vm.cross(ca_points[STEPS - i], bc_points[i]))
        end
        for v = 0, STEPS do
            local b_circle = b_circles[v]
            for u = 0, STEPS - v do
                local i = index_from_coordinates(face_id, u, v)
                -- okay here we go
                -- 1. get the three crosses and normalize
                local w = STEPS - u - v
                -- the corners are special: one of the great circles,
                -- if we had bothered calculating it, would have been degenerate.
                if u == STEPS then self.vertices[i] = a
                elseif v == STEPS then self.vertices[i] = b
                elseif w == STEPS then self.vertices[i] = c
                else
                    local a_circle = a_circles[u]
                    local c_circle = c_circles[w]
                    local ab_intersect = vm.normalize(vm.cross(a_circle, b_circle))
                    local bc_intersect = vm.normalize(vm.cross(b_circle, c_circle))
                    local ca_intersect = vm.normalize(vm.cross(c_circle, a_circle))
                    self.vertices[i] = vm.normalize(ab_intersect + bc_intersect + ca_intersect)
                end
            end
        end
    end
    self.annotated_vertices = {}
    for face_id = 1,20 do
        for u = 0, STEPS do
            for v = u % 3, STEPS - u, 3 do -- only every third; these are the centers of hexagons
                local starting_index = #self.annotated_vertices + 1
                local w = STEPS - v - u
                local center = self.vertices[index_from_coordinates(face_id, u, v)]
                table.insert(self.annotated_vertices, annotated_vertex(center, center))
                local starting_index = #self.annotated_vertices
                local success_count = 0
                local corner
                if w > 0 then -- these two push w down, so we don't want to do it if that would make it negative
                    corner = self.vertices[index_from_coordinates(face_id, u+1, v)]
                    table.insert(self.annotated_vertices, annotated_vertex(corner, center))
                    corner = self.vertices[index_from_coordinates(face_id, u, v+1)]
                    table.insert(self.annotated_vertices, annotated_vertex(corner, center))
                    success_count = success_count + 1
                end
                if u > 0 then
                    corner = self.vertices[index_from_coordinates(face_id, u-1, v+1)]
                    table.insert(self.annotated_vertices, annotated_vertex(corner, center))
                    corner = self.vertices[index_from_coordinates(face_id, u-1, v)]
                    table.insert(self.annotated_vertices, annotated_vertex(corner, center))
                    success_count = success_count + 1
                end
                if v > 0 then
                    corner = self.vertices[index_from_coordinates(face_id, u, v-1)]
                    table.insert(self.annotated_vertices, annotated_vertex(corner, center))
                    corner = self.vertices[index_from_coordinates(face_id, u+1, v-1)]
                    table.insert(self.annotated_vertices, annotated_vertex(corner, center))
                    success_count = success_count + 1
                end
                for i = 1, success_count * 2 - 1, 2 do
                    index_triangle(self.vertex_indices, starting_index, i, i+1)
                end
                if success_count == 2 then
                    if u > 0 then -- the two that we get are adjacent without crossing the loop
                        index_triangle(self.vertex_indices, starting_index, 2, 3)
                    else
                        index_triangle(self.vertex_indices, starting_index, 4, 1)
                    end
                end
                if success_count == 3 then
                    index_triangle(self.vertex_indices, starting_index, 2, 3)
                    index_triangle(self.vertex_indices, starting_index, 4, 5)
                    index_triangle(self.vertex_indices, starting_index, 6, 1)
                end
            end
        end
    end
    self.mesh = love.graphics.newMesh({{"VertexPosition", "float", 4}, {"VertexTexCoord", "float", 3}, {"VertexNormal", "float", 3}},self.annotated_vertices, "triangles", "static")
    self.mesh:setVertexMap(self.vertex_indices)
    local w,h = love.graphics.getDimensions()
    local aspect_w, aspect_h = w / math.min(w,h), h / math.min(w,h)
    self.camera_from_world = vm.mat4(0.8 / aspect_w,0,0,0, 0,0.8 / aspect_h,0,0, 0,0,1,0, 0,0,0,1)
    self.world_from_model = vm.mat4()
    self.tex = love.graphics.newCubeImage('demo/cubemap-horizontalstrip-earth.png')
    self.shader = love.graphics.newShader('demo/geodesic.vert')
    love.graphics.setShader(self.shader)
    self.shader:send('camera_from_world', 'column', self.camera_from_world)
    self.shader:send('world_from_model', 'column', self.world_from_model)
    self.shader:send('tex', self.tex)
    self.axial_tilt = vm.quat(vm.vec3(0,0,1), vm.rad(-23.5))
    self.t = 0
end

function geodesic:draw()
    love.graphics.draw(self.mesh)
end


function geodesic:update(dt)
    self.t = self.t + dt / 5
    self.world_from_model = vm.mat4(self.axial_tilt * vm.quat(vm.vec3(0,1,0), -self.t))
    self.shader:send('world_from_model', 'column', self.world_from_model)

end

function geodesic:exit()
    love.graphics.setShader()
end

function geodesic:keypressed() end

return geodesic