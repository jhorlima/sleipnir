"""Compare /tmp/v9/acc/<q>.json with /tmp/v9/base/<q>.json: same rows (keyed by the non-numeric columns), numbers within 5 % (benchmark-integrity 5)."""
import json
import sys

TOLERANCE = 0.05


def load_rows(path):
    with open(path) as handle:
        return json.load(handle)["data"]


def split_row(row):
    key_parts = []
    numbers = {}
    for column, value in row.items():
        if column.endswith("count") or column.endswith("_prcp") or "avg_" in column or "median" in column or "p95" in column or "share" in column or "delta" in column or "prior" in column:
            numbers[column] = None if value is None else float(value)
        else:
            key_parts.append((column, value))
    return tuple(key_parts), numbers


def compare(name):
    accelerated = {}
    for row in load_rows(f"/tmp/v9/acc/{name}.json"):
        key, numbers = split_row(row)
        accelerated[key] = numbers
    baseline = {}
    for row in load_rows(f"/tmp/v9/base/{name}.json"):
        key, numbers = split_row(row)
        baseline[key] = numbers

    if set(accelerated) != set(baseline):
        only_acc = list(set(accelerated) - set(baseline))[:3]
        only_base = list(set(baseline) - set(accelerated))[:3]
        print(f"{name}: KEYS DIFFER acc={len(accelerated)} base={len(baseline)} only_acc={only_acc} only_base={only_base}")
        return

    worst = 0.0
    for key, base_numbers in baseline.items():
        for column, base_value in base_numbers.items():
            acc_value = accelerated[key][column]
            if base_value is None or acc_value is None:
                if base_value != acc_value:
                    worst = float("inf")
                continue
            denominator = max(abs(base_value), 1e-12)
            worst = max(worst, abs(acc_value - base_value) / denominator)
    verdict = "EQUAL" if worst <= TOLERANCE else "DIFFERENT"
    print(f"{name}: {verdict} rows={len(baseline)} worst_relative_diff={worst:.3g}")


for query_name in sys.argv[1:]:
    compare(query_name)
