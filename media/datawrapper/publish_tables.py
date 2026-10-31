# /// script
# requires-python = ">=3.11"
# dependencies = ["playwright==1.48.0"]
# ///
"""Publish every table of the Medium post as a Datawrapper table, so Medium can embed it from a pasted link.

The tables are parsed exactly like media/medium-tables/render_tables.py does (same order: t01..t21). Playwright is
needed by that import and to measure each published table for its embed height (uses the local Google Chrome).
Chart ids, public URLs and embed sizes are kept in charts.json next to this file: a re-run updates and republishes
the same charts instead of creating new ones.

    DATAWRAPPER_TOKEN=... uv run media/datawrapper/publish_tables.py
"""

import html
import json
import os
import re
import sys
import urllib.error
import urllib.request
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT / "media" / "medium-tables"))
import render_tables  # noqa: E402
from playwright.sync_api import sync_playwright  # noqa: E402

API = "https://api.datawrapper.de/v3"
CHARTS_FILE = Path(__file__).resolve().parent / "charts.json"
FOLDER_NAME = "Sleipnir — Medium 01"
SOURCE_NAME = "Sleipnir benchmark, single laptop"
SOURCE_URL = "https://github.com/jhorlima/sleipnir"
INK = "#1E2A2F"
PEN_RED = "#D9382B"
EMBED_WIDTH_PX = 600


def call(method, path, body=None, content_type="application/json"):
    data = None
    if isinstance(body, str):
        data = body.encode("utf-8")
    elif body is not None:
        data = json.dumps(body).encode("utf-8")
    request = urllib.request.Request(
        API + path,
        data=data,
        method=method,
        headers={"Authorization": f"Bearer {os.environ['DATAWRAPPER_TOKEN']}", "Content-Type": content_type},
    )
    try:
        with urllib.request.urlopen(request) as response:
            raw = response.read()
    except urllib.error.HTTPError as error:
        sys.exit(f"{method} {path} failed: {error.code} {error.read().decode('utf-8', 'replace')}")
    if not raw:
        return None
    return json.loads(raw)


def plain_text(text):
    """Markdown marks removed: bold, code and links (link text only), HTML-escaped for Datawrapper."""
    text = re.sub(r"\*\*(.+?)\*\*", r"\1", text)
    text = text.replace("`", "")
    text = re.sub(r"\[(.+?)\]\((.+?)\)", r"\1", text)
    return html.escape(text, quote=False)


def cell_html(text, bold_column):
    """A value the post bolded is printed in pen red; the first column is bold."""
    escaped = html.escape(text.replace("`", ""), quote=False)
    escaped = re.sub(r"\*\*(.+?)\*\*", rf'<b style="color:{PEN_RED}">\1</b>', escaped)
    if bold_column and escaped:
        escaped = f"<b>{escaped}</b>"
    return escaped


def csv_field(value):
    return '"' + value.replace('"', '""') + '"'


def table_csv(header, rows):
    lines = []
    header_fields = []
    for cell in header:
        header_fields.append(csv_field(plain_text(cell)))
    lines.append(",".join(header_fields))
    for row in rows:
        fields = []
        for column, cell in enumerate(row):
            fields.append(csv_field(cell_html(cell, bold_column=column == 0)))
        lines.append(",".join(fields))
    return "\n".join(lines) + "\n"


def split_title(title):
    """Like render_tables.py: a long heading keeps its main words and moves its parenthetical to the description."""
    if len(title) > 45 and " (" in title:
        main, parenthetical = title.split(" (", 1)
        return main, parenthetical.rstrip(")")
    return title, ""


def chart_metadata(header, rows, lead, description, notes):
    intro_parts = []
    if description:
        intro_parts.append(plain_text(description))
    if lead:
        intro_parts.append(plain_text(lead))
    note_lines = []
    for note in notes:
        note_lines.append(plain_text(note))

    # Every column is text so Datawrapper never reformats "2025" or "1,234"; alignment is set by hand instead.
    column_formats = {}
    column_styles = {}
    aligned = render_tables.numeric_columns(header, rows)
    for column, cell in enumerate(header):
        name = plain_text(cell)
        if not name:
            continue
        column_formats[name] = {"type": "text"}
        alignment = "right" if column in aligned else "left"
        column_styles[name] = {"alignment": alignment}

    return {
        "data": {"column-format": column_formats},
        "describe": {
            "intro": "<br>".join(intro_parts),
            "source-name": SOURCE_NAME,
            "source-url": SOURCE_URL,
            "byline": "",
        },
        "annotate": {"notes": "<br>".join(note_lines)},
        "visualize": {
            "columns": column_styles,
            "striped": False,
            "header": {"style": {"bold": True, "color": INK}, "borderBottom": "1px", "borderBottomColor": INK},
        },
    }


def find_or_create_folder():
    listing = call("GET", "/folders")
    for owner in listing["list"]:
        for folder in owner.get("folders", []):
            if folder["name"] == FOLDER_NAME:
                return folder["id"]
    return call("POST", "/folders", {"name": FOLDER_NAME})["id"]


def load_charts():
    if CHARTS_FILE.exists():
        return json.loads(CHARTS_FILE.read_text(encoding="utf-8"))
    return {}


def main():
    lines = render_tables.POST.read_text(encoding="utf-8").splitlines()
    tables = render_tables.borrow_notes_within_section(render_tables.find_tables(lines))
    folder_id = find_or_create_folder()
    charts = load_charts()

    for number, (heading, lead, header, rows, notes) in enumerate(tables, start=1):
        key = f"t{number:02d}"
        title, description = split_title(heading)
        if key in charts:
            chart_id = charts[key]["id"]
        else:
            chart_id = call("POST", "/charts", {"type": "tables", "title": plain_text(title)})["id"]

        call("PUT", f"/charts/{chart_id}/data", table_csv(header, rows), content_type="text/csv")
        call("PATCH", f"/charts/{chart_id}", {
            "title": plain_text(title),
            "folderId": folder_id,
            "metadata": chart_metadata(header, rows, lead, description, notes),
        })
        published = call("POST", f"/charts/{chart_id}/publish")["data"]
        publish_settings = call("GET", f"/charts/{chart_id}")["metadata"].get("publish", {})

        charts[key] = {
            "title": re.sub(r"[*`]", "", heading),
            "id": chart_id,
            "public_url": published["publicUrl"],
            "embed_width": publish_settings.get("embed-width"),
            "embed_height": publish_settings.get("embed-height"),
        }
        save_charts(charts)
        print(key, published["publicUrl"], heading)

    fix_embed_heights(charts)


def save_charts(charts):
    # Saved after every chart, so a failure halfway never orphans the charts already created.
    CHARTS_FILE.write_text(json.dumps(charts, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def fix_embed_heights(charts):
    """Charts published through the API keep the default 400 px embed height (the editor measures it, the API
    does not), and that is the height a pasted link gets. Measure each published table and republish if it differs."""
    with sync_playwright() as playwright:
        browser = playwright.chromium.launch(channel="chrome")
        page = browser.new_page(viewport={"width": EMBED_WIDTH_PX, "height": 100})
        for key, chart in charts.items():
            page.goto(chart["public_url"], wait_until="load")
            page.wait_for_timeout(2500)
            height = page.evaluate("document.body.scrollHeight")
            if chart["embed_width"] == EMBED_WIDTH_PX and chart["embed_height"] == height:
                continue
            call("PATCH", f"/charts/{chart['id']}", {
                "metadata": {"publish": {"embed-width": EMBED_WIDTH_PX, "embed-height": height}},
            })
            published = call("POST", f"/charts/{chart['id']}/publish")["data"]
            chart["public_url"] = published["publicUrl"]
            chart["embed_width"] = EMBED_WIDTH_PX
            chart["embed_height"] = height
            save_charts(charts)
            print(key, published["publicUrl"], f"embed height {height} px")
        browser.close()


if __name__ == "__main__":
    main()
