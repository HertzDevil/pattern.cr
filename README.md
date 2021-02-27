# pattern.cr

Structural pattern matching proof-of-concept library

## Usage

Due to syntax restrictions, macro arguments must be valid Crystal expressions
and cannot declare new variables, and features like splats in container literals
are not supported (but see
[crystal-lang/crystal#3718](https://github.com/crystal-lang/crystal/issues/3718)). The following conventions are applied in this library:

* `exp ~>? pat` becomes `Pattern.matches?(exp, pat)`. Flow typing will not work
  properly because the bound variables in `pat` must be declared prior to this
  point; use `Pattern.try_match(exp, pat)` in those cases instead.
* `exp ~> pat` becomes `Pattern.match!(exp, pat)`. Flow typing works here due to
  the exception thrown in the failing branch.
* `*x` in array patterns are replaced with `__splat(x)`. The `__splat` doesn't
  need to be an existing method.
* `**x` in hash patterns are replaced with `__double_splat => x`. Note that
  `NamedTuple` patterns cannot have a double splat in this way.

Refer to the same examples in [`SPEC.md`](SPEC.md#Examples) to see how compiler
support for structural pattern matching would look like. See also the
[known limitations](SPEC.md#Known-limitations).

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
require "pattern"
a, b, rest = nil, nil, nil
Pattern.match! [1, 2, 3, 4, 5, 6, 7], [a, b, __splat(rest)]
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
require "pattern"
first = nil
x = nil
y = nil
Pattern.try_match(ary, {first = Circle, x = Int32, y = Int32}) do
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
require "pattern"
anniversary = nil
Pattern.match!(events, {__splat(_), {
  "start" => anniversary = "2020-01-01".."2020-12-31",
  "id" => /^ANNIV.*/,
}, __splat(_)})
events.select! do |ev|
  Pattern.matches?(ev, {"start" => __pin(anniversary)})
end
```

## Installation

1. Add the dependency to your `shard.yml`:

   ```yaml
   dependencies:
     pattern:
       github: HertzDevil/pattern.cr
   ```

2. Run `shards install`

## Contributing

1. Fork it (<https://github.com/HertzDevil/pattern.cr/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Contributors

* [Quinton Miller](https://github.com/HertzDevil) - creator and maintainer
