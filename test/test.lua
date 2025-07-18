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

function testQuatPower()
    local a = vm.quat(0,1,0,0)
    local b = vm.quat(0,0,1,0)
    lu.assertAlmostEquals(a^b,vm.quat(0,0,0,1))
end

function testAxisDecompose()
    local z, axis = vm.axisDecompose(vm.quat(1,2,3,4))
    lu.assertAlmostEquals(z, vm.complex(1,math.sqrt(29)))
    lu.assertAlmostEquals(axis, vm.vec3(2,3,4)/math.sqrt(29))
end

function testAtan()
    lu.assertAlmostEquals(vm.atan(1), math.pi / 4)
    lu.assertAlmostEquals(vm.atan(2,2), math.pi / 4)
    lu.assertEquals(vm.atan(0), 0)
    lu.assertEquals(vm.atan(vm.complex(0)), vm.complex(0))
    lu.assertAlmostEquals(vm.atan(vm.complex(1)), vm.complex(math.pi / 4))
    lu.assertAlmostEquals(vm.atan(vm.complex(0,2)), vm.complex(math.pi / 2, math.log(3) / 2))
end

function testAtanh()
    lu.assertEquals(vm.atanh(0), 0)
    lu.assertAlmostEquals(vm.atanh(0.5), math.log(3) / 2)
    lu.assertAlmostEquals(vm.atanh(vm.complex(0,1)), vm.complex(0, math.pi / 4))
end

function testLog()
    local i = vm.complex(0,1)
    lu.assertEquals(vm.log(2), math.log(2))
    lu.assertEquals(vm.log(2,2), 1)
    lu.assertAlmostEquals(vm.log(i), vm.complex(0,math.pi / 2))
    lu.assertAlmostEquals(vm.log(-1, i), vm.complex(2))
    lu.assertEquals(vm.log2(2), 1)
    lu.assertAlmostEquals(vm.log10(10), 1) -- argh, luajit, stop what you do
end

function testExp()
    lu.assertEquals(vm.exp(2), math.exp(2))
    lu.assertAlmostEquals(vm.exp(vm.complex(0,math.pi)), vm.complex(-1,0))
    lu.assertAlmostEquals(vm.exp(vm.quat(0,0,math.pi/2,0)), vm.quat(0,0,1,0))
    lu.assertAlmostEquals(vm.exp2(3), 8)
end

function testInverseSqrt()
    lu.assertEquals(vm.inversesqrt(4), 0.5)
    lu.assertEquals(vm.inversesqrt(vm.complex(0,2)), vm.complex(0.5,-0.5))
end

function testHypot()
    lu.assertEquals(vm.hypot(3,4), 5)
    lu.assertEquals(vm.hypot(vm.complex(0,3), 4), 5)
end

function testArg()
    lu.assertEquals(vm.arg(1), 0)
    lu.assertEquals(vm.arg(-1), math.pi)
    lu.assertAlmostEquals(vm.arg(vm.complex(0,1)), math.pi / 2)
    lu.assertAlmostEquals(vm.arg(vm.quat(1,0,0,1)), math.pi / 4)
end

function testSign()
    lu.assertEquals(vm.sign(5), 1)
    lu.assertEquals(vm.sign(-3), -1)
    lu.assertEquals(vm.sign(0), 0)
    lu.assertAlmostEquals(vm.sign(vm.complex(1,1)), vm.complex(1/vm.sqrt(2), 1/vm.sqrt(2)))
end

function testAbs()
    local a = vm.vec3(-2,3,-5)
    local b = vm.cvec2(vm.complex(-3,4), vm.complex(-13))
    lu.assertEquals(vm.sqabs(a), vm.vec3(4,9,25))
    lu.assertEquals(vm.abs(a), vm.vec3(2,3,5))
    lu.assertEquals(vm.sqabs(b), vm.vec2(25,169))
    lu.assertEquals(vm.abs(b), vm.vec2(5,13))
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

function testVectorOperators()
    local a = vm.vec3(4,6,8)
    local b = 2
    lu.assertEquals(a / b, vm.vec3(2,3,4))
    lu.assertEquals(b + a, vm.vec3(6,8,10))
    lu.assertEquals(a * a, vm.vec3(16,36,64))
    lu.assertEquals(-a, vm.vec3(-4,-6,-8))
end

function testMatrixOperators()
    local a = vm.mat2x3(1,2,3,4,5,6)
    local b = 10
    lu.assertEquals(a + a, vm.mat2x3(2,4,6,8,10,12))
    lu.assertEquals(b - a, vm.mat2x3(9,8,7,6,5,4))
    lu.assertEquals(a * b, vm.mat2x3(10,20,30,40,50,60))
    lu.assertEquals(-a, vm.mat2x3(-1,-2,-3,-4,-5,-6))
end

function testMatrixMultiplication()
    local a = vm.mat2x3(1,2,3,4,5,6)
    local b = vm.mat3x2(1,2,3,4,5,6)
    local v = vm.vec3(1,2,3)
    lu.assertEquals(a * b, vm.mat3(9,12,15,19,26,33,29,40,51))
    lu.assertEquals(b * a, vm.mat2(22,28,49,64))
    lu.assertEquals(v * a, vm.vec2(14,32))
    lu.assertEquals(b * v, vm.vec2(22,28))
end

function testSwizzleRead()
    local a = vm.vec3(1,2,3)
    local n = 0
    lu.assertEquals(vm.swizzleReadx(a), 1)
    lu.assertEquals(a.x, 1)
    lu.assertEquals(a.b, 3)
    lu.assertEquals(vm.swizzleReady(a), 2)
    lu.assertEquals(vm.swizzleReadz(a), 3)
    lu.assertError(function() return vm.swizzleReadw(a) end)
    lu.assertEquals(vm.swizzleReadxy(a), vm.vec2(1,2))
    lu.assertEquals(vm.swizzleReadyx(a), vm.vec2(2,1))
    lu.assertEquals(a.yx, vm.vec2(2,1))
    lu.assertEquals(a.ps, vm.vec2(3,1))

    lu.assertEquals(vm.swizzleReadyzx(a,a), vm.vec3(2,3,1)) -- targeting itself should be sane
end

function testSwizzleWrite()
    local a = vm.vec3(1,2,3)
    local b = vm.vec2(4,5)
    local c = 6
    vm.swizzleWritex(a, c)
    lu.assertEquals(a, vm.vec3(6,2,3))
    vm.swizzleWritezy(a, b)
    lu.assertEquals(a, vm.vec3(6,5,4))
    a.x = 10
    lu.assertEquals(a, vm.vec3(10,5,4))
    a.gb = vm.vec2(12,15)
    lu.assertEquals(a, vm.vec3(10,12,15))
    a.pts = a
    lu.assertEquals(a, vm.vec3(15,12,10))
end

function testConj()
    lu.assertEquals(vm.conj(3), 3)
    lu.assertEquals(vm.conj(vm.complex(1,2)), vm.complex(1,-2))
    lu.assertEquals(vm.conj(vm.quat(1,2,3,4)), vm.quat(1,-2,-3,-4))
end

function testCopySign()
    lu.assertEquals(vm.copysign(2,-3), -2)
    lu.assertEquals(vm.copysign(-2,-3), -2)
    lu.assertEquals(vm.copysign(-2,3), 2)
    lu.assertEquals(vm.copysign(2,3), 2)
end

function testAcos()
    local i = vm.complex(0,1)
    lu.assertAlmostEquals(vm.acos(0), math.pi/2)
    lu.assertAlmostEquals(vm.acos(1), 0)
    lu.assertAlmostEquals(vm.acos(vm.complex(0)), vm.complex(math.pi/2))
    lu.assertAlmostEquals(vm.acos(vm.complex(1)), vm.complex(0))
    lu.assertAlmostEquals(vm.acos(i), vm.complex(math.pi/2, math.log(math.sqrt(2) - 1)))
end

function testAcosh()
    lu.assertAlmostEquals(vm.acosh(1), 0)
    lu.assertAlmostEquals(vm.acosh(vm.complex(1)), vm.complex(0))
    lu.assertAlmostEquals(vm.acosh(vm.complex(0)), vm.complex(0,math.pi / 2))
    lu.assertAlmostEquals(vm.acosh(vm.complex(0,1)), vm.complex(vm.log(1 + vm.sqrt(2)), math.pi / 2))
end

function testAsinh()
    lu.assertAlmostEquals(vm.asinh(0), 0)
    lu.assertAlmostEquals(vm.asinh(1), math.log(math.sqrt(2)+1))
    lu.assertAlmostEquals(vm.asinh(vm.complex(0)), vm.complex(0))
    lu.assertAlmostEquals(vm.asinh(vm.complex(1)), vm.complex(math.log(math.sqrt(2)+1)))
    lu.assertAlmostEquals(vm.asinh(vm.complex(0,1)), vm.complex(0, math.pi / 2))
end

function testAsin()
    local i = vm.complex(0,1)
    lu.assertAlmostEquals(vm.asin(0), 0)
    lu.assertAlmostEquals(vm.asin(1), math.pi/2)
    lu.assertAlmostEquals(vm.asin(vm.complex(0)), vm.complex(0))
    lu.assertAlmostEquals(vm.asin(vm.complex(1)), vm.complex(math.pi/2))
    lu.assertAlmostEquals(vm.asin(i), vm.complex(0, math.log(math.sqrt(2) + 1)))
end

function testCeil()
    lu.assertEquals(vm.ceil(2.5), 3)
    lu.assertEquals(vm.ceil(vm.vec4(1,1.2,2,4.9)), vm.vec4(1,2,2,5))
end

function testCos()
    local e = math.exp(1)
    lu.assertEquals(vm.cos(0), 1)
    lu.assertAlmostEquals(vm.cos(vm.complex(0,1)), vm.complex((1+e*e)/(2*e)))
end

function testSin()
    local e = math.exp(1)
    lu.assertEquals(vm.sin(0), 0)
    lu.assertAlmostEquals(vm.sin(vm.complex(0,1)), vm.complex(0,(e*e-1)/(2*e)))
end

function testCosh()
    local e = math.exp(1)
    lu.assertEquals(vm.cosh(0), 1)
    lu.assertAlmostEquals(vm.cosh(1), (1+e*e)/(2*e))
    lu.assertAlmostEquals(vm.cosh(vm.complex(0,1)), vm.complex(math.cos(1)))
end

function testSinh()
    local e = math.exp(1)
    lu.assertEquals(vm.sinh(0), 0)
    lu.assertEquals(vm.sinh(1), (e*e-1)/(2*e))
    lu.assertEquals(vm.sinh(vm.complex(0,math.pi/2)), vm.complex(0,1))
end

function testDeg()
    lu.assertAlmostEquals(vm.deg(vm.vec3(0,1,math.pi)), vm.vec3(0,180 / math.pi, 180))
end

function testFloor()
    lu.assertEquals(vm.floor(2.5), 2)
    lu.assertEquals(vm.floor(vm.vec4(1,1.2,-2.5,4.9)), vm.vec4(1,1,-3,4))
end

function testFract()
    lu.assertAlmostEquals(vm.fract(2.6), 0.6)
    lu.assertAlmostEquals(vm.fract(-5.2), -0.2)
end

function testFmod()
    lu.assertEquals(vm.fmod(5,3), 2)
    lu.assertEquals(vm.fmod(-5,3), -2)
end

function testIsinf()
    lu.assertTrue(vm.isinf(math.huge))
    lu.assertTrue(vm.isinf(vm.complex(0, math.huge)))
    lu.assertFalse(vm.isinf(4))
    lu.assertFalse(vm.isinf(vm.complex()))
end
function testIsnan()
    lu.assertTrue(vm.isnan(0/0))
    lu.assertFalse(vm.isnan(1/0))
end

function testFma()
    lu.assertEquals(vm.fma(2,3,5), 11)
end

function testFrexp()
    local mantissa, exponent = vm.frexp(vm.vec3(1.5, math.pi, 0.001))
    lu.assertAlmostEquals(mantissa, vm.vec3(0.75, math.pi / 4, 0.512))
    lu.assertEquals(exponent, vm.vec3(1, 2, -9))
end

function testLdexp()
    local mantissa = vm.vec3(0.75, math.pi / 4, 0.512)
    local exponent = vm.vec3(1, 2, -9)
    lu.assertAlmostEquals(vm.ldexp(mantissa, exponent), vm.vec3(1.5, math.pi, 0.001))
end

function testDotProduct()
    local i = vm.complex(0,1)
    local a = vm.vec2(2,3)
    local b = vm.vec2(3,-2)
    local c = vm.cvec2(1,i)
    lu.assertEquals(vm.dot(a,b), 0)
    lu.assertEquals(vm.dot(a,c), vm.complex(2,-3))
    lu.assertEquals(vm.dot(c,a), vm.complex(2,3))
end

function testCrossProduct()
    local a = vm.vec3(1,2,3)
    local b = vm.vec3(2,3,1)
    lu.assertEquals(vm.cross(a,b), vm.vec3(-7,5,-1))
    lu.assertEquals(vm.cross(b,a), vm.vec3(7,-5,1))
end

function testNormalize()
    local a = vm.vec3(3,4,12)
    local b = vm.cvec2(3, vm.complex(0,4))
    lu.assertAlmostEquals(vm.normalize(a), a / 13)
    lu.assertAlmostEquals(vm.normalize(b), b / 5)
end

function testFaceForward()
    local i = vm.vec2(1,0)
    local n = vm.vec2(0,1)
    local frontish = vm.vec2(-1,1)
    local backish = vm.vec2(1,1)
    lu.assertEquals(vm.faceForward(n,i,frontish), n)
    lu.assertEquals(vm.faceForward(n,i,backish), -n)
end

function testDeterminant()
    local a = vm.mat2(1,2,3,4)
    lu.assertEquals(vm.determinant(a), -2)
    local b = vm.mat3(1,0,1,-1,0,1,1,1,1)
    lu.assertEquals(vm.determinant(b), -2)
    local c = vm.mat4(0,1,8,27,0,1,4,9,0,1,2,3,1,1,1,1)
    vm.utils.bake('determinant', {'mat4x4'})
    lu.assertEquals(vm.determinant(c), 12)
    local d = vm.mat4(1,8,27,64,1,4,9,16,1,2,3,4,1,1,1,1)
    lu.assertEquals(vm.determinant(d), 12)
end

function testTranspose()
    local a = vm.mat2(1,2,3,4)
    a = vm.transpose(a, a)
    lu.assertEquals(a, vm.mat2(1,3,2,4))
    local b = vm.mat3x2(1,2,3,4,5,6)
    lu.assertEquals(vm.transpose(b), vm.mat2x3(1,3,5,2,4,6))
end

function testInverse()
    local a = vm.mat2(1,2,3,4)
    a = vm.inverse(a, a)
    lu.assertEquals(a, vm.mat2(-2,1, 1.5, -0.5))
    local b = vm.mat3(1,4,9,1,2,3,1,1,1)
    lu.assertEquals(vm.inverse(b), vm.mat3(0.5, -2.5, 3, -1, 4, -3, 0.5, -1.5, 1))
    local c = vm.mat4(1,8,27,64,1,4,9,16,1,2,3,4,1,1,1,1)
    local d = vm.mat4(-1, 9, -26, 24, 3, -24, 57, -36, -3, 21, -42, 24, 1, -6, 11, -6) / 6
    lu.assertAlmostEquals(vm.inverse(c), d)
end

function testLength()
    lu.assertEquals(vm.length(vm.vec2(3,4)), 5)
end

function testDistance()
    lu.assertEquals(vm.distance(vm.vec2(3,0), vm.vec2(0,4)), 5)
end

function testComponentCompare()
    local a = vm.vec3(1,2,3)
    local b = vm.vec3(1,3,2)
    lu.assertEquals(vm.equal(a, b), vm.bvec3(true, false, false))
    lu.assertEquals(vm.greaterThan(a, b), vm.bvec3(false, false, true))
    lu.assertEquals(vm.greaterThanEqual(a, b), vm.bvec3(true, false, true))
    lu.assertEquals(vm.lessThan(a, b), vm.bvec3(false, true, false))
    lu.assertEquals(vm.lessThanEqual(a, b), vm.bvec3(true, true, false))
    lu.assertEquals(vm.notEqual(a, b), vm.bvec3(false, true, true))
end

function testAnyAll()
    local a = vm.bvec2(true, true)
    local b = vm.bvec2(false, true)
    local c = vm.bvec2(false, false)
    lu.assertTrue(vm.any(a))
    lu.assertTrue(vm.any(b))
    lu.assertFalse(vm.any(c))
    lu.assertTrue(vm.all(a))
    lu.assertFalse(vm.all(b))
    lu.assertFalse(vm.all(c))
end

function testLogicalConnectives()
    local a = vm.bvec4(false,false,true,true)
    local b = vm.bvec4(false,true,false,true)
    lu.assertEquals(vm.logicalAnd(a,b), vm.bvec4(false, false, false, true))
    lu.assertEquals(vm.logicalOr(a,b), vm.bvec4(false, true, true, true))
    lu.assertEquals(vm.logicalNot(a), vm.bvec4(true, true, false, false))
end

function testMatrixCompMult()
    local a = vm.mat2(1,1,2,2)
    local b = vm.mat2(1,3,1,3)
    lu.assertEquals(vm.matrixCompMult(a,b), vm.mat2(1,3,2,6))
end

function testMinMax()
    local a = vm.vec3(1,2,3)
    local b = vm.vec3(1,3,2)
    lu.assertEquals(vm.min(a,b), vm.vec3(1,2,2))
    lu.assertEquals(vm.max(a,b), vm.vec3(1,3,3))
end

function testMix()
    local a,b,t = 0,5,0.8
    lu.assertAlmostEquals(vm.mix(a,b,t), 4)
    lu.assertEquals(vm.mix(vm.vec2(1,0), vm.vec2(0,1), 0.75), vm.vec2(0.25,0.75))
    lu.assertEquals(vm.mix(vm.vec3(1,2,3), vm.vec3(4,5,6), vm.bvec3(true, false, true)), vm.vec3(4,2,6))
end

function testMod()
    lu.assertEquals(vm.vec3(7,11,15) % 5, vm.vec3(2,1,0))
end

function testModf()
    local w,f = vm.modf(vm.vec3(1.7,4.6,-3.2))
    lu.assertEquals(w, vm.vec3(1,4,-3))
    lu.assertAlmostEquals(f, vm.vec3(0.7,0.6,-0.2),1e-15) -- apparently the default isn't accurate enough?
end

function testNumber()
    lu.assertEquals(vm.number(), 0)
    lu.assertEquals(vm.number(3), 3)
    lu.assertEquals(vm.number('0x40'), 64)
    lu.assertEquals(vm.number('123',4), 27)
end

function testOuterProduct()
    local a = vm.vec2(1,2)
    local b = vm.vec3(1,2,3)
    lu.assertEquals(vm.outerProduct(a,b), vm.mat3x2(1,2,2,4,3,6))
end

function testRad()
    lu.assertAlmostEquals(vm.rad(vm.vec3(0,60,90)), vm.vec3(0,math.pi/3, math.pi/2))
end

function testReflect()
    local ray = vm.vec2(-0.8,0.6)
    local x_mirror = vm.vec2(1,0)
    local xy_mirror = vm.normalize(vm.vec2(1,1))
    lu.assertAlmostEquals(vm.reflect(ray, x_mirror), vm.vec2(0.8,0.6))
    lu.assertAlmostEquals(vm.reflect(ray, xy_mirror), vm.vec2(-0.6,0.8))
end

function testRefract()
    local index = 1.2
    lu.assertAlmostEquals(vm.refract(vm.vec2(0.5,math.sqrt(3)/2), vm.vec2(0,-1), 1.2), vm.vec2(0.6,0.8))
end

function testRound()
    lu.assertEquals(vm.round(2.5), 3)
    lu.assertEquals(vm.round(vm.vec4(1,1.2,2,4.9)), vm.vec4(1,1,2,5))
end

function testRoundEven()
    lu.assertEquals(vm.roundEven(2.5), 2)
    lu.assertEquals(vm.roundEven(vm.vec4(1,1.2,2,4.9)), vm.vec4(1,1,2,5))
end

function testStep()
    lu.assertEquals(vm.step(5, vm.vec3(2,5,8)), vm.vec3(0,1,1))
end

function testSmoothStep()
    lu.assertEquals(vm.smoothStep(4, 6, vm.vec4(3, 4.5, 5, 7)), vm.vec4(0, 5/32, 1/2, 1))
end

function testClamp()
    lu.assertEquals(vm.clamp(3,4,5), 4)
    lu.assertEquals(vm.clamp(4.5,4,5), 4.5)
    lu.assertEquals(vm.clamp(6,4,5), 5)
end

function testSqrt()
    lu.assertEquals(vm.sqrt(4), 2)
    lu.assertEquals(vm.sqrt(vm.complex(-4)), vm.complex(0,2))
    lu.assertEquals(vm.sqrt(vm.complex(0,2)), vm.complex(1,1))
end

function testTan()
    local e = math.exp(1)
    lu.assertEquals(vm.tan(0), 0)
    lu.assertAlmostEquals(vm.tan(math.pi / 4), 1)
    lu.assertAlmostEquals(vm.tan(vm.complex(0,1)), vm.complex(0, (e - 1/e)/(e + 1/e)))
end

function testTanh()
    local e = math.exp(1)
    lu.assertEquals(vm.tanh(0), 0)
    lu.assertAlmostEquals(vm.tanh(1), (e - 1/e)/(e + 1/e))
    lu.assertAlmostEquals(vm.tanh(vm.complex(0,math.pi/4)), vm.complex(0, math.sqrt(0.5)))
end

function testTrunc()
    lu.assertEquals(vm.trunc(1.2), 1)
    lu.assertEquals(vm.trunc(-1.2), -1)
end

function testVectorTableFill()
    local t = {3, 5, vm.complex()}
    lu.assertEquals(vm.vec2(t), vm.vec2(3, 5))
    lu.assertEquals(vm.cvec3(t), vm.cvec3(3, 5, vm.complex()))
    lu.assertError(vm.vec3, t)
    lu.assertError(vm.cvec4, t)
end

function testMatrixTableFill()
    local t = {1, 2, 3, 4, vm.complex(5), 6}
    lu.assertEquals(vm.mat2(t), vm.mat2(1,2,3,4))
    lu.assertEquals(vm.cmat3x2(t), vm.cmat3x2(1, 2, 3, 4, vm.complex(5), 6))
    lu.assertError(vm.mat3x2, t)
    lu.assertError(vm.cmat3, t)
end

function testCis()
    lu.assertAlmostEquals(vm.cis(math.pi / 3), vm.complex(0.5, math.sqrt(3)/2))
end

function testPolarComplex()
    lu.assertAlmostEquals(vm.polarComplex(math.sqrt(8), math.pi/4), vm.complex(2,2), 1e-15)
end

function testPolarVectors()
    lu.assertAlmostEquals(vm.polarVec2(5, math.atan(0.75)), vm.vec2(4,3))
    lu.assertAlmostEquals(vm.cylindricalVec3(13, math.atan(2.4), -10), vm.vec3(5,12,-10), 1e-14) -- this one's even more floppy
    lu.assertAlmostEquals(vm.sphericalVec3(math.sqrt(3), math.pi/4, math.atan(math.sqrt(0.5))), vm.vec3(1,1,1))
end

function testMinMaxComponent()
    local v = vm.vec4(2,1,4,3)
    lu.assertEquals(vm.minComponent(v), 1)
    lu.assertEquals(vm.maxComponent(v), 4)
end

function testFunkyNormalizes()
    lu.assertEquals(vm.cubeNormalize(vm.vec3(1,-4,2)), vm.vec3(0.25,-1,0.5))
    lu.assertEquals(vm.homogeneousNormalize(vm.vec3(5,10,2.5)), vm.vec3(2,4,1))
    lu.assertAlmostEquals(vm.homogeneousNormalize(vm.vec3(3,4,0)), vm.vec3(0.6,0.8,0))
    lu.assertAlmostEquals(vm.hesseNormalize(vm.vec3(3,-4,10)), vm.vec3(0.6,-0.8,2))
end

os.exit(lu.LuaUnit.run())