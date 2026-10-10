{#- Engine-specific SQL and table properties (SPEC §7.2). Add <adapter>__ variants for new engines. -#}

{% macro parse_yyyymmdd(column) -%}
    {{ return(adapter.dispatch('parse_yyyymmdd', 'sleipnir')(column)) }}
{%- endmacro %}

{% macro trino__parse_yyyymmdd(column) -%}
    cast(date_parse({{ column }}, '%Y%m%d') as date)
{%- endmacro %}


{#- Returns model config entries; used as {{ config(**partitioned_by_month('date')) }}. -#}
{% macro partitioned_by_month(column) -%}
    {{ return(adapter.dispatch('partitioned_by_month', 'sleipnir')(column)) }}
{%- endmacro %}

{% macro trino__partitioned_by_month(column) -%}
    {{ return({'properties': {'partitioning': "ARRAY['month(" ~ column ~ ")']"}}) }}
{%- endmacro %}
