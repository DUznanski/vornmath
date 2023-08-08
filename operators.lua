-- This is a bunch of functions that are all done componentwise:
-- if applied to a vector it performs the operation on each component individually.


-- functions I use to complete other functions
local abs = math.abs
local exp = math.exp
local floor = math.floor
local log = math.log
local max = math.max
local min = math.min
local sqrt = math.sqrt

-- constants
local ln2 = log(2)
local huge = math.huge

-- atan is complicated because in 5.3, atan takes over the functionality of atan2
-- this is what we want, so we'll emulate that behavior in earlier versions.
local atan
do
	local math_atan = math.atan
	local math_atan2 = math.atan2
	if math_atan2 then
		atan = function(a,b)
			if not b then return math_atan(a)
			else return math_atan2(a,b)
			end
		end
	else
		atan = math_atan
	end
end

-- tanh is missing in 5.3+
local tanh
if math.tanh then
	tanh = math.tanh
else
	tanh = function (x)
		local y = exp(2 * x)
		return (y - 1) / (y + 1)
	end
end

-- now, on to new functions.

-- clamp and sign are used to define other functions.
local function clamp(x, lo, hi)
	return min(max(lo, x), hi)
end

local function sign(x)
	if x > 0 then return 1
	elseif x < 0 then return -1
	else return 0 end
end

-- roundEven, step, and smoothstep just complicated, so including them directly in the table is nasty.
local function roundEven(x)
	local base = floor(x)
	local extra = x - base
	if base % 2 == 0 and extra > 0.5 then
		return base + 1
	elseif extra >= 0.5 then
		return base + 1
	else
		return base
	end
end

local function step(edge, x)
	if x < edge then
		return 0
	else
		return 1
	end
end

local function smoothstep(lo, hi, x)
	local t = clamp((x - lo) / (hi - lo), 0, 1)
	return t * t * (3 - 2*t)
end

-- here I make a complete list of every componentwise math function.
-- simple functions are defined inline here.
local functions = {
	-- 0. arithmetic
	unm = function(x) return -x end,
	add = function(x, y) return x + y end,
	sub = function(x, y) return x - y end,
	mul = function(x, y) return x * y end,
	div = function(x, y) return x / y end,
	mod = function(x, y) return x % y end,
	-- 1. trig
	--  a. angle
	degrees = math.deg,
	radians = math.rad,
	--  b. forward trig
	sin = math.sin,
	cos = math.cos,
	tan = math.tan,
	--  c. inverse trig
	asin = math.asin,
	acos = math.acos,
	atan = atan,
	--  d. forward hyperbolic trig
	sinh = math.sinh or function(x) return (exp(x) - exp(-x)) / 2 end, -- sinh and cosh go away in 5.3
	cosh = math.cosh or function(x) return (exp(x) + exp(-x)) / 2 end,
	tanh = tanh,
	--  e. inverse hyperbolic trig
	asinh = function(x) return log(x + sqrt(x*x+1)) end,
	acosh = function(x) return log(x + sqrt(x*x-1)) end,
	atanh = function(x) return log((1+x) / (1-x)) end,
	-- 2. exponentials
	pow = math.pow or function(x,y) return x^y end, -- pow goes away in 5.3
	exp = exp,
	exp2 = function(x) return exp(ln2 * x) end,
	log = log,
	log2 = function(x) return log(x) / ln2 end,
	sqrt = sqrt,
	inversesqrt = function(x) return 1 / sqrt(x) end,
	-- 3. common functions
	--  a. sign functions
	abs = abs,
	sign = sign,
	--  b. rounding functions
	floor = floor,
	ceil = math.ceil,
	trunc = function(x) return floor(abs(x)) * sign(x) end,
	fract = function(x) return x - floor(x) end,
	round = function(x) return floor(x + 0.5) end,
	roundEven = roundEven,
	modf = math.modf,
	--  c. extrema functions
	min = min,
	max = max,
	clamp = clamp,
	--  d. stepping functions
	mix = function(a, b, t) return a * (1 - t) + b * t end,
	step = step,
	smoothstep = smoothstep,
	--  e. nastiness-checking functions
	isnan = function(x) return x ~= x end,
	isinf = function(x) return x == huge or -x == huge end,
	-- 4. boolean functions
	--  a. comparators
	lessThan = function(x,y) return x < y end,
	lessThanEqual = function(x,y) return x <= y end,
	greaterThan = function(x,y) return x > y end,
	greaterThanEqual = function(x,y) return x >= y end,
	equal = function(x,y) return x == y end,
	notEqual = function(x,y) return x ~= y end,
	--  b. boolean operators
	logicAnd = function(x,y) return x and y end,
	logicOr = function(x,y) return x or y end,
	logicXor = function(x,y) return (x and not y) or (y and not x) end,
	logicNot = function(x) return not x end
}

-- so this works like this:

-- b becomes bool or bvec
-- f becomes float or vec
-- F becomes float or vec, and most importantly can be float when everything else is vec
-- so, for instance, clamp can have signatures
-- float clamp(float x, float lo, float hi)
-- vec2 clamp(vec2 x, vec2 lo, vec2 hi)
-- vec2 clamp(vec2 x, float lo, float hi)
-- and so on with the other vec sizes
-- all of these entries are componentwise.

-- these all come from glsl, with signatures up to version 4.6.

-- this lets me generate the operators without having to write 44ish things into vector, oh god

local aritys = {
	['f:f'] = {'degrees', 'radians', 'sin', 'cos', 'tan', 'asin', 'acos', 'atan',
	        'sinh', 'cosh', 'tanh', 'asinh', 'acosh', 'atanh', 'exp', 'exp2',
	        'log', 'log2', 'sqrt', 'abs', 'sign', 'floor', 'ceil', 'trunc',
	        'round', 'roundEven', 'unm'},
	['f:ff'] = {'atan'},
	['b:f'] = {'isnan', 'isinf'},
	['f:ffF'] = {'mix'},
	['f:fFF'] = {'clamp'},
	['f:FFf'] = {'smoothstep'},
	['f:fF'] = {'min', 'max', 'add', 'sub', 'mul', 'div',},
	['f:Ff'] = {'step', 'add', 'sub', 'mul', 'div'},
	['b:ff'] = {'lessThan','lessThanEqual','greaterThan','greaterThanEqual','equal','notEqual'},
	['b:bB'] = {'logicAnd', 'logicOr', 'logicXor'},
	['b:Bb'] = {'logicAnd', 'logicOr', 'logicXor'},
	['b:b'] = {'logicNot'}
}

-- this does not include any of the non-component ones: any, all, geometry, matrix, etc
-- which is fine.
-- but more importantly, mix has two implementations; the other one is f:ffb, which doesn't do multiplication
-- and so can be safely used when there's NaNs involved.
-- so that one I have to handle separately.
-- also, modf, because it's naughty.