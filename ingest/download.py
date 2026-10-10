"""Download the GHCN-Daily files into the landing directory.

Idempotent: a file already present with the server's Content-Length is skipped.
"""

import os
import shutil
import sys
import urllib.request

from settings import GHCN_BASE_URL, LANDING_DIR, ghcn_years, year_file_name

REFERENCE_FILES = ["ghcnd-stations.txt", "ghcnd-countries.txt"]


def remote_size(url):
    request = urllib.request.Request(url, method="HEAD")
    with urllib.request.urlopen(request, timeout=60) as response:
        return int(response.headers["Content-Length"])


def download(url, target):
    partial = target.with_name(target.name + ".part")
    with urllib.request.urlopen(url, timeout=60) as response:
        with open(partial, "wb") as output:
            shutil.copyfileobj(response, output, length=1024 * 1024)
    os.replace(partial, target)


def wanted_files():
    files = []
    for year in ghcn_years():
        name = year_file_name(year)
        files.append((f"{GHCN_BASE_URL}/by_year/{name}", LANDING_DIR / name))
    for name in REFERENCE_FILES:
        files.append((f"{GHCN_BASE_URL}/{name}", LANDING_DIR / name))
    return files


def main():
    LANDING_DIR.mkdir(parents=True, exist_ok=True)
    files = wanted_files()

    # HEAD everything first so a wrong year fails before any large download starts.
    sizes = {}
    for url, _ in files:
        sizes[url] = remote_size(url)

    for url, target in files:
        expected = sizes[url]
        if target.exists() and target.stat().st_size == expected:
            print(f"skip {target.name} ({expected} bytes, already present)")
            continue
        print(f"download {url} ({expected} bytes)")
        download(url, target)
        actual = target.stat().st_size
        if actual != expected:
            sys.exit(f"{target.name}: got {actual} bytes, expected {expected}")


if __name__ == "__main__":
    main()
