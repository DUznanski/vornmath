---@diagnostic disable: lowercase-global
local lu = require('test.luaunit')
local vm = require('init')


function testVec2Exists()
	local a = vm.vec2(1,2)
	lu.assertNotNil(a)
end

function testVec2TableConstructor()
	local a = vm.vec2({1,2})
	lu.assertNotNil(a)
end

function testVec2ComponentAccess()
	local a = vm.vec2(1,2)
	lu.assertEquals(a.x, 1)
	lu.assertEquals(a.y, 2)
	lu.assertError(function() return a.z end)
end

function testVec2IndexAccess()
	local a = vm.vec2(1,2)
	lu.assertEquals(a[1], 1)
	lu.assertEquals(a[2], 2)
end

function testVec3Exists()
	local a = vm.vec3(1,2,3)
	lu.assertNotNil(a)
end

function testVec3TableConstructor()
	local a = vm.vec3({1,2,3})
	lu.assertNotNil(a)
end

function testVec3ComponentAccess()
	local a = vm.vec3(1,2,3)
	lu.assertEquals(a.x, 1)
	lu.assertEquals(a.y, 2)
	lu.assertEquals(a.z, 3)
	lu.assertError(function() return a.w end) -- no this is wrong it should actually check for either error or nil.
end

function testVec3IndexAccess()
	local a = vm.vec3(1,2,3)
	lu.assertEquals(a[1], 1)
	lu.assertEquals(a[2], 2)
	lu.assertEquals(a[3], 3)
end

function testVec4Exists()
	local a = vm.vec4(1,2,3,4)
	lu.assertNotNil(a)
end

function testVec4TableConstructor()
	local a = vm.vec4({1,2,3,4})
	lu.assertNotNil(a)
end

function testVec4ComponentAccess()
	local a = vm.vec4(1,2,3,4)
	lu.assertEquals(a.x, 1)
	lu.assertEquals(a.y, 2)
	lu.assertEquals(a.z, 3)
	lu.assertEquals(a.w, 4)
end

function testVec4IndexAccess()
	local a = vm.vec4(1,2,3,4)
	lu.assertEquals(a[1], 1)
	lu.assertEquals(a[2], 2)
	lu.assertEquals(a[3], 3)
	lu.assertEquals(a[4], 4)
end

function testSwizzle()
	local a = vm.vec2(1,2)
	local b = a.yx
	lu.assertEquals(b[1], 2)
	lu.assertEquals(b[2], 1)
	lu.assertError(function() return a.xz end)
	lu.assertError(function() return a.rs end)
end

function testSetSwizzle()
	local a = vm.vec3(1,2,3)
	a.xy = {4,5}
	lu.assertEquals(a[1], 4)
	lu.assertEquals(a[2], 5)
	lu.assertError(function() a.xx = {7,8} end)
	lu.assertError(function() a.w = {9} end)
	lu.assertError(function() a.xz = 10 end)
	lu.assertError(function() a.xyz = {11, 12} end)
	lu.assertError(function() a.ry = {13,14} end)
	a.p = 6
	lu.assertEquals(a[3], 6)
	a[1] = 7
	lu.assertEquals(a[1], 7)
end

function testMatrixConstruct()
	local a = vm.vec4(1,2,3,4)
	local m = vm.mat2(a)
	lu.assertEquals(m[1].x, 1)
	lu.assertEquals(m[1].y, 2)
	lu.assertEquals(m[2].x, 3)
	lu.assertEquals(m[2].y, 4)
	local b = {5,6,7,8}
	local n = vm.mat2x4(a,b)
	lu.assertEquals(n[1].x, 1)
	lu.assertEquals(n[2].z, 7)

end



os.exit(lu.LuaUnit.run())