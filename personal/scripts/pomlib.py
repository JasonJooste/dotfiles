"""
pomlib — shared data helpers for pommer: the pom log and project colours.
No printing beyond warnings; the display lives in pommer.py.
"""

import csv
from pathlib import Path

LOG_PATH = Path.home() / "pom_log.csv"
CSV_HEADERS = [
    "date", "project", "task",
    "pom_minutes", "pom_start", "pom_end",
    "break_minutes", "break_start", "break_end",
]

# ANSI colour codes, cycled through per project code (deterministic, not hash()-based
# since str hashing is randomised per run)
COLOURS = [31, 32, 33, 34, 35, 36, 91, 92, 93, 94, 95, 96]


# ---------- logging ----------

def ensure_log():
    if not LOG_PATH.exists():
        with open(LOG_PATH, "w", newline="") as f:
            csv.writer(f).writerow(CSV_HEADERS)


def log_session(project, task, pom_minutes, pom_start, pom_end,
                 break_minutes, break_start, break_end):
    ensure_log()
    with open(LOG_PATH, "a", newline="") as f:
        csv.writer(f).writerow([
            pom_start.strftime("%Y-%m-%d"),
            project,
            task,
            pom_minutes,
            pom_start.strftime("%H:%M:%S"),
            pom_end.strftime("%H:%M:%S"),
            break_minutes,
            break_start.strftime("%H:%M:%S"),
            break_end.strftime("%H:%M:%S"),
        ])


def read_log():
    if not LOG_PATH.exists():
        return []
    with open(LOG_PATH, newline="") as f:
        reader = csv.DictReader(f)
        if reader.fieldnames != CSV_HEADERS:
            print(f"Warning: {LOG_PATH} doesn't match the expected columns "
                  f"({CSV_HEADERS}) — skipping it.")
            return []
        return list(reader)


# ---------- colours ----------

def colour_for(code):
    idx = sum(ord(c) for c in code) % len(COLOURS)
    return COLOURS[idx]
