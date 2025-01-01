# vornmath

Vorn's Lua Math Library

Vornmath is (will be) a comprehensive vector and complex math library for lua.
It works on lua versions 5.1 through 5.4 as well as luajit.

## Installing and Using

Vornmath is a single file, pure Lua library; it does not add any symbols to
global.  Just put `vornmath.lua` somewhere convenient in your source tree and do

```lua
local vm = require('vornmath')
```

You don't even need to bring a license file alongside, there's one onboard!

## Basic concepts

### Returns and outvars

All Vornmath functions that return objects of types that are made of tables -
so anything that would return a vector, matrix, complex, or quaternion - accept
out variables.  The out variable has to be the same type; the object merely
gets its fields filled in.  The object is *also* returned when an outvar is
provided; because there are some cases where giving varying types to a function
may only sometimes result in a type where an out variable actually successfully
changes its target, it is a good idea to not only pass the out variable but
also assign the result to the same place:

```lua
result_vec = vm.add(left_vec, right_vec, result_vec)
```

For functions like `atan` where some parameters are optional, the outvar is
still in the same position, with nil taking the place of those optional things.

```lua
result = vm.atan(angle, nil, result)
```

### Generic and specific forms

All functions in vornmath come in two forms: one in which it is generic and
accepts arguments of any types that are valid for the function, and one in
which the types being passed in are already specified as part of the name.  For
instance, the multiplication function `mul` can accept a great variety of
types for its inputs, so it has many signatures, some of which are:

```lua
mul
mul_number_number_nil
mul_vec3_cvec3_nil
mul_mat4_number_mat4
```

When passing an outvar to a specific-form function, the out variable's type is
part of the signature, and so is included in the name.

The specified ones have one particular advantage: they are a little faster
because they don't do additional function calls to perform dispatch into the
correct function. On the other hand they do have long annoying names and cannot
accept varying types.

In situations where a function has one signature that is a *prefix* of another,
the shorter signature will include a `nil`:

* `atan_number_nil` accepts a single number, and
* `atan_number_number` accepts two.

The presence or absence of `nil` in the signature can be annoying to remember;
it is generally a better idea to use `vm.utils.bake` to find the correct
function.

All of these are in the `vornmath` object.  Or would be, except...

### Laziness

Functions in Vornmath do not exist prior to being named.  This is mostly because
there are a *lot* of functions, and building every single one would make the
code huge: `fill` has over *ten million* signatures!

So instead, we use some objects called *bakeries* to describe the patterns that
functions fall into and construct these functions the first time they are used.
Because of this, examining the `vornmath` table will not actually name every
function available. You will have to rely on this documentation, or examine the
bakeries.  Technical info about bakeries is down below.

### Creating objects

to create an object, call its constructor.

```lua
local a = vm.complex() -- creates a complex number, initialized to 0+0i.
local b = vm.complex(3) -- creates a complex number, initialized to 3+0i.
local c = vm.complex(2,-5) -- creates a complex number, initialized to 2-5i.
local d = vm.complex(c) -- creates a duplicate of c.
```

### `fill`

If you already have an object and wish to replace its contents completely, use
`fill`. Usually, this edits the underlying object, but if the object in
question is a `number` or otherwise immutable, it won't be able to change
it and you'll instead get a fresh object anyway.  **to ward off bad
consequences of this, only use fill on things not used elsewhere, and when you
use fill, assign the result of fill to a value!**

`fill` can be used in any way that a constructor can be used: if you have a
constructor for an object, you can replace that constructor with `fill` and just
put the object you want to fill in as the first argument.

```lua
local a = vm.complex(1,2) -- a is 1+2i
local b = vm.fill(a,3,4) -- a is now 3+4i, and b is the same object as a. 
```

### Operators

Operators exist!  They use the most generic form of the function because they
can't be relied upon to be called on a particular object in the chain.

Most importantly, however, **due to limitations in the way lua implements `==`,
it is not possible to make a thing that compares non-`number` objects to
`number`s!**  if you expect to be comparing a `number` and some other type
(say, because you want to see if it's 0), you will have to use `vm.eq`
instead.

## Types

### `number`

```lua
vm.number() --> 0
vm.number(n) --> n
vm.number(str, [base]) --> string as number in given base (default 10)
```

this is Lua's built-in `number` type.  There's not much to say about it!

The interpretation of strings as numbers comes directly from Lua.

### `complex`

```lua
vm.complex() --> 0 + 0i
vm.complex(a) --> a + 0i
vm.complex(a, b) --> a + bi
vm.complex(a + bi) --> a + bi
```

Complex numbers, of the form `a + bi`.  They have fields `a`, the real part, and
`b`, the imaginary part.  Some functions (in particular `log`arithms and
`sqrt`) will behave slightly differently for complex numbers than regular
numbers: these functions have some values in which no real answer is possible,
and so will not work when given a `number`, but will when given a `complex` of
equivalent value.  In addition, complex numbers do not have a natural ordering,
so `<` and its friends will not work even on real-valued complexes.

### `quat`ernion

```lua
vm.quat() --> 0 + 0i + 0j + 0k
vm.quat(a) --> a + 0i + 0j + 0k
vm.quat(a,b,c,d) --> a + bi + cj + dk
vm.quat(a+bi) --> a + bi + 0j + 0k
vm.quat(a+bi, c+di) --> a + bi + cj + dk
vm.quat(a+bi+cj+dk) --> a + bi + cj + dk
vm.quat(vm.vec3(b, c, d), angle) --> cos(angle/2) + sin(angle/2)*(bi + cj + dk) 
vm.quat(a+bi, vm.vec3(c, d, e)) --> a + b * (ci + dj + ek)
vm.quat(vm.vec3(...), vm.vec3(...))
```

Higher dimensional complex numbers, of the form `a + bi + cj + dk`.  Fields `a`,
`b`, `c`, and `d` access the various components.  Somehow, many things that
work with complex numbers also work with quaternions! (I know, I was surprised
too)  However, quaternion multiplication is *non-commutative*: if `x` and `y`
are quaternions, then `x * y` and `y * x` usually give different results.

The two vector constructor produces the shortest rotation that takes the first
vector to the second.

The axis-angle, complex-axis, and two-vector constructors all expect (but
neither enforce nor convert to) a unit vector; you might get unexpected results
if you pass something else.


### `boolean`

```lua
vm.boolean() --> false
vm.boolean(x) --> x
```

This is Lua's built-in `boolean` type.  Not much to say about it either!

### `vec`tors

```lua
vm.vec2() --> <0, 0>
vm.vec3(a) --> <a, a, a>
vm.cvec4(vm.vec2(a,b), vm.cvec3(c,d,e)) --> <complex(a), complex(b), c, d>
vm.bvec2() --> <false, false>
```

Vectors.  There are actually 9 vector types: `vec2`, `vec3`, and `vec4` are 2-,
3-, and 4-dimensional vectors with `number`s as components; `cvec2`, `cvec3`,
and `cvec4` use `complex` numbers, and `bvec2`, `bvec3`, and `bvec4` use
`boolean`s.

Vectors are indexed numerically, starting at 1.

The general constructor for a vector can take any number of scalar, vector, or
matrix arguments for which the numeric type is convertible to the vector's type
and which together provide enough components to completely fill the vector so
long as the last component of the vector lands in the last argument.

#### Swizzling

In addition to numeric indices, vectors can be indexed via *swizzles*, strings
of letters that describe a list of indices.

There are three alphabets for swizzling: `xyzw` (best for position),
`rgba` (best for color), and `stpq` (best for parametric coordinates).  They
cannot be mixed.

Swizzles can be used for both reading and writing.

```lua
local v = vm.vec3(1,2,3)
v.x --> 1
v.bg --> <3,2>
v.sp = vm.vec2(4,5) --> v = <4,2,5>
```

This functionality can also be accessed as a function, which allows outvars.
For this, the swizzle string is included as part of the name of the function.

These functions always use the `xyzw` alphabet.

```lua
local out = vm.vec2()
swizzleReadx(v) --> 1
out = swizzleReadyx(v, out) --> out = <2,1>
swizzleWritezy(v, vm.vec2(6,7)) --> v = <4,7,6>
```

### `mat`rices

```lua
vm.cmat2() --> [[1+0i,0+0i], [0+0i,1+0i]]
vm.mat3(a) --> [[a,0,0], [0,a,0], [0,0,a]]
vm.mat2x3(a,b,c,d,e,f) --> [[a,b,c], [d,e,f]]
vm.mat3(vm.mat2x3(a,b,c,d,e,f)) --> [[a,b,c], [d,e,f], [0,0,1]]
vm.mat3(vm.quat(...)) --> rotation matrix
vm.mat4(vm.quat(...)) --> rotation matrix
```

Matrices.  There's 18 of these!  They can use numbers or complexes, can be 2 to
4 columns, and can be 2 to 4 rows.  Like vectors, a letter before `mat`
describes the type of number it stores (nothing for numbers, `c` for complex),
and the number(s) after it describe its size: columns first, then `x`, then
rows.  `mat2x4` is a matrix with two columns and four rows, filled with numbers;
`cmat3x2` is a matrix with three columns and two rows, filled with complex
numbers.  Square matrices, with the same number of rows as columns, have shorter
aliases: `mat4` is equivalent to `mat4x4`, `cmat3` is equivalent to `cmat3x3`.
When used in function signatures, always use the longer name, not the alias.

Matrices are indexed numerically by column, starting at `1`; each column is a
`vec`tor in its own right.

The matrix constructor will fill any blank spaces in the result with `0`
except for entries on the diagonal which will receive `1`.

The general constructor can take any number of scalar or vector (not matrix!)
arguments which together provide enough components to completely fill the
matrix so long as the last component of the matrix lands in the last argument.

The quaternion constructors produce a 3d rotation matrix; the `mat4` version
simply augments it with the identity so it works with the larger matrix.

## Functions

### Operators

The various operators can be accessed through their function names, and have
their signatures included to skip dispatch, or can be used directly as
operators.

#### `add` (`a + b`)

```lua
a + b --> a + b
vm.add(a, b[, c]) --> c = a + b
```

Addition!  If applied to a vector and a scalar, or a matrix and a scalar, or two
vectors of the same size, or two matrices of the same size, it operates
*componentwise*: `3 + vec3(5, 6, 7) => vec3(8, 9, 10)`, for instance.

#### `sub` (`a - b`)

```lua
a - b --> a - b
vm.sub(a, b[, c]) --> c = a - b
```

Subtraction!  Just like addition, but using the negation of the second argument.

#### `unm` (`-a`)

```lua
-a --> -a
vm.unm(a[, b]) --> b = -a
```

Unary negation!  Works on everything.

#### `mul` (`a * b`)

```lua
a * b --> a * b
vm.mul(a, b[, c]) --> c = a * b 
```

Multiplication!  If applied to a vector and a scalar, or a matrix and a scalar,
or two vectors of the same size, it operates componentwise, just like addition.

If applied to a matrix and a vector or two matrices, it performs linear
algebraic multiplication: each entry of the result takes the matching row of
the left operand and the matching column of the right operand, multiplies them
together component wise, and takes the sum.  A vector on the left
side acts as a row vector; a vector on the right side acts as a column vector.
The result is a vector or matrix with the same number of rows as the left
operand and the same number of columns as the right operand.  The left
operand's number of columns, and the right operand's number of rows, must be
the same for this to work.

Multiplying a `quat` by a `vec3` results in the vector rotated by the quat.

#### `div` (`a / b`)

```lua
a / b --> a / b
vm.div(a, b[, c]) --> c = a / b
```

Division!  Uses the same rules as addition.  For quaternions, non-commutative
multiplication technically means there are two different forms of division:
Vornmath uses `p * (1/q)`, sometimes called right division.

#### `mod` (`a % b`)

```lua
a % b --> a % b
vm.div(a, b[, c]) --> c = a % b
```

Modulus!  Only works on `number`s and vectors and matrices storing `number`s.
Gives the remainder of division, `p/q - floor(p/q)`.  Works componentwise.

#### `pow` (`a ^ b`)

```lua
a ^ b --> a ^ b
vm.pow(a, b[, c]) --> c = a ^ b
```

Exponentiation!  Some things that are illegal in real numbers will work
when done in complex numbers: `-1 ^ 0.5` is undefined in real numbers but
`complex(-1) ^ 0.5` works and gives `i`.  `pow` does not work on matrices at
all.

#### `eq` (`a == b` and `a ~= b`)

```lua
a == b --> a == b
vm.eq(a, b) --> a == b
```

Equality!  Works on anything; will return `true` if all elements are equal. For
differing number types, will implicitly convert to the necessary type, so
`vm.eq(5, complex(5,0))` is `true`.

**warning**: using the symbolic equals `==` on `number` and a type other than
`number` doesn't work correctly and will always return `false`, due to
limitations in Lua's metatable system.  Instead, use `eq` if you really need to
do that.

#### `tostring`

```lua
vm.tostring(a) --> a string representation of a
```

Technically this isn't an operator, but it is a thing that gets a metamethod.
Turns a thing into a string!  The representations provided by this are not
valid Lua code: they're designed to be reasonable to look at.

### Trigonometric functions

All trigonometric functions act componentwise on vectors.  Angles are always
assumed to be in radians unless otherwise specified.

#### `rad`

```lua
vm.rad(angle_in_degrees[, x]) --> x = angle in radians
```

Converts angle values from degrees to radians.

#### `deg`

```lua
vm.deg(angle_in_radians[, x]) --> x = angle in degrees
```

Converts angle values from radians to degrees.

#### `sin`

```lua
vm.sin(phi[, x]) --> x = sin(phi)
```

Computes the sine of the given angle.

#### `cos`

```lua
vm.cos(phi[, x]) --> x = cos(phi)
```

Computes the cosine of the given angle.

#### `tan`

```lua
vm.tan(phi[, x]) --> x = tan(phi)
```

Computes the tangent of the given angle.

#### `asin`

```lua
vm.asin(phi[, x]) --> x = asin(phi)
```

Computes the inverse sine or arcsine of the given value.  For real inputs, will
return an angle between 0 and π.

#### `acos`

```lua
vm.acos(phi[, x]) --> x = acos(phi)
```

Computes the inverse cosine or arccosine of the given angle.  For real inputs,
will return an angle between -π/2 and π/2.


#### `atan`

```lua
vm.atan(y[, nil, phi]) --> phi = angle
vm.atan(y, x[, phi]) --> phi = angle
```

Computes the inverse tangent or arctangent of the given value.  For `numbers`,
optionally accepts two parameters such that `vm.atan(y, x)` will give the
correct angle across the whole circle, equivalent to `atan2`.  **the out
variable is the *third* parameter** for this function because of this.  For real
inputs, will return an angle between -π/2 and π/2 for the single-input version,
or an angle between -π and π for the two-input version.

#### `sinh`

```lua
vm.sinh(x[, y]) --> y = sinh(x)
```

Computes the hyperbolic sine of the given value.

#### `cosh`

```lua
vm.cosh(x[, y]) --> y = cosh(x)
```

Computes the hyperbolic cosine of the given value.

#### `tanh`

```lua
vm.tanh(x[, y]) --> y = tanh(x)
```

Computes the hyperbolic tangent of the given value.

#### `asinh`

```lua
vm.asinh(x[, y]) --> y = asinh(x)
```

Computes the invers hyperbolic sine of the given value.

#### `acosh`

```lua
vm.acosh(x[, y]) --> y = acosh(x)
```

Computes the inverse hyperbolic cosine of the given value.

#### `atanh`

```lua
vm.atanh(x[, y]) --> y = atanh(x)
```

Computes the inverse hyperbolic tangent of the given value.

### Exponential functions

All these functions act componentwise on vectors.

#### `exp`

```lua
vm.exp(x[, y]) --> y = e^x
```

Computes the exponential function `e^z`.

#### `exp2`

```lua
vm.exp2(x[, y]) --> y = 2^x
```

Computes the base-2 exponential function `2^z`.

#### `log`

```lua
vm.log(x[, nil, y]) --> y = ln x
vm.log(x, b[, y]) --> y = log_b x
```

Computes the logarithm.  For single-argument calls, this is the natural log.
The second argument changes the base: `vm.log(8,2) = 3` because `2^3 = 8`.

#### `log2`

```lua
vm.log2(x[, y]) --> y = log_2 x
```

Computes the base-2 logarithm.


#### `log10`

```lua
vm.log10(x[, y]) --> y = log_10 x
```

Computes the base-10 logarithm.

#### `sqrt`

```lua
vm.sqrt(x[, y]) --> y = sqrt(x)
```

Computes the square root.  Fails if given a negative `number`; given a negative
real `complex` or `quat` it will produce some positive multiple of *i*.  All
numbers (other than zero) have two distinct candidates for their square root;
this function produces the one with a positive real part.

#### `inversesqrt`

```lua
vm.inversesqrt(x[, y]) --> y = 1 / sqrt(x)
```

Computes the inverse square root, the reciprocal of the square root.

#### `hypot`

```lua
vm.hypot(x, y[, z]) --> z = sqrt(|x^2| + |y^2|)
```

Gives the length of the hypotenuse of a right triangle with legs length x and y.
Uses the absolute value to prevent silly results in complexes and quaternions.

### Complex and Quaternion functions

All these act componentwise on vectors.

#### `arg`

```lua
vm.arg(a+bi[, x]) --> x = atan(b, a)
```

Computes the argument or phase of a complex number, the angle the complex
number makes with the positive real line.  Also works on regular numbers and
quaternions.

#### `conj`

```lua
vm.arg(a+bi[, z]) --> z = a-bi
vm.arg(a+bi+cj+dk[, z]) --> z = a-bi-cj-dk
```

Computes the conjugate of a complex number or quaternion, which is the same
number except with all the signs on the complex parts switched.

This works on matrices as well as vectors.

#### `axisDecompose`

```lua
vm.axisDecompose(a+bi+cj+dk[, cpx, axis]) --> ...
-- local l = sqrt(b^2 + c^2 + d^2)
-- cpx = a + li
-- axis = <b, c, d> / l
```

decomposes a quaternion into a complex number and a unit axis.  These can in
turn be fed back into `vm.quat` to reconstruct the original quaternion.

### Common functions

All these act componentwise on vectors.

#### `abs`

```lua
vm.abs(x[, y]) --> y = |x|
```

Returns the absolute value, the positive real number with the same magnitude as
the number given.

#### `sqabs`

```lua
vm.sqabs(x[, y]) --> y = |x|^2
```

Returns the square of the absolute value.

#### `copysign`

```lua
vm.copysign(sign, mag[, result]) --> |result| = |mag|, has same sign as sign
```

Copys the sign of `sign` onto `mag`.

#### `sign`

```lua
vm.sign(x, result) --> result = x/abs(x)
```

Returns a value with magnitude 1 that has the same sign as x, unless x is 0,
in which case returns 0.  Also works on complexes and quaternions, giving values
with the same argument and vector as x.  Notably this means that all results of
`sign` are *unit* except for when the input is 0.

#### `floor`

```lua
vm.floor(x[, y]) --> y <= x < y + 1; y is integer
```

Computes the floor, the highest integer that is at most x.

#### `ceil`

```lua
vm.ceil(x[, y]) --> y - 1 < x <= y; y is integer
```

Computes the ceiling, the lowest integer that is at least x.

#### `trunc`

```lua
vm.trunc(x[, y]) -- 0 <= y <= x < y + 1 or y - 1 < x <= y <= 0; y is integer
```

Truncates a number, removing any fractional part; selects the nearest integer towards 0.

#### `round`

```lua
vm.round(x[, y]) -- |x - y| <= 0.5; y is integer
```

Rounds a number to the nearest integer.  If the fractional part of x is exactly
0.5, rounds up.  This is somewhat faster than `roundEven`.

#### `roundEven`

```lua
vm.roundEven(x[, y]) -- |x - y| <= 0.5; y is integer
```

Rounds a number to the nearest integer.  If the fractional part of x is exactly
0.5, rounds to the nearest even number.  This is somewhat slower than `round`.

#### `fract`

```lua
vm.fract(x[, y]) --> y = x - trunc(x)
```

Gives the fractional part of x, with the same sign as x.  Equivalent to the
second return value of `modf`.

#### `modf`

```lua
vm.modf(x[, whole, fractional]) --> whole + fractional = x
```

Separates a number into whole and fractional parts.  Both parts have the *same
sign* as the original number, so this works as truncating division instead of
the usual flooring division.

#### `fmod`

```lua
vm.fmod(x, y[, remainder]) --> remainder of division
```

Gets the remainder of division such that the quotient takes the sign of the
numerator; this is different from % where it takes the sign of the 
denominator.

#### `min`

```lua
vm.min(x, y[, result]) --> smaller of x and y
```

Finds the minimum of the two inputs. **Unlike `math.min`, this only accepts two
inputs!**

#### `max`

```lua
vm.max(x, y[, result]) --> larger of x and y
```

Finds the maximum of the two inputs. **Unlike `math.max`, this only accepts two
inputs!**

#### `clamp`

```lua
vm.clamp(x, lo, hi) --> min(max(x, lo), hi)
```

Finds the closest value to x that's also between lo and hi inclusive.

#### `mix`

```lua
vm.mix(a, b, t[, r]) --> r = (1-t)*a + t*b
vm.mix(a, b, flags[, r]) --> r[i] = b[i] if flags[i] is true, a[i] otherwise
```

Linear or boolean interpolation: if `t` is a scalar or non-boolean vector, it
will do `(1-t)*a + t*b` componentwise.  If instead it's a boolean vector, it
will select between `a` and `b` based on truth value; this helps to avoid
problems with NaNs and infinities messing with results in cases where that is
possible.

#### `step`

```lua
vm.step(edge, x[, r]) --> r = 0 if x < edge, 1 otherwise
```

#### `smoothStep`

```lua
vm.smoothStep(lo, hi, x) --> 

#### `isnan`

```lua
vm.isnan(x) --> true if x is NaN.
```

check for NaN values; if applied to a complex or quat will be true if any
component is NaN.

#### `isinf`

```lua
vm.isinf(x) --> true if x is infinite.
```

check for infinite values; if applied to a complex or quat will be true if any
component is infinite.

#### `fma`

```lua
vm.fma(a, b, c[, r]) --> r = a * b + c
```

Fused multiply-add.  This exists for compatibility: it doesn't do 
anything special as far as precision or operation count goes.

#### `frexp`

```lua
vm.frexp(x[, mantissa, exponent]) --> mantissa * 2 ^ exponent = x
```

Separates a number into a mantissa with absolute value in 0.5 <= x < 1 and
an exponent such that mantissa * 2 ^ exponent = x.

#### `ldexp`

```lua
vm.ldexp(mantissa, exponent[, x]) --> x = mantissa * 2 ^ exponent
```

puts a number separated via frexp back together.

### Vector functions

#### `length`

```lua
vm.length(v) --> ||v||
```

Returns the length of a vector.  For complex vectors, this uses the absolute
value, because using straight squaring will cause lengths of some non-zero
vectors to be 0, which is not desirable.

#### `distance`

```lua
vm.distance(a,b) --> ||b - a||
```

Finds the distance between two points.  Equivalent to `vm.length(b-a)`.

#### `dot`

```lua
vm.dot(a, b[, r]) --> r = a · b
```

Finds the dot product of the two vectors.  For complex numbers, this takes the
conjugate of b: without this, a · a could be zero and that's not great.

#### `cross`

```lua
vm.cross(a, b[, r]) --> r = a × b
```

Finds the cross product of the two vectors.  Unlike `dot` this doesn't take the
conjugate because it turns out fine.

#### `normalize`

```lua
vm.normalize(a[, r]) --> r = a / ||a||
```

Computes a vector in the same direction as the input, but with length 1.

#### `faceForward`

```lua
vm.faceForward(n, i, nref[, r]) --> r = -n * sign(dot(i, nref))
```

Gives -n or n depending on whether nref is in the same or opposite direction as
i.

#### `reflect`

```lua
vm.reflect(i, n[, r]) --> r = i - 2 * dot(n, i) * n
```

gives the direction of the resultant ray after reflecting an incident ray with
direction `i` off a surface with normal `n`.  `i` and `n` must both be unit
vectors for this to work correctly.

#### `refract`

```lua
vm.refract(i, n, eta[, r]) --> r = ...complicated
```

gives the direction of the resultant ray after refracting an incident ray with
direction `i` through a surface with normal `n` and ratio (after / before) of
indices of refraction `eta`.  if `eta > 1` and the angle of incidence is high
enough, it is possible for the result to be total internal reflection: in this
case, the function returns a zero vector.

Both `n` and `i` must be unit vectors for this to work correctly.

The actual formula for refraction is

$$\begin{aligned}
k &= 1 - \eta^2\left(1-\left(n\cdot i\right)^2\right)\\
r &= \begin{cases}
0 &k < 0\\
\eta i - \left(\eta n\cdot i + \sqrt k\right)n&\text{otherwise}
\end{cases}
\end{aligned}$$

### Matrix functions

#### `matrixCompMult`

```lua
vm.matrixCompMult(a, b[, r]) --> r[i][j] = a[i][j] * b[i][j]
```

Componentwise multiplication of two matrices.  If you want linear algebraic
multiplication, use `mul` or the `*` operator.

#### `outerProduct`

```lua
vm.outerProduct(col, row[, r]) --> r[i][j] = col[i] * row[j]
```

Linear algebraic product of a column vector `col` and a row vector `row`,
producing a matrix.

#### `transpose`

```lua
vm.transpose(m[, r]) --> r = mᵀ
```

Transposes the matrix: swaps the meaning of rows and columns.

#### `determinant`

```lua
vm.determinant(m[, r]) --> r = |m|
```

Calculates the determinant of the matrix.

#### `inverse`

```lua
vm.inverse(m[, r]) --> r = m⁻¹
```

Calculates the inverse of the matrix.

### Vector relational functions

The ones named for various comparison relations are componentwise for vectors:
instead of returning a single boolean, they return a bvec where each component
is the result of applying that relation to 

#### `equal`

```lua
vm.equal(a,b) --> a bvec with true for equal components and false for unequal
```

Componentwise vector equality comparison.  If you want a single boolean, check
[eq](#eq) instead.

#### `notEqual`

```lua
vm.notEqual(a,b) --> a bvec with true for unequal components and false for equal
```

Componentwise vector inequality comparison.  If you want a single boolean, use
`not eq(a,b)` instead.

#### `greaterThan`

```lua
vm.greaterThan(a,b) --> a bvec with true for components where a[i] > b[i]
```

Componentwise vector comparison using >.

#### `greaterThanEqual`

```lua
vm.greaterThanEqual(a,b) --> a bvec with true for components where a[i] >= b[i]
```

Componentwise vector comparison using >=.

#### `lessThan`

```lua
vm.lessThan(a,b) --> a bvec with true for components where a[i] < b[i]
```

Componentwise vector comparison using <.

#### `lessThanEqual`

```lua
vm.lessThanEqual(a,b) --> a bvec with true for components where a[i] <= b[i]
```

Componentwise vector comparison using <=.

#### `any`

```lua
vm.any(v) --> logical OR of all components
```

Returns `true` if any of the components of `v` are `true`; otherwise, `false`.

#### `all`

```lua
vm.all(v) --> logical AND of all components
```

Returns `true` if all of the components of `v` are `true`; otherwise, `false`.

#### `logicalAnd`

```lua
vm.logicalAnd(a,b) --> componentwise logical AND
```

Returns `true` for each component that is `true` in *both* a and b.  This does
not short-circuit: both inputs are evaluated regardless of result.

#### `logicalOr`

```lua
vm.logicalOr(a,b) --> componentwise logical OR
```

Returns `true` for each component that is `true` in *either* a and b.  This does
not short-circuit: both inputs are evaluated regardless of result.

#### `logicalNot`

```lua
vm.logicalNot(a) --> componentwise logical NOT
```

Returns `true` for each component that is `false`.

## Technical Details

### The Bakery

The heart of Vornmath's architecture is the bakery: a system that will generate
any requested function the first time it is asked for and store it permanently
for later use, and prepare simple dispatch functions to enable its use from the
generic function name.

#### Structure of a bakery

A bakery for a function is a simple table placed in
`vm.bakeries[function_name]` and is composed of three functions, each of
which accepts a table of type names:

* `signature_check` returns `true` if this particular bakery handles functions 
  with this signature; if it does return `true`, it may edit the types table to
  trim it or add `'nil'` to help distinguish it from other signatures.
* `create` returns a function that actually performs the requested operation.
  Since it is exclusively called after `signature_check`, it does not need to
  check whether the types are actually correct.
* `return_type` returns the type name(s) returned by the function.  Like 
  `create` it need not check whether it actually works.  If a function returns
  a list of things, this function will do so as well.

#### Why?

Let's look at multiplication.  `mul` has, including filling and return-only
versions, 594 distinct valid signatures, in a dozen or so patterns, all of which
have to actually work.  This is already too many to have each one represented
directly in the source file - I know, because I tried it:  it would be about
half the size as the vornmath library is as a whole right now.  Worse still
would be `fill`, which has tens of millions of signatures, almost none of which
will ever actually get used, and I'm not about to try to judge which ones are
actually sane.  So these have to get generated at some point at runtime, and as
late as possible is the best choice.

Meanwhile, the work required to calculate which function to call in the first
place (and indeed whether that is a usable function!) is quite complicated.  By
placing simple dispatch functions for already-known signatures, the complicated
work is avoided as much as possible.

#### hasBakery

```lua
vm.utils.hasBakery(name, {typenames}) --> bakery
```

`hasBakery` will go through the bakeries for a named function and find one that
matches the types passed.  It will also modify the typenames table, typically
by adding `nil` to the signature or by deleting extraneous types.  If it doesn't
find a bakery it will return `false` (if a function by that name exists but not
with that signature) or `nil` (if the function doesn't exist), so it also works
as a boolean.

#### bake

```lua
vm.utils.bake(name, {typenames}) --> function
```

`bake` actually generates the function with the required signature, and also
generates any proxies required to reach the signature function when the generic
is called.  It returns the function generated.  Note: this does call
`hasBakery`, so the typenames table may be modified.  Will raise an error if no
such bakery exists.

```lua
vm.utils.bakeByCall(name, ...) --> function
```

`bakeByCall` extracts the types of each argument passed as part of `...` and
uses them to bake.

### Metatables amd types

every type used by vornmath gets a metatable.  In addition to operator overloads
and the metameta that enables lazy generation of functions, this metatable
contains some readable information about the type itself:

* `vm_storage` is the name of the underlying numeric type
* `vm_shape` is the shape of the type: `'scalar'`, `'vector'`, or `'matrix'`
* `vm_dim` is the dimensions of the type: `1` for scalars, a number for vectors,
and `{width, height}` for matrices.
* `vm_type` has it all together as the official typename of the type.

`number`, `boolean`, `string`, and `nil` also get their own "metatables" though
they do not get attached to the types, but see 

### Utility functions

#### type

```lua
vm.utils.type(obj) --> typename
```

Returns the name of the vornmath type (if it exists) or the lua type (if not).

#### getmetatable

```lua
vm.utils.getmetatable(obj) --> metatable
```

Returns the vornmath metatable of the object: for built-in types where the
metatable doesn't exist or is fixed, will return the fake metatable created for
vornmath.

#### findTypeByData

```lua
vm.utils.findTypeByData(shape, dim, storage) --> typename
```

Returns the typename that matches the given information.  Will return `nil` if
there isn't one.

#### consensusStorage

```lua
vm.utils.consensusStorage(types) --> typename
```

Finds the consensus storage type, the numeric type that can represent every type
of number found in the given types.

#### componentWiseConsensusType

```lua
vm.utils.componentWiseConsensusType(types) --> typename
```

Finds the "consensus type", the type that would be returned by a componentwise 
function that is passed arguments of these types: it will have the smallest
storage that fits the data, and will be a vector if there are vector types or a 
matrix if there are matrix types.  Will return `nil` instead if there are both
matrix and vector types, or if there are matrices or vectors of different
dimensions, or if the type required isn't suported.

### Expansion Bakeries

Expansion bakeries are generic functions that create additional bakeries to
expand the abilities of a function in common ways.

#### ComponentWiseReturnOnlys

```lua
vm.utils.componentWiseReturnOnlys(function_name, arity, forced_storage) --> bakery
```

Most vornmath functions accept an "out variable" that it fills in with the
results, that it also returns.  However if we want to actually create a new
object, that out variable isn't required; this expander creates the functions
that create a fresh object before doing the main operation.

This works on things where the numeric type coming out is the the one produced
by `componentWiseConsensusType`: it doesn't work for `length` because that isn't
componentwise, and it doesn't work for `abs` because that only makes `number`ish
things.

#### twoMixedScalars

```lua
vm.utils.twoMixedScalars(function_name) --> bakery
```

This bakery accepts things such as `add(number, quat)` and adds casts to
get it to use the same underlying function as `add(quat, quat)`.

#### componentWiseExpander

```lua
vm.utils.componentWiseExpander(function_name, shapes)
```

Generates a bakery that expands a function to accept the various shapes as
inputs.  `shapes` is a table of `vm_shape` values, `scalar`, `vector`, and
`matrix`; `function_name` is the name of the function this bakery is part of.
This is easiest to explain by example: `add` is already defined so it can add
two numbers; `vm.utils.componentWiseExpander('add', {'vector', 'number'})` makes
it so a vector and a number can be added: `vm.vec3(2,3,4) + 5` will now give
`vm.vec3(7,8,9)`.

#### quatOperatorFromComplex

```lua
vm.utils.quatOperatorFromComplex(function_name) --> bakery
```

For a function that accepts and returns a single complex number, there is a
simple way to make it also work for quaternions.  Use this bakery to enable 
that.

#### genericConstructor

```lua
vm.utils.genericConstructor(function_name) --> bakery
```

This allows the use of any `fill` function as a constructor as well: since, for
instance, `fill(complex, number, number)` is a valid signature for `fill`,
`complex(number, number)` is a valid signature for `complex`

### Simple signature checks

#### justNilTypeCheck

```lua
vm.utils.justNilTypeCheck
```

Mostly used for constructors, a bakery that gets this function as its
`signature_check` will accept a completely blank signature.

#### clearingExactTypeCheck

```lua
vm.utils.clearingExactTypeCheck(types) --> signature_check function
```

Will match a signature that are exactly the list of types given, and clear out
any further types from the table.  This clearing has the effect of mitigating
the effects of accidentally calling a function with too many arguments, which
should work just fine and get ignored just like a regular Lua function.

#### nilFollowingExactTypeCheck

```lua
vm.utils.nilFollowingExactTypeCheck(types) --> signature_check function
```

much like clearingExactyTypeCheck, will match signatures that are exactly the
list given.  This one however pads it out with a `'nil'`, which will get
included in the signature used for the specific function.  This is used
primarily for return-only versions of a function, which look almost exactly
like the ones that include out variables; `add_complex_complex_complex`'s
existence means that `add_complex_complex` doesn't work correctly, but
`add_complex_complex_nil` would, and that's what it's here for.

### Other functions

#### unmProxy

```lua
vm.utils.unmProxy
```

It turns out that the usual `__unm` metamethod gets its argument passed twice to
it, which interferes with the out variable setup vornmath uses.  This function
is used in the metatables for vornmath types to avoid this problem.

#### vectorNilConstructor

```lua
vm.utils.vectorNilConstructor(storage,d) --> bakery
```

A default constructor for a vector; tell it the storage type and the size of the
vector and this bakery will be used to initialize storage for such a vector.

#### matrixNilConstructor

```lua
vm.utils.matrixNilConstructor(storage,w,h) --> bakery
```

Like `vectorNilConstructor` but for matrices instead.