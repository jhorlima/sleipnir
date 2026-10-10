{#- Incremental strategy and window shared by every incremental model (SPEC §7.1). -#}

{#- merge upserts on the natural key; delete+insert replaces whole dates (or months) of the window,
    which also removes rows that a newer revision moved out (e.g. a q_flag set later);
    microbatch ignores unique_key. -#}
{% macro incremental_unique_key(natural_key, window_key) -%}
    {%- set strategy = var('incremental_strategy') -%}
    {%- if strategy == 'merge' -%}
        {{ return(natural_key) }}
    {%- elif strategy == 'delete+insert' -%}
        {{ return(window_key) }}
    {%- elif strategy == 'microbatch' -%}
        {{ return(none) }}
    {%- else -%}
        {{ exceptions.raise_compiler_error("Unsupported incremental_strategy: " ~ strategy) }}
    {%- endif -%}
{%- endmacro %}


{#- First date to (re)process, or none for a full build.
    Window: dates in the bronze batches newer than the latest batch in this table, minus the
    batch overlap. With nothing new it returns a far-future date, so the run processes no rows.
    Computed at run time (not in SQL) so engines prune files on a literal predicate. -#}
{% macro incremental_start_date() -%}
    {%- if not execute or not is_incremental() or var('incremental_strategy') == 'microbatch' -%}
        {{ return(none) }}
    {%- endif -%}
    {%- set last_batch_query -%}
        select coalesce(max(_batch_id), 0) from {{ this }}
    {%- endset -%}
    {%- set last_batch_id = run_query(last_batch_query).columns[0].values()[0] -%}
    {%- set first_new_date_query -%}
        select min(date) from {{ source('duckdb_bronze', 'ghcn_daily_raw') }} where _batch_id > {{ last_batch_id }}
    {%- endset -%}
    {%- set first_new_date = run_query(first_new_date_query).columns[0].values()[0] -%}
    {%- if first_new_date is none -%}
        {{ return(modules.datetime.date(9999, 12, 31)) }}
    {%- endif -%}
    {%- set first_date = modules.datetime.datetime.strptime(first_new_date, '%Y%m%d').date() -%}
    {{ return(first_date - modules.datetime.timedelta(days=var('overlap_days'))) }}
{%- endmacro %}
