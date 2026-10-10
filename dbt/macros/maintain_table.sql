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


{#- Retention vars use the Trino notation ('0s', '7d'); Iceberg procedures take a timestamp. -#}
{% macro spark_retention_cutoff(retention, minimum_seconds=0) -%}
    {%- set seconds_per_unit = {'s': 1, 'm': 60, 'h': 3600, 'd': 86400} -%}
    {%- set seconds = [(retention[:-1] | int) * seconds_per_unit[retention[-1]], minimum_seconds] | max -%}
    {%- set cutoff = modules.datetime.datetime.utcnow() - modules.datetime.timedelta(seconds=seconds) -%}
    {{ return(cutoff.strftime('%Y-%m-%d %H:%M:%S')) }}
{%- endmacro %}


{% macro spark__maintain_table(relation) -%}
    {%- set procedures = 'lakehouse.system' -%}
    {%- set bytes_per_unit = {'KB': 1024, 'MB': 1048576, 'GB': 1073741824} -%}
    {%- set threshold = var('optimize_file_size_threshold') -%}
    {%- set threshold_bytes = (threshold[:-2] | int) * bytes_per_unit[threshold[-2:]] -%}
    {%- set snapshot_cutoff = spark_retention_cutoff(var('snapshot_retention')) -%}
    {#- The procedure refuses an orphan retention under 24 h and has no override in SQL (Trino's session
        property is what allows 0s there), so Spark uses 25 h at the least. -#}
    {%- set orphan_cutoff = spark_retention_cutoff(var('orphan_file_retention'), 25 * 3600) -%}
    {#- prefix_listing lists the files through S3FileIO; the default lists through Hadoop's s3 filesystem, which is not installed. -#}
    {#- rewrite_data_files only touches files below min-file-size-bytes, like Trino's file_size_threshold. -#}
    {%- set statements = [
        "call " ~ procedures ~ ".rewrite_data_files(table => '" ~ relation ~ "', options => map('min-file-size-bytes', '" ~ threshold_bytes ~ "'))",
        "call " ~ procedures ~ ".rewrite_manifests(table => '" ~ relation ~ "')",
        "call " ~ procedures ~ ".expire_snapshots(table => '" ~ relation ~ "', older_than => TIMESTAMP '" ~ snapshot_cutoff ~ "', retain_last => 1)",
        "call " ~ procedures ~ ".remove_orphan_files(table => '" ~ relation ~ "', older_than => TIMESTAMP '" ~ orphan_cutoff ~ "', prefix_listing => true)",
    ] -%}
    {%- for statement in statements -%}
        {%- set started_at = modules.datetime.datetime.now() -%}
        {%- do run_query(statement) -%}
        {%- set seconds = (modules.datetime.datetime.now() - started_at).total_seconds() -%}
        {%- do log("maintain_table " ~ relation ~ ": " ~ statement.split('.system.')[-1].split('(')[0] ~ " in " ~ '%.1f' | format(seconds) ~ " s", info=true) -%}
    {%- endfor -%}
{%- endmacro %}
