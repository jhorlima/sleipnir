"""Configuration shared by the download and load steps, read from the environment."""

import os
from pathlib import Path

GHCN_BASE_URL = "https://www.ncei.noaa.gov/pub/data/ghcn/daily"
LANDING_DIR = Path(os.environ.get("LANDING_DIR", "/landing"))
BATCHES_DIR = LANDING_DIR / "batches"


def ghcn_years():
    years = []
    for token in os.environ.get("GHCN_YEARS", "2025").split():
        years.append(int(token))
    return sorted(years)


def year_file_name(year):
    return f"{year}.csv.gz"
