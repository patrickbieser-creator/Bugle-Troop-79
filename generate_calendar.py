#!/usr/bin/env python3
"""
generate_calendar.py
Troop 79 Calendar HTML Generator

Reads the ICS Feed XLSX and produces a Calendar.html file
matching the Bugle's table format, filtered from today forward.

Usage:
    python generate_calendar.py
    python generate_calendar.py --input path/to/feed.xlsx --output Calendar.html
    python generate_calendar.py --as-of 2026-06-01   # override "today" for testing
"""

import argparse
import html
import math
import pandas as pd
from datetime import date, datetime
from pathlib import Path

# ---------------------------------------------------------------------------
# Config defaults
# ---------------------------------------------------------------------------
DEFAULT_INPUT = "Troop 79 Bugle Calendar for ICS Feed.xlsx"
DEFAULT_OUTPUT = "Calendar.html"
SHEET_NAME = "EventsTasks"

DAY_ABBREVS = {0: "Mon", 1: "Tue", 2: "Wed", 3: "Thu", 4: "Fri", 5: "Sat"}
# Sunday (6) is omitted — it's the standard meeting day, no annotation needed

MONTH_NAMES = {
    1: "January", 2: "February", 3: "March", 4: "April",
    5: "May", 6: "June", 7: "July", 8: "August",
    9: "September", 10: "October", 11: "November", 12: "December"
}


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def format_date_col(start: date, end: date) -> str:
    """
    Format the date cell value.
    - Same day:            '22' or '22 (Sat)'
    - Same month range:    '17-19' or '17-19 (Sun)'
    - Cross-month range:   '26 to Aug 1' or '26 to Aug 1 (Sun)'
    Day-of-week appended for any day that is NOT Sunday.
    """
    day_abbrev = DAY_ABBREVS.get(start.weekday(), "")  # empty string for Sunday

    if start == end:
        base = str(start.day)
    elif start.month == end.month:
        base = f"{start.day}-{end.day}"
    else:
        end_month_abbrev = MONTH_NAMES[end.month][:3]
        base = f"{start.day} to {end_month_abbrev} {end.day}"

    if day_abbrev:
        return f"{base} ({day_abbrev})"
    return base


def split_title(title: str):
    """
    Split title on first ' - '.
    Returns (col2, dash_suffix) where dash_suffix may be None.
    """
    if " - " in title:
        parts = title.split(" - ", 1)
        return parts[0].strip(), parts[1].strip()
    return title.strip(), None


def get_col3(description, dash_suffix) -> str:
    """
    Col 3 priority: description field > dash_suffix > blank.
    """
    if description and not (isinstance(description, float) and math.isnan(description)):
        desc = str(description).strip()
        if desc:
            return desc
    if dash_suffix:
        return dash_suffix
    return ""


def escape(text: str) -> str:
    return html.escape(str(text)) if text else ""


# ---------------------------------------------------------------------------
# HTML template
# ---------------------------------------------------------------------------

HTML_WRAPPER = """\
<table class="my-custom-table">
    <tbody>
{rows}    </tbody>
</table>"""

MONTH_ROW = '        <tr>\n            <td class="month-cell" colspan="3">{month} </td>\n        </tr>\n'
EVENT_ROW = '        <tr>\n            <td class="event-cell">{date} </td>\n            <td>{col2} </td>\n            <td>{col3}</td>\n        </tr>\n'


# ---------------------------------------------------------------------------
# Core generator
# ---------------------------------------------------------------------------

def generate(input_path: str, output_path: str, as_of: date):
    df = pd.read_excel(input_path, sheet_name=SHEET_NAME)
    df["start_date"] = pd.to_datetime(df["start_date"]).dt.date
    df["end_date"] = pd.to_datetime(df["end_date"]).dt.date

    # Filter to today forward, sort ascending
    df = df[df["start_date"] >= as_of].sort_values("start_date").reset_index(drop=True)

    if df.empty:
        print("No upcoming events found.")
        return

    rows = []
    current_month = None

    for _, row in df.iterrows():
        start = row["start_date"]
        end = row["end_date"]

        # Inject month header when month changes
        if start.month != current_month:
            current_month = start.month
            rows.append(MONTH_ROW.format(month=MONTH_NAMES[current_month]))

        date_col = format_date_col(start, end)
        col2, dash_suffix = split_title(str(row["title"]))
        col3 = get_col3(row.get("description"), dash_suffix)

        rows.append(EVENT_ROW.format(
            date=escape(date_col),
            col2=escape(col2),
            col3=escape(col3),
        ))

    output = HTML_WRAPPER.format(rows="".join(rows))

    out = Path(output_path)
    out.write_text(output, encoding="utf-8")
    month_count = len(set(r["start_date"].month for _, r in df.iterrows()))
    print(f"Success! Processed {len(df)} events across {month_count} month(s).")
    print(f"Output written to: {out.resolve()}")


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(description="Generate Troop 79 Calendar HTML from XLSX ICS Feed")
    parser.add_argument("--input", default=DEFAULT_INPUT, help="Path to ICS Feed XLSX")
    parser.add_argument("--output", default=DEFAULT_OUTPUT, help="Output HTML file path")
    parser.add_argument("--as-of", dest="as_of", default=None,
                        help="Override today's date (YYYY-MM-DD) for testing")
    args = parser.parse_args()

    as_of = date.today()
    if args.as_of:
        as_of = datetime.strptime(args.as_of, "%Y-%m-%d").date()

    input_path = Path(args.input)
    if not input_path.exists():
        print(f"ERROR: Input file not found: {input_path.resolve()}")
        return
    print(f"Input file found: {input_path.resolve()}")
    print(f"Filtering events on or after: {as_of}")
    generate(args.input, args.output, as_of)


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        print(f"\nERROR: {e}")
    input("\nPress Enter to close...")
