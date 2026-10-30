// Only the `lakehouse` data source gets init SQL; the others keep their env-driven config.
// A driverFactory must return either driver instances or config objects for every source, never a mix.
const lakehouseInitSql = `
  CREATE SECRET rustfs (
    TYPE s3, KEY_ID '${process.env.S3_ACCESS_KEY}', SECRET '${process.env.S3_SECRET_KEY}',
    REGION '${process.env.S3_REGION}', ENDPOINT '${process.env.S3_ENDPOINT}', URL_STYLE 'path', USE_SSL false
  );
  ATTACH 'lakehouse' AS lakehouse (
    TYPE iceberg, ENDPOINT '${process.env.LAKEKEEPER_ENDPOINT}',
    AUTHORIZATION_TYPE 'none', ACCESS_DELEGATION_MODE 'none'
  );
`;

module.exports = {
  driverFactory: ({ dataSource }) => {
    if (dataSource === 'lakehouse') {
      return { type: 'duckdb', initSql: lakehouseInitSql };
    }
    const type = process.env[`CUBEJS_DS_${dataSource.toUpperCase()}_DB_TYPE`] || process.env.CUBEJS_DB_TYPE;
    return { type };
  },
};
