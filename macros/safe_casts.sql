{% macro safe_int64(expression) -%}
    {%- set cleaned = "regexp_replace(btrim((" ~ expression ~ ")::text), ',', '', 'g')" -%}
    case
        when {{ expression }} is null then null
        when lower({{ cleaned }}) in ('', 'null', 'none', 'nan', 'n/a', 'na', 'unknown', 'undefined') then null
        when {{ cleaned }} ~ '^[+-]?[0-9]+(\\.0+)?$' then {{ cleaned }}::numeric::bigint
        else null
    end
{%- endmacro %}

{% macro safe_float64(expression) -%}
    {%- set cleaned = "regexp_replace(btrim((" ~ expression ~ ")::text), ',', '', 'g')" -%}
    case
        when {{ expression }} is null then null
        when lower({{ cleaned }}) in ('', 'null', 'none', 'nan', 'n/a', 'na', 'unknown', 'undefined') then null
        when {{ cleaned }} ~ '^[+-]?([0-9]+(\\.[0-9]*)?|\\.[0-9]+)([eE][+-]?[0-9]+)?$'
            then {{ cleaned }}::double precision
        else null
    end
{%- endmacro %}

{% macro safe_boolean(expression) -%}
    case
        when {{ expression }} is null then null
        when lower(btrim(({{ expression }})::text)) in ('true', 't', '1', 'yes', 'y') then true
        when lower(btrim(({{ expression }})::text)) in ('false', 'f', '0', 'no', 'n') then false
        else null
    end
{%- endmacro %}

{% macro safe_timestamp(expression) -%}
    {%- set cleaned = "btrim((" ~ expression ~ ")::text)" -%}
    case
        when {{ expression }} is null then null
        when lower({{ cleaned }}) in ('', 'null', 'none', 'nan', 'n/a', 'na', 'unknown', 'undefined') then null
        when {{ cleaned }} ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}([ T][0-9]{2}:[0-9]{2}:[0-9]{2}(\\.[0-9]+)?(Z|[+-][0-9]{2}:?[0-9]{2})?)?$'
            then {{ cleaned }}::timestamptz
        when {{ cleaned }} ~ '^[0-9]{10}$'
            then to_timestamp({{ cleaned }}::double precision)
        when {{ cleaned }} ~ '^[0-9]{13}$'
            then to_timestamp({{ cleaned }}::double precision / 1000.0)
        else null
    end
{%- endmacro %}
