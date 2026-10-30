{#- Namespace <target>_<layer> (SPEC §3.1, §7.2); SCHEMA_SUFFIX=_small builds the small scale
    next to the r2 tables (Postgres is small-only and keeps its names); experiment runs with RUN_ID go to bench_<run_id>_<layer>.
    The layer is the first folder under models/; a model outside a layer folder fails compilation. -#}
{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- if node.resource_type != 'model' -%}
        {{ target.schema }}
    {%- else -%}
        {%- set layers = ['silver', 'gold'] -%}
        {%- set layer = node.fqn[1] if node.fqn | length > 2 else none -%}
        {%- if layer not in layers -%}
            {{ exceptions.raise_compiler_error("Model " ~ node.name ~ " must live under models/<layer>/ with layer in " ~ layers) }}
        {%- endif -%}
        {%- set run_id = env_var('RUN_ID', '') -%}
        {%- if run_id -%}
            bench_{{ run_id }}_{{ layer }}
        {%- else -%}
            {{ target.name }}_{{ layer }}{{ '' if target.name == 'postgres' else env_var('SCHEMA_SUFFIX', '') }}
        {%- endif -%}
    {%- endif -%}
{%- endmacro %}
