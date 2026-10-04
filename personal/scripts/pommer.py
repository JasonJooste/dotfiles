#!/usr/bin/env python3
"""
pommer — dead simple pomodoro CLI tracker.

Prompts for project code, task, and pom length (25 or 50 min),
counts down, dings at transitions, logs to CSV, and prints a
colour-coded weekly summary of poms.

Usage:
    pommer            # run a pom
    pommer --report   # just show the weekly summary
    pommer --goal     # add or change a project goal
    pommer -t         # show what's left to reach today's goals
"""

import argparse
import subprocess
import sys
import time
from datetime import datetime, timedelta

from pomlib import (
    GOALS_PATH, LOG_PATH, MISSED, PROJECT_MAX_LEN, TIER_LIMITS, TIER_NAMES, WEEKDAYS,
    add_goal, colour_for, daily_poms, format_days, goal_for, log_session, over_limits,
    parse_days, read_goals, read_log, todays_progress, weekday_totals,
)

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
    print(f"\n{start_dt.strftime('%H:%M')}: {label} — {minutes} min. Press Ctrl+C to stop early.\n")
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


# ---------- weekly report ----------

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


def progress_line(p):
    """e.g. 'MSC          3/4  1 to good' or 'TBK          5/4  good, 1 to great'."""
    colour = colour_for(p["project"])
    line = f"\033[{colour}m{p['project']:<10}{RESET}  {p['done']:>3}/{p['good']:<3}"
    if p["next"] is None:
        return f"{line}  stretch reached"
    to_next = f"{p['left']} to {TIER_NAMES[p['next']]}"
    if p["tier"] == MISSED:
        return f"{line}  {to_next}"
    return f"{line}  {TIER_NAMES[p['tier']]}, {to_next}"


def todays_progress_now():
    return todays_progress(read_goals(), daily_poms(read_log()), datetime.now().date())


def print_todays_goals():
    progress = todays_progress_now()
    print("\nToday's goals")
    if not progress:
        print("  No goals planned for today")
    for p in progress:
        print(f"  {progress_line(p)}")


def limit_warnings(totals):
    """One warning line per tier total that's over its daily limit."""
    return [f"Warning: {key} goals add up to {total} poms on {format_days(days)}, "
            f"over the limit of {TIER_LIMITS[key]}"
            for key, total, days in over_limits(totals)]


def print_goal_summary():
    """Each tier's daily goals summed across projects, per weekday."""
    totals = weekday_totals(read_goals(), datetime.now().date())
    print("\nDaily goals (poms)")
    print(f"{'':10}" + "".join(f"{d:>5}" for d in WEEKDAYS) + f"{'limit':>7}")
    for key, limit in TIER_LIMITS.items():
        print(f"{key:10}" + "".join(f"{t[key]:>5}" for t in totals) + f"{limit:>7}")
    for line in limit_warnings(totals):
        print(line)


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
        print(f"  Enter one of: {opts_str}")


def ask_text(prompt, default=None):
    suffix = f" [{default}]" if default else ""
    raw = input(f"{prompt}{suffix}: ").strip()
    if raw:
        return raw
    return default if default else ""


def ask_project(default):
    """Prompts for a project code, uppercased and at most PROJECT_MAX_LEN chars."""
    while True:
        project = ask_text("Project code", default=default).upper()
        if not project:
            print("  Enter a project code")
        elif len(project) > PROJECT_MAX_LEN:
            print(f"Project codes can't be longer than {PROJECT_MAX_LEN} characters")
        else:
            return project


def ask_count(prompt, default=None, minimum=0):
    """Prompts for a whole number >= minimum. A default below the minimum is dropped."""
    if default is not None and default < minimum:
        default = None
    while True:
        raw = ask_text(prompt, default=None if default is None else str(default))
        if raw.isdigit() and int(raw) >= minimum:
            return int(raw)
        print(f"  Enter a whole number of {minimum} or more")


def ask_days(default):
    """Prompts for the days a goal applies to, returned as a set of weekday numbers."""
    while True:
        raw = ask_text("Days (*, Mon-Fri, Mon Wed Fri)", default=default)
        try:
            return parse_days(raw)
        except ValueError:
            print("  Couldn't parse the days. Use *, a range like Mon-Fri, or a list like Mon Wed Fri.")


def ask_date(prompt, default_date):
    """Prompts for a date (YYYY-MM-DD, or MM-DD for this year, or -N for N days ago),
    defaulting to default_date on empty input. Returns a date."""
    while True:
        raw = input(f"{prompt} [{default_date.strftime('%Y-%m-%d')}]: ").strip()
        if not raw:
            return default_date
        if raw.startswith("-") and raw[1:].isdigit():
            return default_date - timedelta(days=int(raw[1:]))
        try:
            return datetime.strptime(raw, "%Y-%m-%d").date()
        except ValueError:
            pass
        try:
            return datetime.strptime(f"{default_date.year}-{raw}", "%Y-%m-%d").date()
        except ValueError:
            pass
        print("  couldn't parse that — try YYYY-MM-DD, MM-DD, or e.g. -1 for yesterday")


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
        print("  Couldn't parse the time. Use 24h HH:MM or a time like 2:30pm.")


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
    project = ask_project(default="MSC")
    task = ask_text("Task", default="unspecified")
    pom_minutes = ask_choice("Pom length (minutes)", [25, 50], default=25)
    break_minutes = 5 if pom_minutes == 25 else 10

    now = datetime.now()
    default_pom_start = now - timedelta(minutes=pom_minutes + break_minutes)
    pom_date = ask_date("Date", now.date())
    default_pom_start = datetime.combine(pom_date, default_pom_start.time())
    pom_start = ask_time("Pom start time", default_pom_start)
    pom_end = pom_start + timedelta(minutes=pom_minutes)

    break_start = pom_end
    break_end = break_start + timedelta(minutes=break_minutes)

    log_session(project, task, pom_minutes, pom_start, pom_end,
                break_minutes, break_start, break_end)
    print(f"\nLogged to {LOG_PATH}")
    print_week_summary()
    print_todays_goals()


def describe_goal(goal):
    return (f"good {goal['good']}, great {goal['great']}, stretch {goal['stretch']}, "
            f"days {format_days(goal['days'])}")


def run_goal():
    """Adds a goal row that takes effect today, replacing the project's current goal."""
    print("=== pommer (add goal) ===")
    project = ask_project(default=None)
    today = datetime.now().date()
    goals = read_goals()
    current = goal_for(goals, project, today)
    if current:
        print(f"  Current goal: {describe_goal(current)}")
        good = ask_count("Good (daily poms, 0 retires the goal)", current["good"])
    else:
        print(f"  {project} has no goal yet.")
        good = ask_count("Good (daily poms)", minimum=1)

    if good == 0:
        goal = {"good": 0, "great": 0, "stretch": 0, "days": current["days"]}
    else:
        # keep the current great/stretch if good hasn't changed, otherwise scale from good
        keep = current and current["good"] == good
        great = ask_count("Great", current["great"] if keep else good * 2, minimum=good)
        stretch = ask_count("Stretch", current["stretch"] if keep else max(good * 4, great),
                            minimum=great)
        days = ask_days(format_days(current["days"]) if current else "Mon-Fri")
        goal = {"good": good, "great": great, "stretch": stretch, "days": days}

    print(f"\n  From {today}, {project}: {describe_goal(goal)}")
    # goal_for takes the last matching row, so the new goal replaces the current one
    proposed = goals + [{**goal, "from": today, "project": project}]
    for line in limit_warnings(weekday_totals(proposed, today)):
        print(f"  {line}")
    if ask_text("Add this goal? (y/n)", default="y").lower() != "y":
        print("Nothing added.")
        return
    add_goal(project, goal["good"], goal["great"], goal["stretch"], goal["days"], today)
    print(f"\nAdded to {GOALS_PATH}")


def run_pom():
    print("=== pommer ===")
    project = ask_project(default="MSC")
    task = input("Task: ").strip() or "unspecified"
    do_one_pom(project, task)
    print_week_summary()
    print_todays_goals()


def run_repeats(count):
    """count == 0 means run indefinitely until Ctrl+C. No summary is shown between
    poms — only once at the end, or immediately if interrupted."""
    print("=== pommer (repeat mode) ===")
    project = None
    task = None

    completed = 0
    try:
        while count == 0 or completed < count:
            project = ask_project(default=project or "MSC")
            task = ask_text("Task", default=task or "unspecified")
            label = f" ({completed + 1}/{count})" if count else f" (#{completed + 1})"
            interrupted = do_one_pom(project, task, iteration_label=label)
            completed += 1
            for p in todays_progress_now():
                if p["project"] == project:
                    print(progress_line(p))
            if interrupted:
                print("\nInterrupted — stopping repeats.")
                break
    except KeyboardInterrupt:
        print("\nStopped.")
    finally:
        print(f"\nCompleted {completed} pom(s).")
        print_week_summary()
        print_todays_goals()


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
    parser.add_argument(
        "--goal", "-g", action="store_true",
        help="add or change a project's daily pom goal (takes effect today)",
    )
    parser.add_argument(
        "--todays-goals", "-t", action="store_true",
        help="show what's left to reach today's goals",
    )
    args = parser.parse_args()

    if args.report:
        print_week_summary()
        print_goal_summary()
    elif args.goal:
        run_goal()
    elif args.todays_goals:
        print_todays_goals()
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
        print("\nCancelled. Nothing logged.")
