ARG SPARK_VERSION
FROM apache/spark:${SPARK_VERSION}

ARG ICEBERG_VERSION
ARG MAVEN=https://repo1.maven.org/maven2/org/apache/iceberg

# Jars are baked in so a measured run never downloads anything (no spark.jars.packages).
ADD ${MAVEN}/iceberg-spark-runtime-4.1_2.13/${ICEBERG_VERSION}/iceberg-spark-runtime-4.1_2.13-${ICEBERG_VERSION}.jar /opt/spark/jars/
ADD ${MAVEN}/iceberg-aws-bundle/${ICEBERG_VERSION}/iceberg-aws-bundle-${ICEBERG_VERSION}.jar /opt/spark/jars/

USER root
RUN chmod 644 /opt/spark/jars/iceberg-*.jar
USER spark
