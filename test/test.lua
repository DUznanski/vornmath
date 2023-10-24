---@diagnostic disable: lowercase-global
local lu = require('test.luaunit')
local vm = require('vornmath')

function testComplexEquals()
    local a = vm.complex(3,4)
    local b = vm.complex(3,4)
    local c = vm.complex(3,0)
    local d = vm.complex(3)
    lu.assertIsTrue(vm.eq(a,b))
    lu.assertIsFalse(vm.eq(a,c))
    lu.assertIsTrue(vm.eq(c,3))
    lu.assertEquals(a, b)
    lu.assertNotEquals(a, c)
    lu.assertEquals(c, d)
end

function testComplexAddition()
    local a = vm.complex(2,3)
    local b = vm.complex(-3,5)
    local c = 4
    lu.assertEquals(a + b, vm.complex(-1,8))
    lu.assertEquals(a + c, vm.complex(6,3))
    lu.assertEquals(c + b, vm.complex(1,5))
end

function testComplexSubtraction()
    local a = vm.complex(2,3)
    local b = vm.complex(-3,5)
    local c = 4
    lu.assertEquals(a - b, vm.complex(5,-2))
    lu.assertEquals(a - c, vm.complex(-2,3))
    lu.assertEquals(c - b, vm.complex(7,-5))
end

function testComplexMultiplication()
    local a = vm.complex(2,3)
    local b = vm.complex(-3,5)
    local c = 4
    lu.assertEquals(a * b, vm.complex(-21,1))
    lu.assertEquals(a * c, vm.complex(8,12))
    lu.assertEquals(c * b, vm.complex(-12,20))
end

function testComplexDivision()
    local a = vm.complex(-21,1)
    local b = vm.complex(2,3)
    local c = vm.complex(24,-32)
    local d = 4
    local e = vm.complex(1,1)
    lu.assertEquals(a / b, vm.complex(-3,5))
    lu.assertEquals(c / d, vm.complex(6,-8))
    lu.assertEquals(d / e, vm.complex(2,-2))
end

function testComplexNegation()
    local a = vm.complex(-2,3)
    lu.assertEquals(-a, vm.complex(2,-3))
end

function testComplexPower()
    lu.assertAlmostEquals(vm.complex(-1)^0.5, vm.complex(0,1))
    lu.assertAlmostEquals(math.exp(1)^vm.complex(0,math.pi), vm.complex(-1,0))
    lu.assertAlmostEquals(vm.complex(0,1)^vm.complex(0,1), vm.complex(math.exp(-math.pi/2)))
end

function testQuatAddition()
    local a = vm.quat(1,2,3,4)
    local b = vm.complex(5,6)
    local c = 7
    lu.assertEquals(a + a, vm.quat(2,4,6,8))
    lu.assertEquals(a + b, vm.quat(6,8,3,4))
    lu.assertEquals(a + c, vm.quat(8,2,3,4))
    lu.assertEquals(b + a, vm.quat(6,8,3,4))
    lu.assertEquals(c + a, vm.quat(8,2,3,4))
end

function testQuatSubtraction()
    local a = vm.quat(1,2,3,4)
    local b = vm.complex(5,6)
    local c = 7
    lu.assertEquals(a - a, vm.quat(0,0,0,0))
    lu.assertEquals(a - b, vm.quat(-4,-4,3,4))
    lu.assertEquals(a - c, vm.quat(-6,2,3,4))
    lu.assertEquals(b - a, vm.quat(4,4,-3,-4))
    lu.assertEquals(c - a, vm.quat(6,-2,-3,-4))
end

function testQuatMultiplication()
    local neg1 = vm.quat(-1,0,0,0)
    local i = vm.quat(0,1,0,0)
    local j = vm.quat(0,0,1,0)
    local k = vm.quat(0,0,0,1)
    lu.assertEquals(i*i, neg1)
    lu.assertEquals(j*j, neg1)
    lu.assertEquals(k*k, neg1)
    lu.assertEquals(i*j*k, neg1)
    lu.assertEquals(i*j, k)
    lu.assertEquals(j*i, -k)
    lu.assertEquals(k*i, j)
    lu.assertEquals(i*k, -j)
    lu.assertEquals(j*k, i)
    lu.assertEquals(k*j, -i)
    local a = vm.quat(1,2,3,4)
    local b = vm.complex(5,6)
    local c = 7
    lu.assertEquals(a*a, vm.quat(-28,4,6,8))
    lu.assertEquals(a*b, vm.quat(-7,16,39,2))
    lu.assertEquals(b*a, vm.quat(-7,16,-9,38))
    lu.assertEquals(a*c, vm.quat(7,14,21,28))
    lu.assertEquals(c*a, vm.quat(7,14,21,28))
end

function testQuatDivision()
    -- I can't think of any other clever ones.
    lu.assertEquals(vm.quat(2,2,0,0) / vm.quat(1,1,1,1), vm.quat(1,0,0,-1))
end

function testQuatNegation()
    local a = vm.quat(1,-2,3,-4)
    lu.assertEquals(-a, vm.quat(-1,2,-3,4))
end


function testVectorNilConstruction()
    local two = vm.vec2()
    local three = vm.vec3()
    local four = vm.vec4()
    for k = 1,2 do
        lu.assertEquals(two[k], 0)
    end
    for k = 1,3 do
        lu.assertEquals(three[k], 0)
    end
    for k = 1,4 do
        lu.assertEquals(four[k], 0)
    end
end

function testVectorSingleConstruction()
    local two = vm.vec2(2)
    local three = vm.vec3(3)
    local four = vm.vec4(4)
    for k = 1,2 do
        lu.assertEquals(two[k], 2)
    end
    for k = 1,3 do
        lu.assertEquals(three[k], 3)
    end
    for k = 1,4 do
        lu.assertEquals(four[k], 4)
    end
end

function testVectorPileConstruction()
    local one = 1
    local two = vm.vec2(2,3)
    local three = vm.vec3(4,5,6)
    local four = vm.vec4(7,8,9,10)
    for k = 1,2 do
        lu.assertEquals(two[k], 1+k)
    end
    for k = 1,3 do
        lu.assertEquals(three[k], 3+k)
    end
    for k = 1,4 do
        lu.assertEquals(four[k], 6+k)
    end
    local twotwice = vm.vec4(two, two)
    lu.assertEquals(twotwice[1], 2)
    lu.assertEquals(twotwice[2], 3)
    lu.assertEquals(twotwice[3], 2)
    lu.assertEquals(twotwice[4], 3)
    local fourdemoted = vm.vec2(four)
    lu.assertEquals(fourdemoted[1], 7)
    lu.assertEquals(fourdemoted[2], 8)
end

function testVectorEquals()
    lu.assertEquals(vm.vec3(1,2,3), vm.vec3(1,2,3))
    lu.assertNotEquals(vm.vec3(1,2,3), vm.vec3(1,3,3))
end

function testVectorFill()
    local a = vm.vec3(1,2,3)
    local b = vm.vec3(4,5,6)
    vm.fill(a,b)
    lu.assertEquals(a, b)
    local c = vm.vec3()
    vm.fill(a)
    lu.assertEquals(a,c)
end

function testBooleanVector()
    local a = vm.bvec2()
    local b = vm.bvec3(true)
    local c = vm.bvec4(b,a)
    lu.assertEquals(c[1], true)
    lu.assertEquals(c[2], true)
    lu.assertEquals(c[3], true)
    lu.assertEquals(c[4], false)
end

function testComplexVector()
    local a = vm.cvec2()
    lu.assertEquals(a[1], vm.complex(0))
    lu.assertEquals(a[2], vm.complex(0))
    local b = vm.cvec2(1)
    lu.assertEquals(b[1], vm.complex(1,0))
    local c = vm.cvec3(vm.complex(1,2))
    lu.assertEquals(c[1], vm.complex(1,2))
    lu.assertEquals(c[2], vm.complex(1,2))
    lu.assertEquals(c[3], vm.complex(1,2))
    local d = vm.cvec4(c,5)
    lu.assertEquals(d[1], vm.complex(1,2))
    lu.assertEquals(d[2], vm.complex(1,2))
    lu.assertEquals(d[3], vm.complex(1,2))
    lu.assertEquals(d[4], vm.complex(5))
end

function testBVecFill()
    local a = vm.bvec2(false, true)
    local b = vm.bvec2(true, false)
    vm.fill(a,b)
    lu.assertEquals(a, b)
    local c = vm.bvec2()
    vm.fill(a,c)
    lu.assertEquals(a,c)
    lu.assertNotEquals(a,b)
end

function testCVecFill()
    local a = vm.cvec2(1, 2)
    local b = vm.cvec2(3, vm.complex(0,1))
    vm.fill(a,b)
    lu.assertEquals(a, b)
    local c = vm.cvec2()
    vm.fill(a,c)
    lu.assertEquals(a,c)
    lu.assertNotEquals(a,b)
end

function testMatrixConstruct()
    local a = vm.mat4x2()
    lu.assertEquals(a[1][1], 1)
    lu.assertEquals(a[3][2], 0)
    local b = vm.cmat3x4()
    lu.assertEquals(b[2][2], vm.complex(1))
    lu.assertEquals(b[3][4], vm.complex(0))
    local c = vm.mat2x2(3)
    lu.assertEquals(c[1][1], 3)
    lu.assertEquals(c[1][2], 0)
    local d = vm.mat2x3(vm.vec3(1,2,3), vm.vec3(4,5,6))
    lu.assertEquals(d[1][1],1)
    lu.assertEquals(d[2][2],5)
    local e = vm.cmat2x2(vm.vec4(1,2,3,4))
    lu.assertEquals(e[1][2], vm.complex(2))
end

os.exit(lu.LuaUnit.run())