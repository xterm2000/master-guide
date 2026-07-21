#!/usr/bin/env python3
"""Claude Code status line: model, dir, project, git, context, cost, rate limits."""
import json
import os
import subprocess
import sys
import time

# ---- palette (256-color ANSI) ----
RESET = "\033[0m"
DIM = "\033[2m"
BOLD = "\033[1m"


def fg(n):
    return f"\033[38;5;{n}m"


def bg(n):
    return f"\033[48;5;{n}m"


def chip(text, fg_n, bg_n, bold=True):
    b = BOLD if bold else ""
    return f"{bg(bg_n)}{fg(fg_n)}{b} {text} {RESET}"


VIOLET, VIOLET_FG = 99, 255
SLATE, SLATE_FG = 238, 250
GREEN, YELLOW, RED, CYAN, GOLD, PINK = 78, 220, 203, 80, 214, 212
MUTED = 245


def read_input():
    try:
        return json.load(sys.stdin)
    except Exception:
        return {}


def git_info(cwd, session_id):
    cache_file = f"/tmp/statusline-git-{session_id}"
    max_age = 4
    stale = True
    if os.path.exists(cache_file):
        stale = (time.time() - os.path.getmtime(cache_file)) > max_age
    if stale:
        try:
            subprocess.run(
                ["git", "rev-parse", "--git-dir"],
                cwd=cwd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True, timeout=2,
            )
            branch = subprocess.run(
                ["git", "branch", "--show-current"], cwd=cwd, capture_output=True, text=True, timeout=2
            ).stdout.strip() or "detached"
            staged = subprocess.run(
                ["git", "diff", "--cached", "--numstat"], cwd=cwd, capture_output=True, text=True, timeout=2
            ).stdout.strip()
            modified = subprocess.run(
                ["git", "diff", "--numstat"], cwd=cwd, capture_output=True, text=True, timeout=2
            ).stdout.strip()
            untracked = subprocess.run(
                ["git", "ls-files", "--others", "--exclude-standard"], cwd=cwd, capture_output=True, text=True, timeout=2
            ).stdout.strip()
            n_staged = len(staged.splitlines()) if staged else 0
            n_modified = len(modified.splitlines()) if modified else 0
            n_untracked = len(untracked.splitlines()) if untracked else 0
            ahead = behind = 0
            rev = subprocess.run(
                ["git", "rev-list", "--left-right", "--count", "HEAD...@{upstream}"],
                cwd=cwd, capture_output=True, text=True, timeout=2,
            )
            if rev.returncode == 0 and rev.stdout.strip():
                parts = rev.stdout.strip().split()
                if len(parts) == 2:
                    ahead, behind = parts
            with open(cache_file, "w") as f:
                f.write(f"{branch}|{n_staged}|{n_modified}|{n_untracked}|{ahead}|{behind}")
        except Exception:
            with open(cache_file, "w") as f:
                f.write("|0|0|0|0|0")
    try:
        with open(cache_file) as f:
            branch, staged, modified, untracked, ahead, behind = f.read().strip().split("|")
        return branch, int(staged), int(modified), int(untracked), int(ahead), int(behind)
    except Exception:
        return "", 0, 0, 0, 0, 0


def bar(pct, width=12):
    blocks = "▏▎▍▌▋▊▉█"
    filled_f = (pct / 100) * width
    filled = int(filled_f)
    frac = filled_f - filled
    partial = blocks[int(frac * (len(blocks) - 1))] if filled < width and frac > 0.05 else ""
    empty = max(0, width - filled - (1 if partial else 0))
    color = GREEN if pct < 60 else YELLOW if pct < 85 else RED
    return f"{fg(color)}{'█' * filled}{partial}{fg(238)}{'░' * empty}{RESET}"


def fmt_duration(ms):
    s = ms // 1000
    h, s = divmod(s, 3600)
    m, s = divmod(s, 60)
    if h:
        return f"{h}h{m:02d}m"
    if m:
        return f"{m}m{s:02d}s"
    return f"{s}s"


def main():
    data = read_input()

    model = data.get("model", {}).get("display_name", "?")
    ws = data.get("workspace", {})
    cwd = ws.get("current_dir") or data.get("cwd") or os.getcwd()
    project_dir = ws.get("project_dir") or cwd
    session_id = data.get("session_id", "nosession")

    dir_name = os.path.basename(cwd.rstrip("/")) or cwd
    project_name = os.path.basename(project_dir.rstrip("/")) or project_dir

    cw = data.get("context_window") or {}
    pct = cw.get("used_percentage")
    pct = 0 if pct is None else int(pct)

    cost = data.get("cost", {}) or {}
    cost_usd = cost.get("total_cost_usd") or 0
    duration_ms = cost.get("total_duration_ms") or 0

    rl = data.get("rate_limits", {}) or {}
    five_h = rl.get("five_hour", {}).get("used_percentage")
    seven_d = rl.get("seven_day", {}).get("used_percentage")

    effort = data.get("effort", {}).get("level")
    output_style = data.get("output_style", {}).get("name")

    # --- line 1: model | dir | project ---
    seg1 = chip(f"⚡ {model}", VIOLET_FG, VIOLET)
    seg_dir = f"{fg(CYAN)}📁 {dir_name}{RESET}"
    parts1 = [seg1, seg_dir]
    if project_name and project_name != dir_name:
        parts1.append(f"{DIM}{fg(MUTED)}({project_name}){RESET}")
    if effort:
        parts1.append(f"{DIM}{fg(PINK)}effort:{effort}{RESET}")

    # --- line 2: git ---
    branch, staged, modified, untracked, ahead, behind = git_info(cwd, session_id)
    if branch:
        dirty = staged or modified or untracked
        branch_color = YELLOW if dirty else GREEN
        status_bits = []
        if staged:
            status_bits.append(f"{fg(GREEN)}+{staged}{RESET}")
        if modified:
            status_bits.append(f"{fg(YELLOW)}~{modified}{RESET}")
        if untracked:
            status_bits.append(f"{fg(MUTED)}?{untracked}{RESET}")
        sync_bits = []
        if int(ahead):
            sync_bits.append(f"{fg(CYAN)}↑{ahead}{RESET}")
        if int(behind):
            sync_bits.append(f"{fg(RED)}↓{behind}{RESET}")
        clean_tag = f"{fg(GREEN)}✓{RESET}" if not dirty else ""
        line2 = f"{fg(branch_color)}🌿 {branch}{RESET} " + " ".join(status_bits + sync_bits) + (f" {clean_tag}" if clean_tag else "")
        line2 = line2.rstrip()
    else:
        line2 = f"{DIM}{fg(MUTED)}no git repo{RESET}"

    # --- line 3: context / cost / rate limits ---
    ctx_seg = f"{bar(pct)} {fg(238)}{RESET}{BOLD}{pct}%{RESET}"
    cost_seg = f"{fg(GOLD)}$ {cost_usd:.2f}{RESET}"
    time_seg = f"{fg(MUTED)}⏱ {fmt_duration(duration_ms)}{RESET}"

    rl_bits = []
    if five_h is not None:
        c = GREEN if five_h < 60 else YELLOW if five_h < 85 else RED
        rl_bits.append(f"{fg(c)}5h {five_h:.0f}%{RESET}")
    if seven_d is not None:
        c = GREEN if seven_d < 60 else YELLOW if seven_d < 85 else RED
        rl_bits.append(f"{fg(c)}7d {seven_d:.0f}%{RESET}")
    rl_seg = f" {DIM}│{RESET} ".join(rl_bits) if rl_bits else ""

    line3_parts = [ctx_seg, cost_seg, time_seg]
    if rl_seg:
        line3_parts.append(rl_seg)
    line3 = f" {DIM}│{RESET} ".join(line3_parts)

    print(" ".join(parts1))
    print(f" {line2}")
    print(f" {line3}")


if __name__ == "__main__":
    main()