# Structural pattern matching

This document proposes the addition of runtime structural pattern matching to
the Crystal programming language.

## Examples

```crystal
# Before
ary = [1, 2, 3, 4, 5, 6, 7]
if ary.size >= 2
  a, b = ary
  rest = ary[2..]
else
  raise "not enough elements"
end

# After
[1, 2, 3, 4, 5, 6, 7] ~> [a, b, *rest]
```

```crystal
# Before
if ary.size == 3
  first, x, y = ary
end
if first.is_a?(Circle) && x.is_a?(Int32) && y.is_a?(Int32)
  first.move_to(x, y)
end

# After
if ary ~>? {first = Circle, x = Int32, y = Int32}
  first.move_to(x, y)
end
```

```crystal
# Before
anniversary = events.find do |ev|
  ev.has_key?("start") && ev["start"].in?("2020-01-01".."2020-12-31") &&
    ev.has_key?("id") && ev["id"] =~ /^ANNIV.*/
end["start"]
events.select! &.[]?("start").== anniversary

# After
events ~> {*_, {
  "start" => anniversary = "2020-01-01".."2020-12-31",
  "id" => /^ANNIV.*/,
}, *_}
events.select! &.~>?({"start" => ^anniversary})
```

## Optional match operator

The `~>?` operator expects an expression on the left hand side and a pattern on
the right, and attempts to match the expression against that pattern. If
matching succeeds, all bound variables in the pattern are assigned the extracted
values, and this operator returns `true`; otherwise, none of the bound variables
are modified and `false` is returned. `~>?` has a lower precedence than
assignment operators, but higher precedence than splats.

All single identifiers appearing inside the pattern are allowed to declare new
local variables, unless that variable expression is _pinned_.

The Ruby counterpart of this operator is `in`.

`~>?` can be called using the method call syntax and the short block syntax.
Note, however, that any variables newly declared in the pattern will be scoped
to that block and inaccessible from outside:

```crystal
if exp.any? .~>? {a, b} # finds any 2-element list
  a # Error: undefined local variable or method 'a' for top-level
end

# the above is equivalent to:
if exp.any? { |__arg0| __arg0 ~>? {a, b} }
  a
end
```

## Pin operator

The `^` unary operator may only appear within patterns, and indicates that the
pinned expression is interpreted as a single value, not as a sub-pattern. `^`
has the same precedence as splats.

A pinned expression may refer to a variable declared before the pattern, as well
as any bound variables declared before the current expression:

```crystal
var ~>? {a, ^a, a}
# first `a` declares a bound variable
# second `a` refers to the first `a`, so the first two elements of `var` must match
# third `a` re-declares a bound variable and overwrites the first two `a`s
```

It is an error to pin the same expression more than once. The pin operator may
never appear outside patterns.

## Strict match operator

The `~>` operator is similar to `~>?`, except it returns `nil` in case of
success, and raises an exception of type `MatchFailedError` in case of failure.
This operator also has the same precedence as `~>?`. The expression `exp ~> pat`
is equivalent to `(exp ~>? pat) ? nil : ::raise(::MatchFailedError.new(...))`.

The Ruby counterpart of this operator is `=>`. Note that Crystal cannot use
`=>`, because the expression `{1 => x}` may then refer to either a 1-element
`Tuple` with `1` matched against the variable `x`, or a 1-element `Hash` with
key `1` and value `x` (which may be a variable or a call).

`~>` can be called using the method call syntax, like `~>?`.

## Pattern syntax

The abstract syntax of patterns is described below:

```text
<pattern> ::= <paren-pattern>
            | <var-pattern>
            | <underscore-pattern>
            | <assign-pattern>
            | <constant-pattern>
            | <array-pattern>
            | <hash-pattern>

<paren-pattern> ::= '(' . <pattern> . ')'

<var-pattern> ::= <Var>
              ::= <TypeDeclaration>

<underscore-pattern> ::= <Underscore>

<assign-pattern> ::= <Var> . '=' . <pattern>

<constant-pattern> ::= <NilLiteral>
                     | <BoolLiteral>
                     | <NumberLiteral>
                     | <CharLiteral>
                     | <StringLiteral>
                     | <RegexLiteral>
                     | <RangeLiteral>
                     | <SymbolLiteral>
                     | <ProcLiteral>
                     | <Path>
                     | <Generic>
                     | '^' . <expression>

<array-pattern> ::= '{' . <array-pattern-items> . '}'
                  | '[' . <array-pattern-items> . ']'
                  | <Path> . '{' . <array-pattern-items> . '}'
                  | <Generic> . '{' . <array-pattern-items> . '}'

<hash-pattern> ::= '{' . <hash-pattern-items> . '}'
                 | '{' . <named-tuple-pattern-items> . '}'
                 | <Path> . '{' . <hash-pattern-items> . '}'
                 | <Generic> . '{' . <hash-pattern-items> . '}'

<array-pattern-items> ::= <array-pattern-item>
                        | <array-pattern-item> . ','
                        | <array-pattern-item> . ',' . <array-pattern-items>

<hash-pattern-items> ::= <hash-pattern-item>
                       | <hash-pattern-item> . ','
                       | <hash-pattern-item> . ',' . <hash-pattern-items>

<named-tuple-pattern-items> ::= <named-tuple-pattern-item>
                              | <named-tuple-pattern-item> . ','
                              | <named-tuple-pattern-item> . ',' . <named-tuple-pattern-items>

<array-pattern-item> ::= <pattern>
                       | '*' . <Var>
                       | '*' . <Underscore>

<hash-pattern-item> ::= <expression-except-var> '=>' <pattern>
                      | '^' . <expression>
                      | '**' . <Var>
                      | '**' . <NilLiteral>

<named-tuple-pattern-item> ::= <named-tuple-key> <pattern>
                             | '**' . <Var>
                             | '**' . <NilLiteral>

<expression> ::= /* any valid Crystal expression denoting a single value */

<expression-except-var> ::= <expression> - <Var> - <Underscore>

<named-tuple-key> ::= /* any valid NamedTuple key */
```

## Pattern semantics

Each pattern is associated with a success condition, which dictates whether that
pattern successfully matches. A compound pattern usually requires that all
sub-patterns also succeed, in the order they are defined. No bound variables are
written to unless the whole match succeeds; however, the match algorithm may
define temporary variables to store intermediate results.

After a successful match, all bound variables are assigned according to their
specified types, again in the order they are defined.

Given the following where `x` is a bound variable of `pat` not defined prior to
the pattern expression:

```crystal
if exp ~>? pat
  # matched branch
  x
  typeof(x) # => T
else
  # failed branch
  x # Error: read before assignment to local variable 'x'
end

typeof(x) # => (T | Nil)
```

The `x` in the matched branch receives a specified type according to its
position within `pat`, and is undefined in the failed branch. Due to flow
typing, `x` will become nilable after the whole `if` expression. If instead `x`
was defined before the match, its type afterwards will become the union of the
bound variable type and its original type:

```crystal
typeof(x) # => T

if exp ~>? pat
  # matched branch
  typeof(x) # => U
else
  # failed branch
  typeof(x) # => T
end

typeof(x) # => (T | U)
```

A pattern also has its own type that may be used to constrain the type of the
matched expression. If that expression is a variable, its type shall be filtered
in a conditional expression:

```crystal
var = exp
typeof(var)   # => T
if var ~>? [a = Int32]
  typeof(var) # the `Array` subset of `T`
elsif var ~>? {*_}
  typeof(var) # `T`'s subset that responds to `#size` and `#[]`
elsif var ~>? Int32
  typeof(var) # => Int32
else
  typeof(var) # => T
end
typeof(var)   # => T
```

The types in the different branches need not be mutually exclusive.

The different kinds of patterns are described below:

### Parenthesized pattern

```crystal
exp ~>? (pat)
```

Patterns may be parenthesized to override operator precedence; they have no
other effects. There must be exactly one sub-pattern enclosed within the
parentheses.

* **Success condition:** `exp ~>? pat`.
* **Bound variables:** All bound variables of `pat`.
* **Pattern type:** The same type as `pat`.

### Variable pattern

```crystal
exp ~>? var
```

A variable pattern captures an expression into a variable. `var` always
(re-)declares a variable.

* **Success condition:** Always.
* **Bound variables:** `var : typeof(exp)`.
* **Pattern type:** The same type as `exp`.

### Underscore pattern

```crystal
exp ~>? _
```

The underscore pattern ignores a value, and usually appears as a sub-pattern.
Assignments to the underscore during pattern matching are always removed,
including any associated side effects.

* **Success condition:** Always.
* **Bound variables:** None.
* **Pattern type:** The same type as `exp`.

### Assignment pattern

```crystal
exp ~>? var = pat
```

An assignment pattern matches `exp` against a sub-pattern, and additionally
assigns `exp` to `var` in case of a successful match. It also frequently
appears as a sub-pattern.

* **Success condition:** `exp ~>? pat`.
* **Bound variables:** All bound variables of `pat`, plus `var : typeof(exp)`.
* **Pattern type:** The same type as `pat`.

### Constant pattern

```crystal
exp ~>? pat

exp ~>? 0      # (1)
exp ~>? T      # (2)
exp ~>? ^var   # (3)
exp ~>? ^[var] # (3)
```

A constant pattern matches `exp` against a constant using case equality
(`#===`). The form (1) supports any literal, form (2) supports any type
(including generics), and form (3) supports any Crystal expression. Pinning an
expression forces Crystal to interpret it as a single value even if it is an
otherwise legal pattern:

```crystal
# This:
exp ~>? [1, 2]
# is equivalent to:
exp.responds_to?(:[]) &&
  exp.responds_to?(:size) &&
  exp.is_a?(::Array) &&
  exp.size == 2 && 1 === exp[0] && 2 === exp[1]

# This:
exp ~>? ^[1, 2]
# is equivalent to:
[1, 2] === exp
```

* **Success condition:** `pat === exp`.
* **Bound variables:** None.
* **Pattern type:** (1, 3) The same type as `exp`. (2) `T`.

### Fixed array pattern

```crystal
exp ~>? {pat1, pat2, ...}  # (1)
exp ~>? T{pat1, pat2, ...} # (2)
exp ~>? [pat1, pat2, ...]  # (3)
```

(1) matches any array-like object whose size is the same as the number of
sub-patterns given, and whose corresponding elements match the sub-patterns
pair-wise. There cannot be any splats among the sub-patterns; a splat cannot be
applied to a pattern alone, and a tuple literal that contains splat expansions
must be pinned.

(2) and (3) additionally require, respectively, that `exp` is a `T` or `Array`.
None of the patterns have an `of`-clause.

* **Success condition:** `exp.responds_to?(:[])`, `exp.responds_to?(:size)`,
  `exp.size` is equal to the number of sub-patterns given, and for each element
  `elem` of `exp` and its corresponding pattern `pat`, `elem ~>? exp`. (2)
  Additionally `exp.is_a?(T)`. (3) Additionally `exp.is_a?(::Array)`.
* **Bound variables:** All bound variables of each of `pat1, pat2, ...`.
* **Pattern type:** The subset of `exp` that (1) responds to `#[]` and `#size`;
  (2) is `<= T`; (3) is `<= ::Array`.

### Splat array pattern

```crystal
exp ~>? {pat_left, ..., *var, pat_right, ...}
```

This is similar to the fixed array case, except one splat expression may be
present anywhere inside the pattern. The patterns before and after the splat,
which may both be empty, match the elements at the start and the end of the
`exp` respectively, and they cannot overlap. If `var` is a variable, all
elements in the middle are assigned to it; nothing is done if `var` is the
underscore.

Analogous patterns are defined that take the form of an array literal or an
array-like literal.

* **Success condition:** Suppose there are `m` sub-patterns before `*var` and
  `n` sub-patterns after `*var`. Then `exp.responds_to?(:[])`,
  `exp.responds_to?(:size)`, `exp.size >= m + n`,
  `exp[0...m] ~>? {pat_left, ...}`, and `exp[-n..] ~>? {pat_right, ...}`.
* **Bound variables:** All bound variables of each of `pat_left, ...` and
  `pat_right, ...`, plus `var : typeof(exp[range])` for some `range : Range`.
  This `range` is always known at compile-time.
* **Pattern type:** The subset of `exp` that responds to `#[]` and `#size`.

### Search array pattern

```crystal
exp ~>? {pat_left, ..., *var_left, pat_mid, ..., *var_right, pat_right, ...}
```

The search pattern is a further generalization of the splat pattern where two
splats can be used. The prefix and the suffix of `exp` are matched as above;
then, `pat_mid, ...` is searched in the remaining elements from left to right,
and the first matching subsequence causes the whole match to succeed. The middle
part cannot be empty. The two splats are assigned the subranges between the
matched elements, unless they are underscores.

Analogous patterns are defined that take the form of an array literal or an
array-like literal.

* **Success condition:** Suppose there are `m` sub-patterns before `*var_left`,
  `n` sub-patterns between `*var_left` and `*var_right`, and `p` sub-patterns
  after `*var_right`. Then `exp.responds_to?(:[])`, `exp.responds_to?(:size)`,
  `exp.size >= m + n + p`, `exp[0...m] ~>? {pat_left, ...}`,
  `exp[-p..] ~>? {pat_right, ...}`, and there exists `i` such that
  `m <= i <= exp.size - n - p` and `exp[i...i + n] ~>? {pat_mid, ...}`.
* **Bound variables:** All bound variables of each of `pat_left, ...`,
  `pat_mid, ...`, and `pat_right, ...`, plus `var_left : typeof(exp[range])` and
  `var_right : typeof(exp[range])` for some `range : Range`. This `range` is not
  known at compile-time.
* **Pattern type:** The subset of `exp` that responds to `#[]` and `#size`.

### Simple hash pattern

```crystal
exp ~>? {key1 => pat1, key2 => pat2, ...}  # (1)
exp ~>? T{key1 => pat1, key2 => pat2, ...} # (2)
exp ~>? {key1: pat1, key2: pat2, ...}      # (3)
```

(1) matches any hash-like object that has the given keys, and whose
corresponding values match the given patterns. Extra elements are ignored. Each
key can be an arbitrary Crystal expression other than a variable, and will be
used for hash lookup directly. To avoid confusion, variables must be pinned when
used as keys:

```crystal
a = 0
exp ~>? {a => a}  # not allowed
exp ~>? {^a => a} # assigns `exp[0]` to `a` if match succeeds
```

(2) and (3) additionally require, respectively, that `exp` is a `T` or
`NamedTuple`. None of the patterns have an `of`-clause.

* **Success condition:** `exp.responds_to?(:[])`, `exp.responds_to?(:has_key?)`,
  and for each entry `key => pat`, `exp.has_key?(key)` and `exp[key] ~>? pat`.
  (2) Additionally `exp.is_a?(T)`. (3) Additionally `exp.is_a?(::NamedTuple)`.
* **Bound variables:** All bound variables of each of `pat1, pat2, ...`.
* **Pattern type:** The subset of `exp` that (1) responds to `#[]` and
  `#has_key?`; (2) is `<= T`; (3) is `<= ::NamedTuple`.

### Splat hash pattern

```crystal
exp ~>? {key1 => pat1, ..., **var}
```

If a double splat is specified at the end of the simple hash pattern and `var`
is a variable, all remaining key-value pairs in `exp` are assigned to it. This
result may be empty if all the keys in `exp` are included by `key1, ...`.

Analogous patterns are defined that take the form of a named tuple literal or a
hash-like literal.

* **Success condition:** Same as for simple hash pattern, and additionally
  `exp.responds_to?(:reject)`.
* **Bound variables:** All bound variables of each of `pat1, pat2, ...`, plus
  `var : typeof(exp.reject(key1, key2, ...))`.
* **Pattern type:** The subset of `exp` that responds to `#[]`, `#has_key?`, and
  `#reject`.

### Fixed hash pattern

```crystal
exp ~>? {key1 => pat1, ..., **nil}
```

If a double splat of `nil` is specified instead, `exp` may not contain any extra
keys that do not already appear in the pattern. If `exp` responds to `#size`,
then `exp.size` must also not be greater than the number of key-value pairs in
the pattern.

Analogous patterns are defined that take the form of a named tuple literal or a
hash-like literal.

* **Success condition:** Same as for simple hash pattern, and additionally
  `exp.responds_to?(:all)`, and
  `keys = ::Tuple.new(key1, ...); exp.all? { |k, _| keys.includes?(k) }`.
* **Bound variables:** All bound variables of each of `pat1, pat2, ...`.
* **Pattern type:** The subset of `exp` that responds to `#[]`, `#has_key?`, and
  `#all?`.

## Case expressions

Pattern matching in the `when`-clauses and `in`-clauses of a `case` expression
is possible through the implicit object syntax:

```crystal
case [1, 2, 3, 4]
when .~>? {a, b, *c}
  # 2 or more elements
  typeof(a) # => Int32
  typeof(b) # => Int32
  typeof(c) # => Array(Int32)
when .~>? {a}
  # 1 element
  typeof(a) # => Int32
end
typeof(a) # => (Int32 | Nil)
typeof(b) # => (Int32 | Nil)
typeof(c) # => (Array(Int32) | Nil)
```

This declares the variables `a`, `b`, and `c` with the appropriate types in case
of successful matches.

This proposal does not aim to change the exhaustive check semantics of
`in`-clauses. Using a pattern match condition in an exhaustive `case` expression
does not cover any branches.

## Macro language

The following node types shall be added to the macro language:

```crystal
module Crystal
  module Macros
    # A `~>?` or `~>` call.
    class PatternMatch < ASTNode
      # Returns the expression being matched.
      def exp : ASTNode
      end

      # Returns the pattern being matched against.
      def pattern : ASTNode
      end

      # Returns whether this pattern match is strict (`~>`) or optional (`~>?`).
      def strict? : BoolLiteral
      end
    end

    # A pinned expression (`^exp`) inside a pattern.
    class Pin < ASTNode
      # Returns the pinned expression.
      def exp : ASTNode
      end
    end
  end
end
```

It is very likely the compiler internally uses the same representations for
these AST nodes.

The pattern matching operators and the pin themselves are unavailable within the
macro language.

## Known limitations

* `([1, 2] || {3}) ~>? {1, 2}` will fail to compile because `{3}[1]` is a
  compile-time error. On the other hand, calling `#fetch` loses `Tuple`'s type
  safety.
* A lot of hash-like types, most notably `JSON::Any`, define `#[]?` but not
  `#has_key?`, and the hash patterns do not fall back to the former at the
  moment.
* The array find pattern cannot be used when the expression is a `Tuple` and
  either splat expression is a variable, because `Tuple#[](range : Range)` does
  not accept runtime values at the moment.
* The splat hash pattern requires compiler support for
  `NamedTuple#reject(*keys)` when the splat expression is a variable.
