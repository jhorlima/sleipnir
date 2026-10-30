{#- Whole-table natural-key uniqueness, one year per query, so each query fits the engine's
    memory (SPEC §7.3). Not a dbt test: run it after a backfill, outside the measured steps:
      dbt run-operation assert_unique_by_year --args '{relation: trino_silver.ghcn_daily, key_columns: [station_id, date, element]}'
    The key must contain the date column, so duplicates can only collide within one year. -#}
{% macro assert_unique_by_year(relation, key_columns, date_column='date') -%}
    {%- set key_list = key_columns | join(', ') -%}
    {%- set bounds_query -%}
        select min(extract(year from {{ date_column }})), max(extract(year from {{ date_column }})) from {{ relation }}
    {%- endset -%}
    {%- set bounds = run_query(bounds_query).rows[0] -%}
    {%- set first_year = bounds[0] | int -%}
    {%- set last_year = bounds[1] | int -%}

    {%- set years_with_duplicates = [] -%}
    {%- for year in range(first_year, last_year + 1) -%}
        {%- set duplicates_query -%}
            select count(*) from (
                select {{ key_list }}
                from {{ relation }}
                where {{ date_column }} >= date '{{ year }}-01-01'
                    and {{ date_column }} < date '{{ year + 1 }}-01-01'
                group by {{ key_list }}
                having count(*) > 1
            ) as duplicated_keys
        {%- endset -%}
        {%- set duplicate_keys = run_query(duplicates_query).columns[0].values()[0] | int -%}
        {%- do log(relation ~ " " ~ year ~ ": " ~ duplicate_keys ~ " duplicated keys", info=true) -%}
        {%- if duplicate_keys > 0 -%}
            {%- do years_with_duplicates.append(year) -%}
        {%- endif -%}
    {%- endfor -%}

    {%- if years_with_duplicates -%}
        {{ exceptions.raise_compiler_error(relation ~ " has duplicated keys in " ~ years_with_duplicates | join(', ')) }}
    {%- endif -%}
{%- endmacro %}
