#!/usr/bin/env python3
"""Combines several .ninja_log files (one per compiler pipeline) into a single comparison
report written to $GITHUB_STEP_SUMMARY: a headline table (wall time / files compiled per
pipeline) plus a Mermaid xychart-beta line chart overlaying all of them at once.

This is the *only* build-timing report this repo's CI writes. Runs once, in its own aggregation
job that depends on every build job finishing first (needs: [...] in the workflow), since that's
the only point in the whole workflow where all three platforms' .ninja_log files are ever
available at the same time — each build job only ever has its own. Confirmed directly that
$GITHUB_STEP_SUMMARY renders Mermaid diagrams, including xychart-beta — not something GitHub's
own docs actually confirm (see build-agent.md gotcha #20 for the full trail).

X-axis is elapsed build time in seconds, y-axis is % files compiled (0-100) — the conventional
shape for a build-progress chart (time flowing left-to-right, completion climbing), not the
reverse. Y-axis is percent-complete rather than a raw step index or per-file name because the
.ninja_log files being compared here don't have equal step counts (AssetPipeline only exists on
the Windows/msvc and Windows/clang-cl builds, not the Linux/gcc one — a real, deliberate scope
decision: msvc-dev/clang-dev both compile 178 files, linux-gcc-dev compiles 101), so a raw step
index would silently misalign what "step 80" means between a 178-file Windows build and a
101-file Linux one. All three lines share the same 0..max(wall time) x-axis, so a pipeline that
finishes early simply plateaus at 100% rather than being cut short.

The table's own "Color" column and the chart's actual line colors are kept in sync via a
%%{init: {"themeVariables": {"xyChart": {"plotColorPalette": "..."}}}}%% directive that forces
Mermaid's plotColorPalette explicitly, since GitHub renders Mermaid diagrams using whichever
theme matches the *viewer's own* light/dark GitHub setting, not a fixed one — without this the
table's color column would only be correct for viewers on the same theme as whoever wrote it.
PLOT_COLORS/PLOT_COLOR_EMOJI below must stay the same length and order as each other and as the
rows being plotted — colors are assigned strictly by plot order.

Usage: ninja_build_report_collate.py <title> <label>=<path1.ninja_log> [<label2>=<path2> ...]
"""
import os
import sys

GRID_POINTS = 21  # 0%, 5%, 10%, ..., 100%

# Forced Mermaid xyChart.plotColorPalette — see this file's own module docstring for why.
PLOT_COLORS = ["#3498db", "#2ecc71", "#e74c3c"]  # blue, green, red
PLOT_COLOR_EMOJI = ["\U0001F7E6", "\U0001F7E9", "\U0001F7E5"]  # 🟦 🟩 🟥


def parse_ninja_log(log_path):
    """Returns a list of (start_ms, end_ms, name) tuples for the *last* build session recorded
    in the given .ninja_log file, in completion order (the order ninja itself wrote them in).

    Each real .ninja_log line is: start_ms  end_ms  mtime  output  cmdhash. A .ninja_log's
    start/end timestamps are milliseconds since *that particular ninja process's own* launch,
    reset to 0 on every fresh invocation — so if this file accumulated more than one build
    session (e.g. a local `make build` run twice against the same build dir), only the final
    (most recent) session's rows are safe to compare against each other, and only in file order:
    parallel builds routinely have a later-starting edge's start time fall *before* an earlier
    edge's own end time (both in flight at once, on different threads) — comparing sorted-by-
    start rows against a running max end mistakes that completely normal overlap for a session
    boundary. The real signal (matching ninjatracing's own read_targets(), which this mirrors on
    purpose) is simpler and only valid in on-disk file order: a line whose own *end* is earlier
    than the last *end* already seen in the file means the clock reset under it, i.e. a new
    session started. Dedup by cmdhash (not output name) for the same reason ninjatracing itself
    does — a single command can legitimately produce more than one output line.
    """
    with open(log_path, "r", encoding="utf-8", errors="replace") as f:
        lines = [ln.rstrip("\n") for ln in f if ln.strip() and not ln.startswith("#")]

    entries = {}
    last_end_seen = 0
    for ln in lines:
        parts = ln.split("\t")
        if len(parts) < 5:
            continue
        start, end, _mtime, name, cmdhash = parts[0], parts[1], parts[2], parts[3], parts[4]
        start, end = int(start), int(end)
        if end < last_end_seen:
            entries = {}
        last_end_seen = end
        entries[cmdhash] = (start, end, name)

    return sorted(entries.values(), key=lambda t: t[1])


def resample_time(session, t_max):
    """Returns GRID_POINTS percent-complete values (0-100), evenly sampled across a shared
    0..t_max elapsed-seconds axis — time is the independent variable here (not percent-complete),
    so multiple sessions with different t_max values can still share one x-axis: count how many
    files had completed by each grid time, as a percentage of this session's own total."""
    if not session:
        return [0.0] * GRID_POINTS
    wall_start = session[0][0]
    n = len(session)
    elapsed = [(end - wall_start) / 1000.0 for _s, end, _n in session]  # ascending, completion order

    out = []
    idx = 0
    for g in range(GRID_POINTS):
        t = t_max * g / (GRID_POINTS - 1)
        while idx < n and elapsed[idx] <= t:
            idx += 1
        out.append(idx / n * 100.0)
    return out


def build_report(title, rows):
    """Renders the full Markdown report (headline table + xychart-beta chart) for the given
    title and `[(label, session), ...]` rows, in the order given — the chart's own plotted
    "line" order follows the same order as the table above it (see the in-line comment near the
    chart below for why that's the only correlation a reader gets, xychart-beta having no
    per-series legend of its own)."""
    out_lines = [
        f"## {title}",
        "",
        "| Color | Pipeline | Wall time (s) | Files compiled |",
        "|---|---|---|---|",
    ]
    for i, (label, session) in enumerate(rows):
        swatch = PLOT_COLOR_EMOJI[i % len(PLOT_COLOR_EMOJI)]
        if not session:
            out_lines.append(f"| {swatch} | {label} | n/a | 0 |")
            continue
        wall_start = min(s for s, _e, _n in session)
        wall_end = max(e for _s, e, _n in session)
        out_lines.append(
            f"| {swatch} | {label} | {(wall_end - wall_start) / 1000.0:.1f} | {len(session)} |"
        )
    out_lines.append("")

    wall_times = [
        (max(e for _s, e, _n in session) - min(s for s, _e, _n in session)) / 1000.0
        for _l, session in rows if session
    ]
    t_max = max(10, round(max(wall_times, default=0.0) * 1.1))
    palette = ",".join(PLOT_COLORS)
    out_lines += [
        "```mermaid",
        # Forces the exact colors PLOT_COLOR_EMOJI above represents, regardless of the viewer's
        # own GitHub light/dark theme — see this file's own module docstring for why this is
        # necessary, not just belt-and-braces.
        f'%%{{init: {{"themeVariables": {{"xyChart": {{"plotColorPalette": "{palette}"}}}}}}}}%%',
        "xychart-beta",
        f'    title "{title}"',
        f'    x-axis "Elapsed time (s)" 0 --> {t_max}',
        '    y-axis "% files compiled" 0 --> 100',
    ]
    for label, session in rows:
        values = ", ".join(f"{v:.1f}" for v in resample_time(session, t_max))
        # xychart-beta's own "line" directive has no per-series label/legend (confirmed against
        # its spec — this repo only ever compares 3 series at once, so the table's own Color
        # column stands in for a real legend instead).
        out_lines.append(f"    line [{values}]")
    out_lines.append("```")
    out_lines.append("")
    out_lines.append("Lines plotted in the order listed in the table above.")
    out_lines.append("")

    return "\n".join(out_lines)


def main():
    if len(sys.argv) < 3:
        sys.exit("usage: ninja_build_report_collate.py <title> <label>=<.ninja_log> [...]")
    title = sys.argv[1]

    rows = []  # (label, session)
    for arg in sys.argv[2:]:
        label, _, path = arg.partition("=")
        rows.append((label, parse_ninja_log(path)))

    text = build_report(title, rows)

    summary_path = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary_path:
        with open(summary_path, "a", encoding="utf-8") as f:
            f.write(text + "\n")
    else:
        # Local-testing fallback only — the real CI path above always writes UTF-8 explicitly.
        # PLOT_COLOR_EMOJI's characters are outside Windows' default console codepage (cp1252),
        # so a bare print() here fails with UnicodeEncodeError on a real Windows terminal.
        sys.stdout.buffer.write((text + "\n").encode("utf-8"))


if __name__ == "__main__":
    main()
