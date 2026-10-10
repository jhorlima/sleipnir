{#- Table maintenance (SPEC §7.2, §10.4). Post-hook of incremental models while var('maintenance')
    is true; measured runs pass maintenance: false and call it on its own:
      dbt run-operation maintain_table --args '{relation: trino_silver.ghcn_daily}' -#}
{% macro maintain_table(relation) -%}
    {%- if execute -%}
        {%- do adapter.dispatch('maintain_table', 'sleipnir')(relation) -%}
    {%- endif -%}
    {{ return('') }}
{%- endmacro %}


{% macro trino__maintain_table(relation) -%}
    {%- set catalog = target.database -%}
    {#- Trino refuses retentions below these session minimums (7d by default). -#}
    {%- set statements = [
        "set session " ~ catalog ~ ".expire_snapshots_min_retention = '" ~ var('snapshot_retention') ~ "'",
        "set session " ~ catalog ~ ".remove_orphan_files_min_retention = '" ~ var('orphan_file_retention') ~ "'",
        "alter table " ~ relation ~ " execute optimize(file_size_threshold => '" ~ var('optimize_file_size_threshold') ~ "')",
        "alter table " ~ relation ~ " execute optimize_manifests",
        "alter table " ~ relation ~ " execute expire_snapshots(retention_threshold => '" ~ var('snapshot_retention') ~ "')",
        "alter table " ~ relation ~ " execute remove_orphan_files(retention_threshold => '" ~ var('orphan_file_retention') ~ "')",
    ] -%}
    {%- for statement in statements -%}
        {%- set started_at = modules.datetime.datetime.now() -%}
        {%- do run_query(statement) -%}
        {%- set seconds = (modules.datetime.datetime.now() - started_at).total_seconds() -%}
        {%- do log("maintain_table " ~ relation ~ ": " ~ statement.split(' execute ')[-1] ~ " in " ~ '%.1f' | format(seconds) ~ " s", info=true) -%}
    {%- endfor -%}
{%- endmacro %}
