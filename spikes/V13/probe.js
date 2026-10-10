// Probe run inside cubejs/cube:v1.7.50 on the default bridge network (NOT the compose network).
// Checks: bundled DuckDB version, iceberg/httpfs install via the driver, multi-statement initSql,
// ATTACH option parsing (ACCESS_DELEGATION_MODE) against an unreachable endpoint, threads/memory under cgroup limits.
const { DuckDBDriver } = require('/cube/node_modules/@cubejs-backend/duckdb-driver');

const initSql = process.env.PROBE_INIT_SQL || `
  CREATE SECRET rustfs (TYPE s3, KEY_ID 'k', SECRET 's', REGION 'us-east-1', ENDPOINT 'rustfs:9000', URL_STYLE 'path', USE_SSL false);
  ATTACH 'lakehouse' AS lakehouse (TYPE iceberg, ENDPOINT 'http://127.0.0.1:1/catalog', AUTHORIZATION_TYPE 'none', ACCESS_DELEGATION_MODE 'none');
`;

(async () => {
  const driver = new DuckDBDriver({ initSql });
  driver.logger = true;
  const show = async (sql) => console.log(sql, '=>', JSON.stringify(await driver.query(sql)));
  await show('SELECT version() AS v');
  await show("SELECT extension_name, extension_version, loaded FROM duckdb_extensions() WHERE extension_name IN ('iceberg','httpfs','avro')");
  await show('SELECT name FROM duckdb_secrets()');
  await show('SELECT database_name, type FROM duckdb_databases()');
  await show("SELECT current_setting('threads') AS threads, current_setting('memory_limit') AS memory_limit");
  await driver.release();
})().catch((e) => {
  console.error('FAILED', e);
  process.exit(1);
});
