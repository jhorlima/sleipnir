{#- Engine-specific SQL and table properties (SPEC §7.2). Add <adapter>__ variants for new engines. -#}

{% macro parse_yyyymmdd(column) -%}
    {{ return(adapter.dispatch('parse_yyyymmdd', 'sleipnir')(column)) }}
{%- endmacro %}

{% macro trino__parse_yyyymmdd(column) -%}
    cast(date_parse({{ column }}, '%Y%m%d') as date)
{%- endmacro %}

{#- Replaces dbt-spark's macro of the same name (a project macro wins). dbt-spark picks the Iceberg
    syntax from existing_relation.is_iceberg, which is unset for a table created earlier in the same run
    (the first microbatch run creates the table in batch 1), so batch 2 emitted the Hive
    `insert overwrite table ... partition (...)` form and failed. Every Spark table here is Iceberg. -#}
{% macro get_insert_overwrite_sql(source_relation, target_relation, existing_relation) %}
    {%- set dest_columns = adapter.get_columns_in_relation(target_relation) -%}
    {%- set dest_cols_csv = dest_columns | map(attribute='quoted') | join(', ') -%}
    insert overwrite {{ target_relation }}
    select {{ dest_cols_csv }} from {{ source_relation }}
{% endmacro %}

{#- dbt's default date_trunc is Spark's date_trunc(), which returns a TIMESTAMP; Trino returns a DATE.
    trunc() keeps the DATE type so both writers produce the same columns. -#}
{% macro spark__date_trunc(datepart, date) -%}
    trunc({{ date }}, '{{ {'month': 'MM', 'year': 'YYYY'}[datepart] }}')
{%- endmacro %}

{% macro spark__parse_yyyymmdd(column) -%}
    to_date({{ column }}, 'yyyyMMdd')
{%- endmacro %}


{% macro postgres__parse_yyyymmdd(column) -%}
    to_date({{ column }}, 'YYYYMMDD')
{%- endmacro %}

{#- dbt's default date_trunc returns a TIMESTAMP on Postgres; Trino returns a DATE. -#}
{% macro postgres__date_trunc(datepart, date) -%}
    cast(date_trunc('{{ datepart }}', {{ date }}) as date)
{%- endmacro %}


{#- Returns model config entries; used as {{ config(**partitioned_by_month('date')) }}.
    sort_columns (fct_weather_daily, SPEC §14 D-15) adds the table's sort order. It is an argument, not a
    second macro, because two config() calls replace each other's `properties`. -#}
{% macro partitioned_by_month(column, sort_columns=[]) -%}
    {{ return(adapter.dispatch('partitioned_by_month', 'sleipnir')(column, sort_columns)) }}
{%- endmacro %}

{% macro trino__partitioned_by_month(column, sort_columns) -%}
    {%- set properties = {'partitioning': "ARRAY['month(" ~ column ~ ")']"} -%}
    {%- if sort_columns -%}
        {%- do properties.update({'sorted_by': "ARRAY['" ~ sort_columns | join("', '") ~ "']"}) -%}
    {%- endif -%}
    {{ return({'properties': properties}) }}
{%- endmacro %}

{#- Iceberg `months(col)` transform. Hash distribution makes each writer task receive whole partitions,
    so a partitioned write does not leave one small file per task per month.
    A sort order can only be set on an existing table, and dbt runs a model's post-hooks once per microbatch
    run, so a build writes its batches unsorted; maintain_table then rewrites the table with the sort order.
    Writes after the hook has run are sorted. -#}
{% macro spark__partitioned_by_month(column, sort_columns) -%}
    {%- set entries = {
        'partition_by': ['months(' ~ column ~ ')'],
        'tblproperties': {'write.distribution-mode': 'hash'},
    } -%}
    {%- if sort_columns -%}
        {%- do entries.update({'post_hook': "alter table {{ this }} write ordered by " ~ sort_columns | join(', ')}) -%}
    {%- endif -%}
    {{ return(entries) }}
{%- endmacro %}

{#- No partitioning on Postgres: the `small` scale is ~44 M rows, and dbt-postgres has no declarative
    partitioning config; an unpartitioned heap is the plain baseline. `config()` rejects an empty call,
    so the entry is Postgres' own default (a regular, logged table). -#}
{% macro postgres__partitioned_by_month(column, sort_columns) -%}
    {{ return({'unlogged': false}) }}
{%- endmacro %}


{#- 8-byte floating point: `double` on Trino and Spark, `double precision` on Postgres.
    dbt's own type_float() is not used because some adapters map it to a 4-byte float. -#}
{% macro type_double() -%}
    {{ return(adapter.dispatch('type_double', 'sleipnir')()) }}
{%- endmacro %}

{% macro default__type_double() -%}
    double
{%- endmacro %}

{% macro postgres__type_double() -%}
    double precision
{%- endmacro %}
