{#- Incremental strategy and window shared by every incremental model (SPEC §7.1). -#}

{#- merge upserts on the natural key; delete+insert replaces whole dates (or months) of the window,
    which also removes rows that a newer revision moved out (e.g. a q_flag set later);
    insert_overwrite and microbatch ignore unique_key (they replace whole partitions). -#}
{% macro incremental_unique_key(natural_key, window_key) -%}
    {%- set strategy = var('incremental_strategy') -%}
    {%- if strategy == 'merge' -%}
        {{ return(natural_key) }}
    {%- elif strategy == 'delete+insert' -%}
        {{ return(window_key) }}
    {%- elif strategy == 'microbatch' and target.type == 'postgres' -%}
        {#- dbt-postgres runs each batch as a merge on unique_key and refuses microbatch without one. -#}
        {{ return(natural_key) }}
    {%- elif strategy in ['insert_overwrite', 'microbatch'] -%}
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
    {#- reprocess_from_batch (B2 incremental scenarios): take the window from the bronze batches >= that
        batch, whether or not the table already has them. -#}
    {%- set reprocess_from_batch = var('reprocess_from_batch', none) -%}
    {%- if reprocess_from_batch is none -%}
        {%- set last_batch_query -%}
            select coalesce(max(_batch_id), 0) from {{ this }}
        {%- endset -%}
        {%- set first_batch_id = run_query(last_batch_query).columns[0].values()[0] + 1 -%}
    {%- else -%}
        {%- set first_batch_id = reprocess_from_batch -%}
    {%- endif -%}
    {%- set first_new_date_query -%}
        select min(date) from {{ source('duckdb_bronze', 'ghcn_daily_raw') }} where _batch_id >= {{ first_batch_id }}
    {%- endset -%}
    {%- set first_new_date = run_query(first_new_date_query).columns[0].values()[0] -%}
    {%- if first_new_date is none -%}
        {{ return(modules.datetime.date(9999, 12, 31)) }}
    {%- endif -%}
    {%- set first_date = modules.datetime.datetime.strptime(first_new_date, '%Y%m%d').date() -%}
    {%- set window_start = first_date - modules.datetime.timedelta(days=var('overlap_days')) -%}
    {#- insert_overwrite replaces whole monthly partitions, so a window starting mid-month would drop the rest of it. -#}
    {%- if var('incremental_strategy') == 'insert_overwrite' -%}
        {{ return(window_start.replace(day=1)) }}
    {%- endif -%}
    {{ return(window_start) }}
{%- endmacro %}
