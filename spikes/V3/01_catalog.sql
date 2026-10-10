-- External catalog over Lakekeeper. Static S3 keys, no vended credentials (the warehouse has sts/remote-signing off).
-- ${S3_*} are substituted by run.sh (envsubst).
DROP CATALOG IF EXISTS lakehouse;

CREATE EXTERNAL CATALOG lakehouse
PROPERTIES (
    "type" = "iceberg",
    "iceberg.catalog.type" = "rest",
    "iceberg.catalog.uri" = "http://lakekeeper:8181/catalog",
    "iceberg.catalog.warehouse" = "lakehouse",
    "iceberg.catalog.vended-credentials-enabled" = "false",
    "aws.s3.endpoint" = "http://rustfs:9000",
    "aws.s3.enable_path_style_access" = "true",
    "aws.s3.region" = "${S3_REGION}",
    "aws.s3.access_key" = "${S3_ACCESS_KEY}",
    "aws.s3.secret_key" = "${S3_SECRET_KEY}"
);

SHOW DATABASES FROM lakehouse;
SELECT count(*) FROM lakehouse.trino_gold.fct_weather_daily;
SELECT count(*) FROM lakehouse.trino_gold.dim_station;
SELECT count(*) FROM lakehouse.trino_gold.dim_date;
