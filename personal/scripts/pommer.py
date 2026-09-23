#!/usr/bin/env python3
"""
pommer — dead simple pomodoro CLI tracker.

Prompts for project code, task, and pom length (25 or 50 min),
counts down, dings at transitions, logs to CSV, and prints a
colour-coded weekly summary of poms.

Usage:
    pommer            # run a pom
    pommer --report   # just show the weekly summary
"""

import argparse
import csv
import subprocess
import sys
import time
from datetime import datetime, timedelta
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
RESET = "\033[0m"
DIM = "\033[2m"


# ---------- sound ----------

def ding(times=1):
    """Ubuntu only: play the desktop complete sound via paplay, fall back to terminal bell."""
    for _ in range(times):
        try:
            subprocess.run(
                ["paplay", "/usr/share/sounds/freedesktop/stereo/complete.oga"],
                check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            )
        except (FileNotFoundError, subprocess.CalledProcessError):
            sys.stdout.write("\a")
            sys.stdout.flush()
        time.sleep(0.3)


# ---------- countdown ----------

def countdown(minutes, label):
    """Returns (start_dt, end_dt, interrupted). end_dt reflects when it actually
    stopped, whether that's the full duration or an early Ctrl+C."""
    start_dt = datetime.now()
    total_seconds = minutes * 60
    interrupted = False
    print(f"\n{start_dt.strftime('%H:%M')}: {label} — {minutes} min. Ctrl+C to bail early.\n")
    try:
        while total_seconds > 0:
            mins, secs = divmod(total_seconds, 60)
            print(f"\r  {label}: {mins:02d}:{secs:02d} remaining   ", end="", flush=True)
            time.sleep(1)
            total_seconds -= 1
        print(f"\r  {label}: done!                          ")
    except KeyboardInterrupt:
        interrupted = True
        print(f"\n{start_dt.strftime('%H:%M')}: {label} stopped early.")
    end_dt = datetime.now()
    return start_dt, end_dt, interrupted


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


# ---------- weekly report ----------

def colour_for(code):
    idx = sum(ord(c) for c in code) % len(COLOURS)
    return COLOURS[idx]


def make_cell(code, width):
    """A single stacked pom cell: '[  CODE  ]' coloured, one row tall."""
    colour = colour_for(code)
    text = f"[{code:^{width - 2}}]"
    return f"\033[{colour}m{text}{RESET}"


def print_week_summary(days=7):
    rows = read_log()
    by_date = {}
    for r in rows:
        by_date.setdefault(r["date"], []).append(r)

    today = datetime.now().date()
    day_list = [today - timedelta(days=i) for i in range(days - 1, -1, -1)]  # oldest -> today

    cell_width = 12  # "[" + 10-char code + "]"
    columns = []   # one list per day, bottom-to-top: [(code, minutes), ...]
    labels = []
    totals = []

    for d in day_list:
        d_str = d.strftime("%Y-%m-%d")
        day_rows = sorted(by_date.get(d_str, []), key=lambda r: r.get("pom_start", ""))
        col = []
        total_min = 0
        for r in day_rows:
            code = r["project"][:10]
            minutes = int(r["pom_minutes"])
            total_min += minutes
            height = 2 if minutes >= 50 else 1  # longer poms get an extra stacked row
            col.extend([code] * height)
        columns.append(col)
        labels.append(d.strftime("%a %d"))
        totals.append(total_min)

    max_height = max((len(c) for c in columns), default=0)
    chart_width = cell_width * len(columns)

    print(f"\n{'=' * chart_width}\n{'Last ' + str(days) + ' days':^{chart_width}}\n{'=' * chart_width}\n")

    if max_height == 0:
        print(f"{'· no poms this week ·':^{chart_width}}")
    else:
        # print top row down to the bottom, so poms stack upward like a bar chart
        for row_idx in range(max_height - 1, -1, -1):
            line = ""
            for col in columns:
                if row_idx < len(col):
                    line += make_cell(col[row_idx], cell_width)
                else:
                    line += " " * cell_width
            print(line)

    print("─" * chart_width)
    print("".join(f"{lbl:^{cell_width}}" for lbl in labels))
    print("".join(f"{str(t) + 'm':^{cell_width}}" for t in totals))


# ---------- main flow ----------

def ask_choice(prompt, options, default=None):
    opts_str = "/".join(str(o) for o in options)
    suffix = f" (default {default})" if default is not None else ""
    while True:
        raw = input(f"{prompt} [{opts_str}]{suffix}: ").strip()
        if raw == "" and default is not None:
            return default
        if raw in [str(o) for o in options]:
            return int(raw)
        print(f"  enter one of: {opts_str}")


def ask_text(prompt, default=None):
    suffix = f" [{default}]" if default else ""
    raw = input(f"{prompt}{suffix}: ").strip()
    if raw:
        return raw
    return default if default else ""


def ask_time(prompt, default_dt):
    """Prompts for a clock time (HH:MM, 24h or with am/pm), defaulting to default_dt
    on empty input. Returns a datetime on the same day as default_dt."""
    formats = ("%H:%M", "%H:%M:%S", "%I:%M%p", "%I:%M %p", "%I%p")
    while True:
        raw = input(f"{prompt} [{default_dt.strftime('%H:%M')}]: ").strip()
        if not raw:
            return default_dt
        for fmt in formats:
            try:
                t = datetime.strptime(raw, fmt).time()
                return datetime.combine(default_dt.date(), t)
            except ValueError:
                continue
        print("  couldn't parse that — try 24h HH:MM or e.g. 2:30pm")


def do_one_pom(project, task, iteration_label=""):
    """Runs one pom + break, logs it, returns True if either phase was interrupted."""
    pom_minutes = ask_choice(f"Pom length (minutes){iteration_label}", [25, 50], default=25)
    break_minutes = 5 if pom_minutes == 25 else 10

    pom_start, pom_end, pom_interrupted = countdown(
        pom_minutes, f"[{project}] {task} — pom{iteration_label}"
    )
    print(f"\n{datetime.now().strftime('%H:%M')}: Pom done. Break time.")
    ding(2)  # start of break

    break_start, break_end, break_interrupted = countdown(break_minutes, f"Break{iteration_label}")
    print(f"\n{datetime.now().strftime('%H:%M')}: Break over. Back to it.")
    ding(3)  # end of break

    log_session(project, task, pom_minutes, pom_start, pom_end,
                break_minutes, break_start, break_end)
    print(f"\nLogged to {LOG_PATH}")

    return pom_interrupted or break_interrupted


def run_manual():
    print("=== pommer (manual entry) ===")
    project = ask_text("Project code", default="MSC")
    task = ask_text("Task", default="unspecified")
    pom_minutes = ask_choice("Pom length (minutes)", [25, 50], default=25)
    break_minutes = 5 if pom_minutes == 25 else 10

    now = datetime.now()
    default_pom_start = now - timedelta(minutes=pom_minutes + break_minutes)
    pom_start = ask_time("Pom start time", default_pom_start)
    pom_end = pom_start + timedelta(minutes=pom_minutes)

    break_start = pom_end
    break_end = break_start + timedelta(minutes=break_minutes)

    log_session(project, task, pom_minutes, pom_start, pom_end,
                break_minutes, break_start, break_end)
    print(f"\nLogged to {LOG_PATH}")
    print_week_summary()


def run_pom():
    print("=== pommer ===")
    project = input("Project code: ").strip() or "misc"
    task = input("Task: ").strip() or "unspecified"
    do_one_pom(project, task)
    print_week_summary()


def run_repeats(count):
    """count == 0 means run indefinitely until Ctrl+C. No summary is shown between
    poms — only once at the end, or immediately if interrupted."""
    print("=== pommer (repeat mode) ===")
    project = None
    task = None

    completed = 0
    try:
        while count == 0 or completed < count:
            project = ask_text("Project code", default=project or "misc")
            task = ask_text("Task", default=task or "unspecified")
            label = f" ({completed + 1}/{count})" if count else f" (#{completed + 1})"
            interrupted = do_one_pom(project, task, iteration_label=label)
            completed += 1
            if interrupted:
                print("\nInterrupted — stopping repeats.")
                break
    except KeyboardInterrupt:
        print("\nStopped.")
    finally:
        print(f"\nCompleted {completed} pom(s).")
        print_week_summary()


def main():
    parser = argparse.ArgumentParser(description="Simple pomodoro CLI tracker")
    parser.add_argument("--report", action="store_true", help="just show the weekly summary")
    parser.add_argument(
        "--manual", "-m", action="store_true",
        help="manually log an entry (asks the same questions but skips the timers)",
    )
    parser.add_argument(
        "--repeats", "-r", nargs="?", type=int, const=0, default=None,
        help="run multiple poms back-to-back without showing the summary each time. "
             "Give a number to repeat that many times, or omit it to run until Ctrl+C.",
    )
    args = parser.parse_args()

    if args.report:
        print_week_summary()
    elif args.manual:
        run_manual()
    elif args.repeats is not None:
        run_repeats(args.repeats)
    else:
        run_pom()


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\nBailed. Nothing logged.")
