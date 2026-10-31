# /// script
# requires-python = ">=3.11"
# dependencies = ["playwright==1.48.0"]
# ///
"""Render every table of the Medium post as a PNG, for platforms that cannot show Markdown tables.

Each image carries the table's section title, the table itself and the footnotes printed right under it, in the
shared look (media/LOOK.md). The post is the only source: re-run after changing it.

    uv run media/medium-tables/render_tables.py

Uses the locally installed Google Chrome (no browser download).
"""

import html
import re
from pathlib import Path

from playwright.sync_api import sync_playwright

REPO_ROOT = Path(__file__).resolve().parents[2]
POST = REPO_ROOT / "docs" / "blog" / "01-medium-local-benchmark.md"
OUT_DIR = REPO_ROOT / "docs" / "assets" / "medium" / "tables"
WIDTH_PX = 1400
FOOTNOTE_MARKS = "¹²³⁴⁵⁶⁷⁸⁹"
SOURCE_LINE = "Sleipnir benchmark, single laptop; results/*.parquet"

PAGE_STYLE = """
<link href="https://fonts.googleapis.com/css2?family=League+Gothic&family=Oswald:wght@400;500;600&display=block" rel="stylesheet">
<style>
  :root { --paper: #F5F7F3; --grid: #BFD8D2; --grid-faint: rgba(191, 216, 210, 0.4); --ink: #1E2A2F; --red: #D9382B; --muted: #5E6B70; }
  html, body { margin: 0; background: var(--paper); }
  .sheet {
    width: %(width)dpx; box-sizing: border-box; padding: 56px 64px 40px;
    background-color: var(--paper);
    background-image:
      linear-gradient(var(--grid-faint) 1px, transparent 1px),
      linear-gradient(90deg, var(--grid-faint) 1px, transparent 1px);
    background-size: 24px 24px;
    font-family: 'Oswald', sans-serif; color: var(--ink);
  }
  h1 { font-weight: 600; font-size: 40px; line-height: 1.2; margin: 0 0 8px; }
  .lead { font-size: 24px; color: var(--muted); margin: 0 0 24px; }
  table { width: 100%%; border-collapse: collapse; background: var(--paper); font-variant-numeric: tabular-nums; }
  th { font-weight: 500; font-size: 24px; text-align: left; padding: 12px 14px; border-bottom: 3px solid var(--ink); }
  td { font-weight: 400; font-size: 26px; padding: 12px 14px; border-bottom: 1px solid var(--grid); vertical-align: top; }
  td.num, th.num { text-align: right; white-space: nowrap; }
  td:first-child { font-weight: 500; }
  strong { color: var(--red); font-weight: 600; }
  code { font-family: 'Oswald', sans-serif; font-weight: 500; }
  .notes { margin: 20px 0 0; padding: 10px 14px 4px; background: var(--paper); font-size: 21px; color: var(--muted); line-height: 1.45; }
  .notes p { margin: 0 0 6px; }
  .source { display: inline-block; margin-top: 28px; padding: 4px 14px; background: var(--paper); font-size: 20px; color: var(--muted); }
</style>
"""


def inline_markdown(text):
    """The few inline marks the tables use: bold, code and links (link text only)."""
    escaped = html.escape(text)
    escaped = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", escaped)
    escaped = re.sub(r"`(.+?)`", r"<code>\1</code>", escaped)
    escaped = re.sub(r"\[(.+?)\]\((.+?)\)", r"\1", escaped)
    return escaped


def split_row(line):
    cells = line.strip().strip("|").split("|")
    stripped = []
    for cell in cells:
        stripped.append(cell.strip())
    return stripped


def looks_numeric(text):
    """Right-align cells that are mostly a number (with units, ranges, arrows or a footnote mark)."""
    plain = re.sub(r"[*`]", "", text).strip()
    return bool(re.fullmatch(r"[~\d.,\s/→()%×xsmhGBMTB\-–]+[" + FOOTNOTE_MARKS + r"]?", plain)) and any(
        character.isdigit() for character in plain
    )


def find_tables(lines):
    """Yield (title, lead, header, rows, notes) for every Markdown table, with the nearest heading as its title."""
    tables = []
    title = ""
    index = 0
    while index < len(lines):
        line = lines[index]
        if line.startswith("#"):
            title = line.lstrip("#").strip()
        is_table_start = line.startswith("|") and index + 1 < len(lines) and lines[index + 1].startswith("|---")
        if not is_table_start:
            index += 1
            continue

        lead = ""
        previous = lines[index - 1].strip() if index > 0 else ""
        if previous == "" and index > 1:
            previous = lines[index - 2].strip()
        if previous.endswith(":") and not previous.startswith("#"):
            lead = previous

        header = split_row(line)
        rows = []
        index += 2
        while index < len(lines) and lines[index].startswith("|"):
            rows.append(split_row(lines[index]))
            index += 1

        # Notes may sit after a sentence of commentary: collect them up to the next table or heading.
        notes = []
        scan = index
        while scan < len(lines):
            candidate = lines[scan].strip()
            if candidate.startswith("#") or candidate.startswith("|"):
                break
            if candidate and (candidate[0] in FOOTNOTE_MARKS or candidate.startswith("Derived from TPC-H")):
                notes.append(candidate)
            scan += 1
        tables.append((title, lead, header, rows, notes))
    return tables


def slug(text):
    return re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")[:48]


def numeric_columns(header, rows):
    """A column is right-aligned as a whole when most of its cells are numbers ("failed" or "n/a" follow it)."""
    aligned = set()
    for column in range(1, len(header)):
        numeric_count = 0
        filled_count = 0
        for row in rows:
            if column < len(row) and row[column]:
                filled_count += 1
                if looks_numeric(row[column]):
                    numeric_count += 1
        if filled_count and numeric_count * 2 > filled_count:
            aligned.add(column)
    return aligned


def borrow_notes_within_section(tables):
    """Footnote marks used in a table whose notes are printed under the next table of the same section."""
    completed = []
    for position, (title, lead, header, rows, notes) in enumerate(tables):
        cells = " ".join(" ".join(row) for row in rows)
        has_marks = any(mark in cells for mark in FOOTNOTE_MARKS)
        if has_marks and not notes:
            for later in tables[position + 1:]:
                if later[0] != title:
                    break
                if later[4]:
                    notes = later[4]
                    break
        completed.append((title, lead, header, rows, notes))
    return completed


def table_html(title, lead, header, rows, notes):
    parts = ['<div class="sheet">']
    # A long heading keeps its main words as the title and moves its parenthetical to a subtitle line.
    subtitle = ""
    if len(title) > 45 and " (" in title:
        title, subtitle = title.split(" (", 1)
        subtitle = subtitle.rstrip(")")
    if title:
        parts.append(f"<h1>{inline_markdown(title)}</h1>")
    if subtitle:
        parts.append(f'<p class="lead">{inline_markdown(subtitle)}</p>')
    if lead:
        parts.append(f'<p class="lead">{inline_markdown(lead)}</p>')
    aligned = numeric_columns(header, rows)
    parts.append("<table>")
    if any(header):
        parts.append("<thead><tr>")
        for column, cell in enumerate(header):
            css_class = ' class="num"' if column in aligned else ""
            parts.append(f"<th{css_class}>{inline_markdown(cell)}</th>")
        parts.append("</tr></thead>")
    parts.append("<tbody>")
    for row in rows:
        parts.append("<tr>")
        for column, cell in enumerate(row):
            css_class = ' class="num"' if column in aligned else ""
            parts.append(f"<td{css_class}>{inline_markdown(cell)}</td>")
        parts.append("</tr>")
    parts.append("</tbody></table>")
    if notes:
        parts.append('<div class="notes">')
        for note in notes:
            parts.append(f"<p>{inline_markdown(note)}</p>")
        parts.append("</div>")
    parts.append(f'<div class="source">{SOURCE_LINE}</div></div>')
    return "<!doctype html><html><head><meta charset='utf-8'>" + PAGE_STYLE % {"width": WIDTH_PX} + "</head><body>" + "".join(parts) + "</body></html>"


def main():
    lines = POST.read_text(encoding="utf-8").splitlines()
    tables = borrow_notes_within_section(find_tables(lines))
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    with sync_playwright() as playwright:
        browser = playwright.chromium.launch(channel="chrome")
        page = browser.new_page(viewport={"width": WIDTH_PX, "height": 800}, device_scale_factor=2)
        for number, (title, lead, header, rows, notes) in enumerate(tables, start=1):
            page.set_content(table_html(title, lead, header, rows, notes), wait_until="networkidle")
            page.evaluate("document.fonts.ready")
            name = f"t{number:02d}-{slug(title or header[0])}.png"
            page.locator(".sheet").screenshot(path=str(OUT_DIR / name))
            print(name)
        browser.close()


if __name__ == "__main__":
    main()
