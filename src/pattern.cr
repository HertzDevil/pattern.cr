module Pattern
  # Exception raised when a call to `Pattern.match!` fails.
  class MatchFailedError < Exception
  end

  # :nodoc:
  macro match_cond_exp(exp, pat)
    {% if pat.is_a?(Expressions) %}
      {% raise "expected a single expression" unless pat.expressions.size == 1 %}
      ::Pattern.match_cond_exp({{ exp }}, {{ pat.expressions.first }})

    {% elsif pat.is_a?(Var) %}
      true

    {% elsif pat.is_a?(Underscore) %}
      true

    {% elsif pat.is_a?(Assign) %}
      {% raise "LHS must be a Var" unless pat.target.is_a?(Var) %}
      ::Pattern.match_cond_exp({{ exp }}, {{ pat.value }})

    {% elsif pat.is_a?(Call) %}
      {% raise "named arguments are not supported" if pat.named_args %}
      {% raise "blocks are not supported" if pat.block || pat.block_arg %}
      {% if !pat.receiver && pat.name == "__pin" && pat.args.size == 1 %}
        {{ pat.args.first }} === {{ exp }}
      {% else %}
        {% raise "unknown call in pattern: #{pat.id}" %}
      {% end %}

    {% elsif pat.is_a?(Path) %}
      {{ pat }} === {{ exp }}

    {% elsif pat.is_a?(Generic) %}
      {{ pat }} === {{ exp }}

    {% elsif pat.is_a?(TupleLiteral) || pat.is_a?(ArrayLiteral) %}
      {% raise "of T is unsupported" if pat.is_a?(ArrayLiteral) && pat.of %}
      {% splat_indices = [] of NumberLiteral %}
      {% for elem, i in pat %}
        {% if elem.is_a?(Call) && !elem.receiver && elem.name == "__splat" && elem.args.size == 1 && !elem.named_args && !elem.block && !elem.block_arg %}
          {% splat_exp = elem.args.first %}
          {% raise "invalid splat argument" unless splat_exp.is_a?(Var) || splat_exp.is_a?(Underscore) %}
          {% splat_indices << i %}
        {% end %}
      {% end %}

      {% if splat_indices.empty? %}
        {{ exp }}.responds_to?(:size) &&
          {{ exp }}.responds_to?(:[]) &&
          {{ exp }}.size == {{ pat.size }} &&
          {% if pat.is_a?(ArrayLiteral) %}
            {{ exp }}.is_a?({% if pat.type %} {{ pat.type }} {% else %} ::Array {% end %}) &&
          {% end %}
          {% for elem, i in pat %}
            {% subexp = "#{exp}_#{i}".id %}
            ({{ subexp }} = {{ exp }}[{{ i }}]; ::Pattern.match_cond_exp({{ subexp }}, {{ elem }})) &&
          {% end %}
          true

      {% elsif splat_indices.size == 1 %}
        {% splat_index = splat_indices.first %}
        {{ exp }}.responds_to?(:size) &&
          {{ exp }}.responds_to?(:[]) &&
          {{ exp }}.size >= {{ pat.size - 1 }} &&
          {% if pat.is_a?(ArrayLiteral) %}
            {{ exp }}.is_a?({% if pat.type %} {{ pat.type }} {% else %} ::Array {% end %}) &&
          {% end %}
          {% for i in 0...splat_index %}
            {% subexp = "#{exp}_#{i}".id %}
            ({{ subexp }} = {{ exp }}[{{ i }}]; ::Pattern.match_cond_exp({{ subexp }}, {{ pat[i] }})) &&
          {% end %}
          {% for i in splat_index + 1...pat.size %}
            {% subexp = "#{exp}_#{i}".id %}
            ({{ subexp }} = {{ exp }}[{{ i }}]; ::Pattern.match_cond_exp({{ subexp }}, {{ pat[i] }})) &&
          {% end %}
          true

      {% elsif splat_indices.size == 2 %}
        {% splat_b = splat_indices[0] %}
        {% splat_e = splat_indices[1] %}
        {% index_var = "#{exp}_index".id %}
        {% raise "empty find pattern" if splat_e == splat_b + 1 %}

        {{ exp }}.responds_to?(:size) &&
          {{ exp }}.responds_to?(:[]) &&
          {{ exp }}.size >= {{ pat.size - 2 }} &&
          {% if pat.is_a?(ArrayLiteral) %}
            {{ exp }}.is_a?({% if pat.type %} {{ pat.type }} {% else %} ::Array {% end %}) &&
          {% end %}
          {% for i in 0...splat_b %}
            {% subexp = "#{exp}_#{i}".id %}
            ({{ subexp }} = {{ exp }}[{{ i }}]; ::Pattern.match_cond_exp({{ subexp }}, {{ pat[i] }})) &&
          {% end %}
          begin
            {{ index_var }} = {{ splat_b }}
            while true
              if {{ index_var }} > {{ exp }}.size - {{ pat.size - splat_b - 2 }}
                {{ index_var }} = nil
                break
              end

              break if
                {% for j in splat_b + 1..splat_e - 1 %}
                  {% subexp = "#{exp}_#{j}".id %}
                  ({{ subexp }} = {{ exp }}[{{ index_var }} + {{ j - splat_b - 1 }}]; ::Pattern.match_cond_exp({{ subexp }}, {{ pat[j] }})) &&
                {% end %}
                true

              {{ index_var }} += 1
            end
            {{ index_var }}
          end &&
          {% for i in splat_e + 1...pat.size %}
            {% subexp = "#{exp}_#{i}".id %}
            ({{ subexp }} = {{ exp }}[{{ i - pat.size }}]; ::Pattern.match_cond_exp({{ subexp }}, {{ pat[i] }})) &&
          {% end %}
          true

      {% else %}
        {% raise "at most 2 splats are allowed in tuple patterns" %}
      {% end %}

    {% elsif pat.is_a?(HashLiteral) || pat.is_a?(NamedTupleLiteral) %}
      {% raise "of T is unsupported" if pat.is_a?(HashLiteral) && (pat.of_key || pat.of_value) %}
      {{ exp }}.responds_to?(:has_key?) &&
        {{ exp }}.responds_to?(:[]) &&
        {% if pat.is_a?(NamedTupleLiteral) %}
          {{ exp }}.is_a?(::NamedTuple) &&
        {% elsif pat.type %}
          {{ exp }}.is_a?({{ pat.type }}) &&
        {% end %}
        {% for key, value, i in pat %}
          {% subexp = "#{exp}_#{i}".id %}
          {% if key.is_a?(Var) || key.is_a?(Underscore) %}
            {% raise "invalid key in hash pattern" %}
          {% end %}
          {% if key.is_a?(Call) && !key.receiver && key.name == "__double_splat" && key.args.empty? && !key.named_args && !key.block && !key.block_arg %}
            {% raise "BUG: double splat cannot appear here" unless i == pat.size - 1 %}
            {% if value.is_a?(NilLiteral) %}
              {{ exp }}.responds_to?(:all?) &&
                !({{ exp }}.responds_to?(:size) && {{ exp }}.size > {{ pat.size - 1 }}) &&
                begin
                  {% keys_var = "#{exp}_keys".id %}
                  {{ keys_var }} = ::Tuple.new({{ pat.keys[0..-2].splat }})
                  {{ exp }}.all? { |k, _| {{ keys_var }}.includes?(k) }
                end &&
            {% elsif value.is_a?(Var) %}
              {{ exp }}.responds_to?(:reject) &&
            {% else %}
              {% raise "invalid double splat argument" %}
            {% end %}

          {% else %}
            {% if key.is_a?(Call) && !key.receiver && key.name == "__pin" && key.args.size == 1 && !key.named_args && !key.block && !key.block_arg %}
              {{ exp }}.has_key?({{ key.args.first }}) &&
              ({{ subexp }} = {{ exp }}[{{ key.args.first }}]; ::Pattern.match_cond_exp({{ subexp }}, {{ value }})) &&
            {% elsif pat.is_a?(NamedTupleLiteral) %}
              {{ exp }}.has_key?({{ key.symbolize }}) &&
              ({{ subexp }} = {{ exp }}[{{ key.symbolize }}]; ::Pattern.match_cond_exp({{ subexp }}, {{ value }})) &&
            {% else %}
              {{ exp }}.has_key?({{ key }}) &&
              ({{ subexp }} = {{ exp }}[{{ key }}]; ::Pattern.match_cond_exp({{ subexp }}, {{ value }})) &&
            {% end %}

          {% end %}
        {% end %}
        true

    {% elsif pat.is_a?(NumberLiteral) || pat.is_a?(BoolLiteral) || pat.is_a?(CharLiteral) ||
             pat.is_a?(StringLiteral) || pat.is_a?(RangeLiteral) || pat.is_a?(RegexLiteral) ||
             pat.is_a?(SymbolLiteral) || pat.is_a?(ProcLiteral) || pat.is_a?(NilLiteral) %}
      {{ pat }} === {{ exp }}

    {% else %}
      {% raise "unknown pattern: #{pat.class_name}" %}
    {% end %}

    {% if false; puts "#{exp} ~>? #{pat}\n======="; debug; puts "======="; end %}
  end

  # :nodoc:
  macro match_value_exp(exp, pat)
    {% if pat.is_a?(Expressions) %}
      ::Pattern.match_value_exp({{ exp }}, {{ pat.expressions.first }})

    {% elsif pat.is_a?(Assign) %}
      ::Pattern.match_value_exp({{ exp }}, {{ pat.value }})

    {% elsif pat.is_a?(Path) || pat.is_a?(Generic) %}
      {{ exp }}.as({{ pat }})

    {% elsif pat.is_a?(ArrayLiteral) && pat.type %}
      {{ exp }}.as({{ pat.type }})

    {% elsif pat.is_a?(ArrayLiteral) %}
      {{ exp }}.as(::Array)

    {% elsif pat.is_a?(TupleLiteral) %}
      {{ exp }}.as(typeof(begin
        {% value_var = "#{exp}_val".id %}
        {{ value_var }} = {{ exp }}
        {{ value_var }}.responds_to?(:[]) &&
          {{ value_var }}.responds_to?(:size) ? {{ value_var }} : raise ""
      end))

    {% elsif pat.is_a?(NamedTupleLiteral) %}
      {{ exp }}.as(::NamedTuple)

    {% elsif pat.is_a?(HashLiteral) && pat.type %}
      {{ exp }}.as({{ pat.type }})

    {% elsif pat.is_a?(HashLiteral) %}
      {% last = pat.to_a.last %}
      {% key = last[0] %}
      {% has_double_splat = key.is_a?(Call) && !key.receiver && key.name == "__double_splat" && key.args.empty? && !key.named_args && !key.block && !key.block_arg %}
      {{ exp }}.as(typeof(begin
        {% value_var = "#{exp}_val".id %}
        {{ value_var }} = {{ exp }}
        {{ value_var }}.responds_to?(:[]) &&
          {{ value_var }}.responds_to?(:has_key?) &&
          {% if has_double_splat %}
            {% if last[1].is_a?(Var) %}
              {{ value_var }}.responds_to?(:reject) &&
            {% elsif last[1].is_a?(NilLiteral) %}
              {{ value_var }}.responds_to?(:all?) &&
            {% end %}
          {% end %}
          true ? {{ value_var }} : raise ""
      end))

    {% else %}
      {{ exp }}

    {% end %}
  end

  # :nodoc:
  macro match_bind_exp(exp, pat)
    {% if pat.is_a?(Expressions) %}
      ::Pattern.match_bind_exp({{ exp }}, {{ pat.expressions.first }})

    {% elsif pat.is_a?(Var) %}
      {{ pat.id }} = {{ exp }}

    {% elsif pat.is_a?(Assign) %}
      ::Pattern.match_bind_exp({{ exp }}, {{ pat.value }})
      {{ pat.target.id }} = ::Pattern.match_value_exp({{ exp }}, {{ pat.value }})

    {% elsif pat.is_a?(TupleLiteral) || pat.is_a?(ArrayLiteral) %}
      {% splat_indices = [] of NumberLiteral %}
      {% for elem, i in pat %}
        {% if elem.is_a?(Call) && !elem.receiver && elem.name == "__splat" && elem.args.size == 1 && !elem.named_args && !elem.block && !elem.block_arg %}
          {% splat_indices << i %}
        {% end %}
      {% end %}

      {% if splat_indices.empty? %}
        {% for elem, i in pat %}
          {% subexp = "#{exp}_#{i}".id %}
          ::Pattern.match_bind_exp({{ subexp }}, {{ elem }})
        {% end %}

      {% elsif splat_indices.size == 1 %}
        {% splat_index = splat_indices.first %}
        {% for i in 0...splat_index %}
          {% subexp = "#{exp}_#{i}".id %}
          ::Pattern.match_bind_exp({{ subexp }}, {{ pat[i] }})
        {% end %}
        {% splat_var = pat[splat_index].args.first %}
        {% unless splat_var.is_a?(Underscore) %}
          {{ splat_var }} = {{ exp }}[{{ splat_index }}..{{ splat_index - pat.size }}]
        {% end %}
        {% for i in splat_index + 1...pat.size %}
          {% subexp = "#{exp}_#{i}".id %}
          ::Pattern.match_bind_exp({{ subexp }}, {{ pat[i] }})
        {% end %}

      {% elsif splat_indices.size == 2 %}
        {% splat_b = splat_indices[0] %}
        {% splat_e = splat_indices[1] %}
        {% index_var = "#{exp}_index".id %}
        {% for i in 0...splat_b %}
          {% subexp = "#{exp}_#{i}".id %}
          ::Pattern.match_bind_exp({{ subexp }}, {{ pat[i] }})
        {% end %}
        {% splat_var = pat[splat_b].args.first %}
        {% unless splat_var.is_a?(Underscore) %}
          {{ splat_var }} = {{ exp }}[{{ splat_b }}...{{ index_var }}]
        {% end %}
        {% for i in splat_b + 1..splat_e - 1 %}
          {% subexp = "#{exp}_#{i}".id %}
          ::Pattern.match_bind_exp({{ subexp }}, {{ pat[i] }})
        {% end %}
        {% splat_var = pat[splat_e].args.first %}
        {% unless splat_var.is_a?(Underscore) %}
          {{ splat_var }} = {{ exp }}[{{ index_var }} + {{ splat_e - splat_b - 1 }}..{{ splat_e - pat.size }}]
        {% end %}
        {% for i in splat_e + 1...pat.size %}
          {% subexp = "#{exp}_#{i}".id %}
          ::Pattern.match_bind_exp({{ subexp }}, {{ pat[i] }})
        {% end %}

      {% end %}

    {% elsif pat.is_a?(HashLiteral) || pat.is_a?(NamedTupleLiteral) %}
      {% for key, value, i in pat %}
        {% if key.is_a?(Call) && !key.receiver && key.name == "__double_splat" && key.args.empty? && !key.named_args && !key.block && !key.block_arg %}
          {% if value.is_a?(Var) %}
            {{ value }} = {{ exp }}.reject({{ pat.keys[0..-2].splat }})
          {% end %}
        {% else %}
          {% subexp = "#{exp}_#{i}".id %}
          ::Pattern.match_bind_exp({{ subexp }}, {{ value }})
        {% end %}
      {% end %}

    {% end %}

    {% if false; puts "#{pat} <~ #{exp}\n======="; debug; puts "======="; end %}
  end

  # Attempts to match *exp* against the given pattern *pat*. Returns `true` if
  # matching succeeds, `false` if matching fails.
  #
  # Due to language limitations, using this macro in a condition does not fully
  # constrain the types of the bound variables in the pattern; use
  # `Pattern.try_match` instead.
  #
  # ```
  # a, b, c, d = nil, nil, nil, nil
  # if Pattern.matches?([1, [2, 3], 4], {a, {b, __splat(c)}, d})
  #   values = {a, b, c, d} # => {1, 2, [3], 4}
  #   typeof(values)        # => Tuple(Array(Int32) | Int32 | Nil, Int32 | Nil, Array(Int32) | Nil, Array(Int32) | Int32 | Nil)
  # end
  # ```
  #
  # The code below shall be equivalent to above:
  #
  # ```
  # if [1, [2, 3], 4] ~>? {a, {b, *c}, d}
  #   values = {a, b, c, d} # => {1, 2, [3], 4}
  #   typeof(values)        # => Tuple(Array(Int32) | Int32, Int32, Array(Int32), Array(Int32) | Int32)
  # else
  #   values = {a, b, c, d} # => {nil, nil, nil, nil}
  #   typeof(values)        # => Tuple(Nil, Nil, Nil, Nil)
  # end
  # ```
  macro matches?(exp, pat)
    %exp = {{ exp }}
    if ::Pattern.match_cond_exp(%exp, {{ pat }})
      ::Pattern.match_bind_exp(%exp, {{ pat }})
      true
    else
      false
    end
  end

  # Attempts to match *exp* against the given pattern *pat*. Invokes the block
  # body if matching succeeds. Returns `nil`.
  #
  # This method is for testing purposes only. Language support for pattern
  # matching should implement proper flow typing for successful matches.
  #
  # ```
  # a, b, c, d = nil, nil, nil, nil
  # Pattern.try_match([1, [2, 3], 4], {a, {b, __splat(c)}, d}) do
  #   values = {a, b, c, d} # => {1, 2, [3], 4}
  #   typeof(values)        # => Tuple(Array(Int32) | Int32, Int32, Array(Int32), Array(Int32) | Int32)
  # end
  # ```
  macro try_match(exp, pat, &block)
    %exp = {{ exp }}
    if ::Pattern.match_cond_exp(%exp, {{ pat }})
      ::Pattern.match_bind_exp(%exp, {{ pat }})
      {{ block.body }}
    end
    nil
  end

  # Matches *exp* against the given pattern *pat*. Raises
  # `Pattern::MatchFailedError` if matching fails.
  #
  # ```
  # a, b, c, d = nil, nil, nil, nil
  # Pattern.match!([1, [2, 3], 4], {a, {b, __splat(c)}, d})
  # values = {a, b, c, d} # => {1, 2, [3], 4}
  # typeof(values)        # => Tuple(Array(Int32) | Int32, Int32, Array(Int32), Array(Int32) | Int32)
  #
  # Pattern.match!([1, 2], {a, b, c}) # Pattern::MatchFailedError: matching against {a, b, c} failed
  # ```
  #
  # The code below shall be equivalent to above:
  #
  # ```
  # [1, [2, 3], 4] ~> {a, {b, *c}, d}
  # values = {a, b, c, d} # => {1, 2, [3], 4}
  # typeof(values)        # => Tuple(Array(Int32) | Int32, Int32, Array(Int32), Array(Int32) | Int32)
  # [1, 2] ~> {a, b, c}   # Pattern::MatchFailedError
  # ```
  macro match!(exp, pat)
    %exp = {{ exp }}
    if ::Pattern.match_cond_exp(%exp, {{ pat }})
      ::Pattern.match_bind_exp(%exp, {{ pat }})
      nil
    else
      ::raise ::Pattern::MatchFailedError.new("matching against #{ {{ pat.stringify }} } failed")
    end
  end
end
