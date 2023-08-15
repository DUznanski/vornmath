# vornmath

Vorn's Lua Math Library

Vornmath is (will be) a comprehensive vector and complex math library for lua.

## Basic concepts

### Generic and specific forms

All functions in vornmath come in two forms: one in which it is generic and
accepts arguments of any types that are valid for the function, and one in
which the types being passed in are already specified as part of the name.  For
instance, the linear interpolation function `mix` can accept a great variety of
types for its inputs, so it has many signatures, some of which are:

```lua
mix
mix_number_number_number
mix_vec3_cvec3_complex
mix_vec4_vec4_boolean
```

The specified ones have one particular advantage: they are a little faster because they
don't do additional function calls to perform dispatch into the correct
function. On the other hand they do have long annoying names and cannot accept varying types.

In situations where a function has one signature that is a *prefix* of another,
the shorter signature will include a `nil`:

* `atan_number_nil` accepts a single number, and
* `atan_number_number` accepts two.

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

If you already have an object and wish to replace its contents completely, use
`fill`. Usually, this changes the underlying object, but if the object in
question is a `number` or otherwise immutable (I expect that once I get FFI
figured out nicely, `complex` will fall under this), it won't be able to change
it and you'll instead get a fresh object anyway.  **to ward off bad
consequences of this, only use fill on things not used elsewhere, and when you
use fill, assign the result of fill to a value!**

```lua
local a = vm.complex(1,2) -- a is 1+2i
local b = vm.fill(a,3,4) -- b is now 3+4i. a probably is too, but only probably.
```

### Other functions

Functions that aren't constructors or fill always have an optional parameter,
after all the other parameters, where the result object may be stored.  This
optional parameter is required to always be either `nil` (in which case a new
object is created) or of the type that would be returned by the function.  This
optional parameter does not appear in the name of the function, and is always
in exactly the same place.  Very few functions accept a varying number of
parameters, but in those that do, pad the arguments with `nil` to reach the
optional parameter.  **This storage uses `fill`, so all the warnings above
apply here as well!**

```lua
local a = vm.add(3, complex(4,5)) -- a = 7+8i
local b = vm.conj(complex(2,8), some_unused_complex) -- b is 2-8i and uses an existing table
local c = vm.atan(complex(1,2), nil, another_unused_complex) -- c ≈ 1.34 + 0.40i 
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

this is Lua's built-in `number` type.  There's not much to say about it!

### `complex`

Complex numbers, of the form `a + bi`.  They have fields `a`, the real part, and
`b`, the imaginary part.  Some functions (in particular `log`arithms and
`sqrt`) will behave slightly differently for complex numbers than regular
numbers: these functions have some values in which no real answer is possible,
and so will not work when given a `number`, but will when given a `complex` of
equivalent value.  In addition, complex numbers do not have a natural ordering,
so `lt` (`<`) and its friends will not work even on real-valued complexes.

### `quat`ernion

Higher dimensional complex numbers, of the form `a + bi + cj + dk`.  Fields `a`,
`b`, `c`, and `d` access the various components.  Somehow, many things that
work with complex numbers also work with quaternions! (I know, I was surprised
too)  However, quaternion multiplication is *non-commutative*: if `x` and `y`
are quaternions, then `x * y` and `y * x` usually give different results.

### `boolean`

This is Lua's built-in `boolean` type.  Not much to say about it either!

### `vec`tors

Vectors.  There are actually 9 vector types: `vec2`, `vec3`, and `vec4` are 2-,
3-, and 4-dimensional vectors with `number`s as components; `cvec2`, `cvec3`,
and `cvec4` use `complex` numbers, and `bvec2`, `bvec3`, and `bvec4` use
`boolean`s.

### `mat`rices

Matrices.  There's 18 of these!  They can use numbers or complexes, can be 2 to
4 columns, and can be 2 to 4 rows.  Like vectors, a letter before `mat`
describes the type of number it stores (nothing for numbers, `c` for complex),
and the number(s) after it describe its size: columns first, then `x`, then
rows.  `mat2x4` is a matrix with two columns and four rows, filled with numbers;
`cmat3x2` is a matrix with three columns and two rows, filled with complex
numbers.  Square matrices, with the same number of rows as columns, have shorter
aliases: `mat4` is equivalent to `mat4x4`, `cmat3` is equivalent to `cmat3x3`.
When used in function signatures, always use the full name, not the alias.

## functions

### operators

The various operators can be accessed through their function names, and have
their signatures included to skip dispatch, or can be used directly as
operators.

#### `add` (`a + b`)

Addition!  If applied to a vector and a scalar, or a matrix and a scalar, or two
vectors of the same size, or two matrices of the same size, it operates
*componentwise*: `3 + vec3(5, 6, 7) => vec3(8, 9, 10)`, for instance.

#### `sub` (`a - b`)

Subtraction!  Just like addition, but using the negation of the second argument.

#### `unm` (`-a`)

Unary negation!  Works on everything.

#### `mul` (`a * b`)

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

Division!  Uses the same rules as addition.  For quaternions, since
`p * q != q * p`, there is technically ambiguity here, `p / q` might mean
`p * (1/q)` or `(1/q) * p`.  Vornmath uses `p * (1/q)`.

#### `mod` (`a % b`)

Modulus!  Only works on `number`s and vectors and matrices storing `number`s.
Gives the remainder of division, `p/q - floor(p/q)`.  Works componentwise.

#### `pow` (`a ^ b`)

Exponentiation!  Some things that are illegal in real numbers will work
when done in complex numbers: `-1 ^ 0.5` is undefined in real numbers but
`complex(-1) ^ 0.5` works and gives `i`.

#### `eq` (`a == b` and `a ~= b`)

Equality!  Works on anything; will return `true` if all elements are equal. For
differing number types, will implicitly convert to the necessary type, so
`eq(5, complex(5,0))` is `true`.

**warning**: actually using `==` on `number` and a type other than `number`
doesn't work correctly and will always return `false`, due to limitations in
Lua's metatable system.  Instead, use `eq` if you really need to do that.

#### `lt` and `le` (`a < b`, `a > b`, `a <= b`, `a >= b`)

Comparison is not actually implemented: it only works on `number`s anyway.

#### `tostring`

Technically this isn't an operator, but it is a thing that gets a metamethod.
Turns a thing into a string!  The representations provided by this are not
valid Lua code: they're designed to be nice to look at.

