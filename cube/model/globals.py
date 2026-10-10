# Jinja globals for the YAML templates in cubes/ and views/.
# Every engine-specific SQL difference lives here, keyed by data source; the templates stay engine-agnostic.
import os

from cube import SafeString, TemplateContext

template = TemplateContext()

gold_namespace = os.environ.get("GOLD_NAMESPACE", "trino_gold")

# `default` is a placeholder that no cube uses (see compose/serving.yaml); every other declared
# data source gets its own cubes and view.
@template.function("data_sources")
def data_sources():
    names = []
    for name in os.environ["CUBEJS_DATASOURCES"].split(","):
        if name.strip() != "default":
            names.append(SafeString(name.strip()))
    return names


def unsupported(data_source):
    return ValueError(f"no SQL dialect defined for data source '{data_source}' in cube/model/globals.py")


@template.function("gold_table")
def gold_table(data_source, table):
    if data_source == "trino":
        return SafeString(f"lakehouse.{gold_namespace}.{table}")
    raise unsupported(data_source)


# Rollup-eligible measures are cast to a double so Cube Store stores Float, not Decimal(18,5)
# (.claude/rules/cube-models.md).
@template.function("to_double")
def to_double(data_source, expression):
    if data_source == "trino":
        return SafeString(f"CAST({expression} AS DOUBLE)")
    raise unsupported(data_source)


@template.function("percentile")
def percentile(data_source, expression, fraction):
    if data_source == "trino":
        return SafeString(f"approx_percentile({expression}, {fraction})")
    raise unsupported(data_source)
