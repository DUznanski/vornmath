# vornmath

Vorn's Lua Math Library

Vornmath is (will be) a comprehensive vector and complex math library for lua.

## Installing and Using

Vornmath is a single file, pure Lua library; it does not add any symbols to global.  Just put it somewhere convenient in your source tree and do

```lua
local vm = require('vornmath')
```

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
mul_number_number
mul_vec3_cvec3
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
number() --> 0
number(n) --> n
number(str, [base]) --> string as number in given base (default 10)
```

this is Lua's built-in `number` type.  There's not much to say about it!

The interpretation of strings as numbers comes directly from Lua.

### `complex`

```lua
complex() --> 0 + 0i
complex(a) --> a + 0i
complex(a, b) --> a + bi
complex(a + bi) --> a + bi
```

Complex numbers, of the form `a + bi`.  They have fields `a`, the real part, and
`b`, the imaginary part.  Some functions (in particular `log`arithms and
`sqrt`) will behave slightly differently for complex numbers than regular
numbers: these functions have some values in which no real answer is possible,
and so will not work when given a `number`, but will when given a `complex` of
equivalent value.  In addition, complex numbers do not have a natural ordering,
so `lt` (`<`) and its friends will not work even on real-valued complexes.

### `quat`ernion

```lua
quat() --> 0 + 0i + 0j + 0k
quat(a) --> a + 0i + 0j + 0k
quat(a,b,c,d) --> a + bi + cj + dk
quat(a+bi) --> a + bi + 0j + 0k
quat(a+bi, c+di) --> a + bi + cj + dk
quat(a+bi+cj+dk) --> a + bi + cj + dk
quat(vec3(b, c, d), angle) --> cos(angle/2) + sin(angle/2) * (bi + cj + dk) 
quat(a+bi, vec3(c, d, e)) --> a + b * (ci + dj + ek)
```

Higher dimensional complex numbers, of the form `a + bi + cj + dk`.  Fields `a`,
`b`, `c`, and `d` access the various components.  Somehow, many things that
work with complex numbers also work with quaternions! (I know, I was surprised
too)  However, quaternion multiplication is *non-commutative*: if `x` and `y`
are quaternions, then `x * y` and `y * x` usually give different results.

The axis-angle and complex-axis constructors both expect (but neither enforce
nor convert to) a unit vector; you might get unexpected results if you pass
something else.

### `boolean`

```lua
boolean() --> false
boolean(x) --> x
```

This is Lua's built-in `boolean` type.  Not much to say about it either!

### `vec`tors

```lua
vec2() --> <0, 0>
vec3(a) --> <a, a, a>
cvec4(vec2(a,b), cvec3(c,d,e)) --> <complex(a), complex(b), c, d>
bvec2() --> <false, false>
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

### `mat`rices

```lua
cmat2() --> [[1+0i,0+0i], [0+0i,1+0i]]
mat3(a) --> [[a,0,0], [0,a,0], [0,0,a]]
mat2x3(a,b,c,d,e,f) --> [[a,b,c], [d,e,f]]
mat3(mat2x3(a,b,c,d,e,f)) --> [[a,b,c], [d,e,f], [0,0,1]]
```

Matrices.  There's 18 of these!  They can use numbers or complexes, can be 2 to
4 columns, and can be 2 to 4 rows.  Like vectors, a letter before `mat`
describes the type of number it stores (nothing for numbers, `c` for complex),
and the number(s) after it describe its size: columns first, then `x`, then
rows.  `mat2x4` is a matrix with two columns and four rows, filled with numbers;
`cmat3x2` is a matrix with three columns and two rows, filled with complex
numbers.  Square matrices, with the same number of rows as columns, have shorter
aliases: `mat4` is equivalent to `mat4x4`, `cmat3` is equivalent to `cmat3x3`.
When used in function signatures, always use the full name, not the alias.

Matrices are indexed numerically by column, starting at `1`; each column is a
`vec`tor in its own right.

The matrix constructor will fill any blank spaces in the result with `0`
except for entries on the diagonal which will receive `1`.

The general constructor can take any number of scalar or vector (not matrix!)
arguments which together provide enough components to completely fill the
matrix so long as the last component of the matrix lands in the last argument.

## Functions

### Operators

The various operators can be accessed through their function names, and have
their signatures included to skip dispatch, or can be used directly as
operators.

#### `add` (`a + b`)

```lua
a + b --> a + b
add(a, b[, c]) --> c = a + b
```

Addition!  If applied to a vector and a scalar, or a matrix and a scalar, or two
vectors of the same size, or two matrices of the same size, it operates
*componentwise*: `3 + vec3(5, 6, 7) => vec3(8, 9, 10)`, for instance.

#### `sub` (`a - b`)

```lua
a - b --> a - b
sub(a, b[, c]) --> c = a - b
```

Subtraction!  Just like addition, but using the negation of the second argument.

#### `unm` (`-a`)

```lua
-a --> -a
unm(a[, b]) --> b = -a
```

Unary negation!  Works on everything.

#### `mul` (`a * b`)

```lua
a * b --> a * b
mul(a, b[, c]) --> c = a * b 
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

#### `div` (`a / b`)

```lua
a / b --> a / b
div(a, b[, c]) --> c = a / b
```

Division!  Uses the same rules as addition.  For quaternions, non-commutative
multiplication technically means there are two different forms of division:
Vornmath uses `p * (1/q)`, sometimes called right division.

#### `mod` (`a % b`)

```lua
a % b --> a % b
div(a, b[, c]) --> c = a % b
```

Modulus!  Only works on `number`s and vectors and matrices storing `number`s.
Gives the remainder of division, `p/q - floor(p/q)`.  Works componentwise.

#### `pow` (`a ^ b`)

```lua
a ^ b --> a ^ b
pow(a, b[, c]) --> c = a ^ b
```

Exponentiation!  Some things that are illegal in real numbers will work
when done in complex numbers: `-1 ^ 0.5` is undefined in real numbers but
`complex(-1) ^ 0.5` works and gives `i`.  `pow` does not work on matrices at
all.

#### `eq` (`a == b` and `a ~= b`)

```lua
a == b --> a == b
eq(a, b) --> a == b
```

Equality!  Works on anything; will return `true` if all elements are equal. For
differing number types, will implicitly convert to the necessary type, so
`eq(5, complex(5,0))` is `true`.

**warning**: using the symbolic equals `==` on `number` and a type other than
`number` doesn't work correctly and will always return `false`, due to
limitations in Lua's metatable system.  Instead, use `eq` if you really need to
do that.

#### `tostring`

```lua
tostring(a) --> a string representation of a
```

Technically this isn't an operator, but it is a thing that gets a metamethod.
Turns a thing into a string!  The representations provided by this are not
valid Lua code: they're designed to be reasonable to look at.

### Trigonometric functions

#### `atan`

```lua
atan(y[, nil, phi]) --> phi = angle
atan(y, x[, phi]) --> phi = angle
```

Computes the inverse tangent or arctangent of the given value.  For `numbers`,
optionally accepts two parameters such that `atan(y, x)` will give the correct
angle across the whole circle, equivalent to `atan2`.  **the out variable is
the *third* parameter** for this function because of this.  This function acts
componentwise on vectors for both `y` and `x`.

### Exponential functions

#### `exp`

```lua
exp(x[, y]) --> y = e^x
```

Computes the exponential function `e^z`.

#### `log`

```lua
log(x[, nil, y]) --> y = ln x
log(x, b[, y]) --> y = log_b x
```

Computes the logarithm.  For single-argument calls, this is the natural log.
The second argument changes the base: `log(8,2) = 3` because `2^3 = 8`.  This
function acts componentwise on vectors.

### Complex and Quaternion functions

#### `arg`

```lua
arg(a+bi[, x]) --> x = atan(b, a)
```

Computes the argument or phase of a complex number, the angle the complex
number makes with the positive real line.

#### `conj`

```lua
arg(a+bi[, z]) --> z = a-bi
arg(a+bi+cj+dk[, z]) --> z = a-bi-cj-dk
```

Computes the conjugate of a complex number or quaternion, which is the same
number except with all the signs on the complex parts switched.

#### `axisDecompose`

```lua
axisDecompose(a+bi+cj+dk[, cpx, axis]) --> ...
-- local l = sqrt(b^2 + c^2 + d^2)
-- cpx = a + li
-- axis = <b, c, d> / l
```

decomposes a quaternion into a complex number and a unit axis.  These can in
turn be fed back into `vm.quat` to reconstruct the original quaternion.

### Common functions

#### `abs`

```lua
abs(x[, y]) --> y = |x|
```

Returns the absolute value, the positive real number with the same magnitude as
the number given.  When used on a vector, acts componentwise.

#### `sqabs`

```lua
sqabs(x[, y]) --> y = |x|^2
```

Returns the square of the absolute value.  When used on a vector, acts
componentwise

### Vector functions

#### `length`

```lua
length(v) --> ||v||
```

Returns the length of a vector.  For complex vectors, this uses the absolute
value, because using straight squaring will cause lengths of some non-zero
vectors to be 0, which is not desirable.

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
versions, 593 distinct valid signatures, in a dozen or so patterns, all of which
have to actually work.  This is already too many to have each one represented
directly in the source file - I know, because I tried it:  it would be about the
same size as the vornmath library is as a whole right now.  Worse still would be
`fill`, which has tens of millions of signatures, almost none of which will ever
actually get used, and I'm not about to try to judge which ones are actually
sane.  So these have to get generated at some point at runtime, and as late as
possible is the best choice.

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

### type

```lua
vm.utils.type(obj) --> typename
```

Returns the name of the vornmath type (if it exists) or the lua type (if not).

### getmetatable

```lua
vm.utils.getmetatable(obj) --> metatable
```

Returns the vornmath metatable of the object: for built-in types where the
metatable doesn't exist or is fixed, will return the fake metatable created for
vm.

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
componentWiseReturnOnlys(function_name, arity) --> bakery
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
twoMixedScalars(function_name) --> bakery
```

This bakery accepts things such as `add(number, quat)` and adds casts to
get it to use the same underlying function as `add(quat, quat)`.

#### Vector and matrix expanders

```lua
vm.utils.componentWiseVector(function_name) --> bakery
vm.utils.componentWiseVectorNil(function_name) --> bakery
vm.utils.componentWiseMatrix(function_name) --> bakery
vm.utils.componentWiseVectorScalar(function_name) --> bakery
vm.utils.componentWiseScalarVector(function_name) --> bakery
vm.utils.componentWiseVectorVector(function_name) --> bakery
vm.utils.componentWiseMatrixScalar(function_name) --> bakery
vm.utils.componentWiseScalarMatrix(function_name) --> bakery
vm.utils.componentWiseMatrixMatrix(function_name) --> bakery
```

These bakeries all expand functions that work on numeric types to also work
componentwise on vectors and matrices.

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

It turns out that the usual `__unm` metamethod gets its argument passed twice to it, which interferes with the out variable setup vornmath uses.  This function is used in the metatables for vornmath types to avoid this problem.

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

Like vectorNilConstructor but for matrices instead.