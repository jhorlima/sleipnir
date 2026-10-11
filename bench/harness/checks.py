"""Pure logic of the read suites: result comparison (benchmark-integrity §5), the run protocol (SPEC §10.6)
and the B5 gates. Self-check: `uv run python checks.py`."""

import math
import sys
from datetime import date, datetime
from decimal import ROUND_HALF_UP, Decimal

from results import REPO_ROOT

# One checksum for every suite: the TPC-H check script owns it (order-insensitive md5 sum, numbers to 2 decimals).
sys.path.insert(0, str(REPO_ROOT / "bench" / "queries" / "tpch"))
from check import checksum, normalize  # noqa: E402

WARM_RUNS = 5
APPROX_TOLERANCE = 0.05
CUBE_MIDNIGHT_SUFFIX = "T00:00:00.000"


def stabilize_number(text):
    """Decimal-looking text rounded to 2 decimals, half up, after cutting float noise at 9 decimals.
    Two engines summing doubles in another order differ in the last bits (21.975 vs 21.974999999999998),
    which would flip a plain 2-decimal rounding."""
    if "." not in text:
        return text
    try:
        number = float(text)
    except ValueError:
        return text
    if not math.isfinite(number):
        return text
    exact = Decimal(repr(round(number, 9)))
    return str(exact.quantize(Decimal("0.01"), rounding=ROUND_HALF_UP))


def cell_text(value):
    """One result cell as text, the same way for every engine and for Cube's JSON."""
    return stabilize_number(_raw_cell_text(value))


def _raw_cell_text(value):
    if value is None:
        return ""
    if isinstance(value, datetime) and value.time().isoformat() == "00:00:00":
        return value.date().isoformat()
    if isinstance(value, date):
        return value.isoformat()
    text = str(value)
    if text.endswith(CUBE_MIDNIGHT_SUFFIX):
        return text[: -len(CUBE_MIDNIGHT_SUFFIX)]
    return text


def rows_to_text(rows):
    text_rows = []
    for row in rows:
        text_rows.append([cell_text(value) for value in row])
    return text_rows


def compare_results(rows, reference_rows, approx_measure_columns=0):
    """(matches, note). Exact: row count + checksum. With approx_measure_columns=n the last n columns are
    approximate measures and match within APPROX_TOLERANCE, rows paired by the columns before them."""
    if len(rows) != len(reference_rows):
        return False, f"row count {len(rows)} != reference {len(reference_rows)}"
    if approx_measure_columns == 0:
        if checksum(rows) == checksum(reference_rows):
            return True, ""
        return False, "checksum differs from the DuckDB reference"
    return _compare_approx(rows, reference_rows, approx_measure_columns)


def _compare_approx(rows, reference_rows, measure_count):
    reference_by_key = {}
    for row in reference_rows:
        key = tuple(normalize(cell) for cell in row[:-measure_count])
        reference_by_key[key] = row[-measure_count:]
    for row in rows:
        key = tuple(normalize(cell) for cell in row[:-measure_count])
        if key not in reference_by_key:
            return False, f"row {key} not in the reference"
        for value, expected in zip(row[-measure_count:], reference_by_key[key]):
            if not _within_tolerance(value, expected):
                return False, f"row {key}: {value} vs {expected} is off by more than {APPROX_TOLERANCE:.0%}"
    return True, f"approximate measures within {APPROX_TOLERANCE:.0%} relative tolerance"


def _within_tolerance(value, expected):
    if value == "" or expected == "":
        return value == expected
    value_number = float(value)
    expected_number = float(expected)
    largest = max(abs(value_number), abs(expected_number))
    return abs(value_number - expected_number) <= APPROX_TOLERANCE * largest


def protocol_plan(warm_runs=WARM_RUNS):
    """(run_type, repetition) in execution order: 1 cold, 1 discarded warm-up, `warm_runs` measured warm runs."""
    plan = [("cold", 1), ("warmup", 1)]
    for repetition in range(1, warm_runs + 1):
        plan.append(("warm", repetition))
    return plan


def explain_uses_mvs(explain_text, tables):
    """B5a gate: every table the query reads must show up as its MV (`mv_<table>`) and not as the base table."""
    missing = []
    for table in tables:
        if f"mv_{table}" not in explain_text:
            missing.append(table)
    if missing:
        return False, f"EXPLAIN does not scan the MV of: {', '.join(missing)}"
    return True, ""


def explain_reads_base_tables(explain_text, tables):
    """Tables still scanned directly: a line naming the table without the mv_ prefix."""
    base_reads = []
    for table in tables:
        for line in explain_text.splitlines():
            if table in line and f"mv_{table}" not in line and "TABLE" in line.upper():
                base_reads.append(table)
                break
    return base_reads


def pre_aggregations_gate(response):
    """B5c gate on a Cube /load response: usedPreAggregations must name at least one rollup."""
    used = response.get("usedPreAggregations") or {}
    if not used:
        return False, "usedPreAggregations is empty: the query did not use a pre-aggregation"
    return True, f"usedPreAggregations={sorted(used)}"


def _self_check():
    assert cell_text(None) == ""
    assert cell_text(date(2025, 1, 1)) == "2025-01-01"
    assert cell_text(datetime(2025, 1, 1)) == "2025-01-01"
    assert cell_text("2025-03-01T00:00:00.000") == "2025-03-01"
    assert cell_text("2025-03-01T10:00:00.000") == "2025-03-01T10:00:00.000"

    assert cell_text(21.974999999999998) == cell_text("21.975") == "21.98"
    assert cell_text("29.884999999999998") == cell_text(29.885) == "29.89"
    assert cell_text("USW00094728") == "USW00094728" and cell_text(5) == "5"

    reference = rows_to_text([("PT", date(2025, 1, 1), 12.3449), ("ES", date(2025, 1, 1), None)])
    shuffled = rows_to_text([("ES", "2025-01-01T00:00:00.000", None), ("PT", "2025-01-01T00:00:00.000", "12.3401")])
    assert compare_results(shuffled, reference)[0]
    different = rows_to_text([("ES", "2025-01-01", None), ("PT", "2025-01-01", "12.40")])
    assert not compare_results(different, reference)[0]
    assert not compare_results(shuffled[:1], reference)[0]

    approx_reference = [["PT", "10.0"], ["ES", "20.0"]]
    assert compare_results([["ES", "20.9"], ["PT", "9.6"]], approx_reference, approx_measure_columns=1)[0]
    assert not compare_results([["ES", "21.5"], ["PT", "10.0"]], approx_reference, approx_measure_columns=1)[0]
    assert not compare_results([["XX", "20.0"], ["PT", "10.0"]], approx_reference, approx_measure_columns=1)[0]

    plan = protocol_plan()
    assert plan[0] == ("cold", 1) and plan[1] == ("warmup", 1)
    assert [run_type for run_type, _ in plan].count("cold") == 1
    assert [run_type for run_type, _ in plan].count("warmup") == 1
    assert [run_type for run_type, _ in plan].count("warm") == 5
    assert len(protocol_plan(warm_runs=2)) == 4

    mv_plan = "  0:OlapScanNode\n     TABLE: mv_fct_weather_daily\n  1:OlapScanNode\n     TABLE: mv_dim_station"
    assert explain_uses_mvs(mv_plan, ["fct_weather_daily", "dim_station"])[0]
    assert not explain_uses_mvs(mv_plan, ["fct_weather_daily", "dim_date"])[0]
    base_plan = "  0:IcebergScanNode\n     TABLE: fct_weather_daily"
    assert not explain_uses_mvs(base_plan, ["fct_weather_daily"])[0]
    assert explain_reads_base_tables(base_plan, ["fct_weather_daily"]) == ["fct_weather_daily"]
    assert explain_reads_base_tables(mv_plan, ["fct_weather_daily", "dim_station"]) == []

    assert not pre_aggregations_gate({"data": [], "usedPreAggregations": {}})[0]
    assert not pre_aggregations_gate({"data": []})[0]
    assert pre_aggregations_gate({"usedPreAggregations": {"prod.trino_weather_daily_monthly": {}}})[0]
    print("checks ok")


if __name__ == "__main__":
    _self_check()
