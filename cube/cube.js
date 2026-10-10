// Env cannot carry init SQL, and DuckDB needs a secret + ATTACH to read Iceberg through Lakekeeper.
// A driverFactory must return configs (or drivers) for every data source, never a mix.
const duckdbInitSql = `
  SET threads = ${process.env.CUBE_DUCKDB_THREADS};
  CREATE SECRET rustfs (
    TYPE s3, KEY_ID '${process.env.S3_ACCESS_KEY}', SECRET '${process.env.S3_SECRET_KEY}',
    REGION '${process.env.S3_REGION}', ENDPOINT '${process.env.S3_ENDPOINT}', URL_STYLE 'path', USE_SSL false
  );
  ATTACH '${process.env.LAKEKEEPER_WAREHOUSE}' AS lakehouse (
    TYPE iceberg, ENDPOINT '${process.env.LAKEKEEPER_ENDPOINT}',
    AUTHORIZATION_TYPE 'none', ACCESS_DELEGATION_MODE 'none'
  );
`;

module.exports = {
  driverFactory: ({ dataSource }) => {
    if (dataSource === 'duckdb') {
      return { type: 'duckdb', initSql: duckdbInitSql };
    }
    const type = process.env[`CUBEJS_DS_${dataSource.toUpperCase()}_DB_TYPE`] || process.env.CUBEJS_DB_TYPE;
    return { type };
  },
};
