"""
pomlib — shared data helpers for pommer: the pom log, goals, tiers, streaks and
project colours. No printing beyond warnings; the display lives in pommer.py.
"""

import csv
from datetime import date, timedelta
from pathlib import Path

LOG_PATH = Path.home() / "pom_log.csv"
CSV_HEADERS = [
    "date", "project", "task",
    "pom_minutes", "pom_start", "pom_end",
    "break_minutes", "break_start", "break_end",
]

# project codes are stored uppercase and kept short enough to fit the report columns
PROJECT_MAX_LEN = 10

# A goal applies from its "from" date until a later row for the same project
# replaces it. Zeros retire a goal. Lines starting with "#" are ignored.
GOALS_PATH = Path.home() / "pom_goals.csv"
GOAL_HEADERS = ["from", "project", "good", "great", "stretch", "days"]

# poms are counted in 25 minute units, so a 50 minute pom counts as 2
POM_UNIT_MINUTES = 25

# daily limits, in poms, on each tier's goals summed across projects
TIER_LIMITS = {"good": 8, "great": 16, "stretch": 32}

# tiers for a planned day; unplanned days have no tier (None)
MISSED, GOOD, GREAT, STRETCH = 0, 1, 2, 3
TIER_NAMES = {MISSED: "missed", GOOD: "good", GREAT: "great", STRETCH: "stretch"}

WEEKDAYS = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

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


# ---------- goals ----------

def parse_days(text):
    """Turns '*', 'Mon-Fri', 'Mon Wed Fri' or a mix like 'Mon-Wed Sat' into a set of
    weekday numbers (Mon = 0). Commas work too, but need quoting in the CSV."""
    text = text.strip()
    if text == "*":
        return set(range(7))
    days = set()
    for part in text.replace(",", " ").split():
        if "-" in part:
            start, end = (WEEKDAYS.index(p.title()) for p in part.split("-"))
            if start > end:
                raise ValueError(f"day range {part} runs backwards")
            days.update(range(start, end + 1))
        else:
            days.add(WEEKDAYS.index(part.title()))
    if not days:
        raise ValueError("no days given")
    return days


def format_days(days):
    """The reverse of parse_days: '*' for every day, otherwise e.g. 'Mon-Wed Sat',
    with runs of three or more days written as a range."""
    if days == set(range(7)):
        return "*"
    ordered = sorted(days)
    parts = []
    i = 0
    while i < len(ordered):
        j = i
        while j + 1 < len(ordered) and ordered[j + 1] == ordered[j] + 1:
            j += 1
        if j - i >= 2:
            parts.append(f"{WEEKDAYS[ordered[i]]}-{WEEKDAYS[ordered[j]]}")
        else:
            parts.extend(WEEKDAYS[d] for d in ordered[i:j + 1])
        i = j + 1
    return " ".join(parts)


def check_tiers(good, great, stretch):
    if not 0 <= good <= great <= stretch:
        raise ValueError("needs 0 <= good <= great <= stretch")


def read_goals(path=GOALS_PATH):
    """Returns the goal rows sorted by start date. Bad rows are skipped with a warning."""
    if not path.exists():
        return []
    with open(path, newline="") as f:
        lines = [line for line in f if not line.lstrip().startswith("#")]
    reader = csv.DictReader(lines, skipinitialspace=True)
    if reader.fieldnames != GOAL_HEADERS:
        print(f"Warning: {path} doesn't match the expected columns "
              f"({GOAL_HEADERS}) — skipping it.")
        return []

    goals = []
    for row in reader:
        try:
            goal = {
                "from": date.fromisoformat(row["from"].strip()),
                "project": row["project"].strip().upper(),
                "good": int(row["good"]),
                "great": int(row["great"]),
                "stretch": int(row["stretch"]),
                "days": parse_days(row["days"]),
            }
            check_tiers(goal["good"], goal["great"], goal["stretch"])
        except (ValueError, TypeError, AttributeError) as e:
            print(f"Warning: skipping goal row {dict(row)} in {path}: {e}")
            continue
        goals.append(goal)
    # sorted() is stable, so a later row with the same date and project wins
    return sorted(goals, key=lambda g: g["from"])


def add_goal(project, good, great, stretch, days, start, path=GOALS_PATH):
    """Appends a goal row, creating the file with a header if needed."""
    check_tiers(good, great, stretch)
    new_file = not path.exists()
    with open(path, "a", newline="") as f:
        writer = csv.writer(f)
        if new_file:
            writer.writerow(GOAL_HEADERS)
        writer.writerow([start.isoformat(), project, good, great, stretch, format_days(days)])


def goal_for(goals, project, day):
    """The goal in effect for a project on a day, or None if there isn't one."""
    current = None
    for goal in goals:
        if goal["project"] == project and goal["from"] <= day:
            current = goal
    if current is None or current["good"] == 0:
        return None
    return current


def weekday_totals(goals, day):
    """Each tier's goals summed across projects, per weekday, using the goals in
    effect on day. Returns a list of 7 dicts keyed like TIER_LIMITS (Mon first)."""
    totals = [{key: 0 for key in TIER_LIMITS} for _ in WEEKDAYS]
    for project in {g["project"] for g in goals}:
        goal = goal_for(goals, project, day)
        if goal is None:
            continue
        for weekday in goal["days"]:
            for key in TIER_LIMITS:
                totals[weekday][key] += goal[key]
    return totals


def over_limits(totals):
    """(tier, total, weekdays) for each tier total over its limit, with weekdays
    that share the same total grouped together."""
    over = {}
    for weekday, day_totals in enumerate(totals):
        for key, limit in TIER_LIMITS.items():
            if day_totals[key] > limit:
                over.setdefault((key, day_totals[key]), set()).add(weekday)
    return [(key, total, days) for (key, total), days in over.items()]


def daily_poms(log_rows):
    """Pom counts per (project, date), in POM_UNIT_MINUTES units."""
    counts = {}
    for r in log_rows:
        key = (r["project"], date.fromisoformat(r["date"]))
        counts[key] = counts.get(key, 0) + int(r["pom_minutes"]) // POM_UNIT_MINUTES
    return counts


def tier_for(goals, poms, project, day):
    """The highest tier reached on a planned day, MISSED if none, or None if the
    day isn't planned for this project."""
    goal = goal_for(goals, project, day)
    if goal is None or day.weekday() not in goal["days"]:
        return None
    count = poms.get((project, day), 0)
    for tier, key in ((STRETCH, "stretch"), (GREAT, "great"), (GOOD, "good")):
        if count >= goal[key]:
            return tier
    return MISSED


def todays_progress(goals, poms, today):
    """One dict per project planned today: poms done, the good goal, the tier
    reached, and the next tier with poms left to it (None and 0 after stretch)."""
    progress = []
    for project in sorted({g["project"] for g in goals}):
        tier = tier_for(goals, poms, project, today)
        if tier is None:
            continue
        goal = goal_for(goals, project, today)
        done = poms.get((project, today), 0)
        next_tier = None if tier == STRETCH else tier + 1
        left = goal[TIER_NAMES[next_tier]] - done if next_tier else 0
        progress.append({"project": project, "done": done, "good": goal["good"],
                         "tier": tier, "next": next_tier, "left": left})
    return progress


def streaks(goals, poms, project, today):
    """Returns (current, best) runs of planned days at GOOD or better. Unplanned days
    are skipped, and a miss today doesn't end the run since the day isn't over."""
    starts = [g["from"] for g in goals if g["project"] == project]
    if not starts:
        return 0, 0
    run = best = 0
    day = min(starts)
    while day <= today:
        tier = tier_for(goals, poms, project, day)
        if tier is None:
            pass
        elif tier >= GOOD:
            run += 1
            best = max(best, run)
        elif day != today:
            run = 0
        day += timedelta(days=1)
    return run, best


# ---------- colours ----------

def colour_for(code):
    idx = sum(ord(c) for c in code) % len(COLOURS)
    return COLOURS[idx]
