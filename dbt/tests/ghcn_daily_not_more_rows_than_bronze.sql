-- Dedup and the QC filter never add rows (SPEC §7.3). Singular instead of dbt_utils.fewer_rows_than:
-- that macro groups by a select alias, which Trino rejects (COLUMN_NOT_FOUND).
with silver_rows as (
    select count(*) as row_count from {{ ref('ghcn_daily') }}
),

bronze_rows as (
    select count(*) as row_count from {{ source('duckdb_bronze', 'ghcn_daily_raw') }}
)

select
    silver_rows.row_count as silver_row_count,
    bronze_rows.row_count as bronze_row_count
from silver_rows
cross join bronze_rows
where silver_rows.row_count > bronze_rows.row_count
