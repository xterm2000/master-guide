#!/usr/bin/env bash
#
# Aurora — a truecolor gradient bash prompt with command timing.
# Install: add `source ~/aurora-prompt.sh` to the end of your ~/.bashrc,
#          then run `source ~/.bashrc`.
#
# Requires a terminal with 24-bit ("truecolor") support — virtually every
# modern one (Windows Terminal, iTerm2, kitty, Alacritty, VS Code, GNOME).
#
#   ╭─ 14:22 · you@host · ~/src/aurora ·  main✓ · ⏱ 1.20s
#   ╰─❯❯❯
#
#   • the path is drawn with a smooth cyan→violet→pink character gradient
#   • ⏱ shows how long the previous command ran (hidden if it was instant)
#   • the ❯❯❯ arrows glow on success and turn solid red on failure

# ── palette (24-bit RGB) ─────────────────────────────────────────────────────
__aur_c1=(0   229 255)   # cyan   — gradient start
__aur_c2=(168 85  247)   # violet — gradient mid
__aur_c3=(244 114 182)   # pink   — gradient end
__c_reset='\[\033[0m\]'
__c_dim='\[\033[38;2;120;120;140m\]'
__c_frame='\[\033[38;2;90;90;120m\]'
__c_ok_r=80;  __c_ok_g=250;  __c_ok_b=160     # success arrow (green)
__c_bad_r=255; __c_bad_g=70; __c_bad_b=90     # failure arrow (red)

# ── high-resolution clock in milliseconds (bash 5 EPOCHREALTIME, else SECONDS) ─
__aur_now_ms() {
    if [ -n "${EPOCHREALTIME:-}" ]; then
        local t=${EPOCHREALTIME} s=${EPOCHREALTIME%.*} frac=${EPOCHREALTIME#*.}
        frac=${frac}000000; frac=${frac:0:6}
        echo $(( 10#$s * 1000 + 10#$frac / 1000 ))
    else
        echo $(( SECONDS * 1000 ))
    fi
}

# ── command timer: stamp only the FIRST command after each prompt ────────────
# __aur_arm is set as the last act of rendering the prompt, so the DEBUG trap
# fires cleanly on the user's next command and not on the prompt machinery.
__aur_preexec() {
    [ -n "${__aur_arm:-}" ] || return
    __aur_arm=
    __aur_start=$(__aur_now_ms)
}
__aur_precmd() {
    if [ -n "${__aur_start:-}" ]; then
        __aur_dur=$(( $(__aur_now_ms) - __aur_start ))
        unset __aur_start
    else
        __aur_dur=
    fi
}
trap '__aur_preexec' DEBUG

# ── format a millisecond duration compactly (450ms / 1.20s / 2m05s) ──────────
__aur_fmt_dur() {
    local ms=$1
    if   [ "$ms" -lt 1000  ]; then printf '%dms' "$ms"
    elif [ "$ms" -lt 60000 ]; then printf '%d.%02ds' $(( ms / 1000 )) $(( (ms % 1000) / 10 ))
    else printf '%dm%02ds' $(( ms / 60000 )) $(( (ms % 60000) / 1000 )); fi
}

# ── paint a string with a 3-stop character gradient, wrapped for readline ────
__aur_grad() {
    local text=$1                       # keep on its own line: a same-line
    local n=${#text} out='' i pos r g b # `local x=$1 n=${#x}` reads x unset
    for (( i = 0; i < n; i++ )); do
        if [ "$n" -le 1 ]; then pos=0; else pos=$(( i * 1000 / (n - 1) )); fi
        if [ "$pos" -lt 500 ]; then      # blend c1 → c2 over first half
            local t=$(( pos * 2 ))
            r=$(( __aur_c1[0] + (__aur_c2[0] - __aur_c1[0]) * t / 1000 ))
            g=$(( __aur_c1[1] + (__aur_c2[1] - __aur_c1[1]) * t / 1000 ))
            b=$(( __aur_c1[2] + (__aur_c2[2] - __aur_c1[2]) * t / 1000 ))
        else                             # blend c2 → c3 over second half
            local t=$(( (pos - 500) * 2 ))
            r=$(( __aur_c2[0] + (__aur_c3[0] - __aur_c2[0]) * t / 1000 ))
            g=$(( __aur_c2[1] + (__aur_c3[1] - __aur_c2[1]) * t / 1000 ))
            b=$(( __aur_c2[2] + (__aur_c3[2] - __aur_c2[2]) * t / 1000 ))
        fi
        out+="\[\033[38;2;${r};${g};${b}m\]${text:i:1}"
    done
    printf '%s%s' "$out" "$__c_reset"
}

# ── shortened, home-relative working directory ───────────────────────────────
__aur_path() {
    local p=${PWD/#$HOME/\~} max=42
    [ ${#p} -gt $max ] && p="…${p: -$((max - 1))}"
    printf '%s' "$p"
}

# ── git branch + clean/dirty glyph ───────────────────────────────────────────
__aur_git() {
    local branch
    branch=$(git symbolic-ref --short HEAD 2>/dev/null || git rev-parse --short HEAD 2>/dev/null)
    [ -z "$branch" ] && return
    if git diff --quiet --ignore-submodules HEAD -- 2>/dev/null; then
        printf ' %s· \[\033[38;2;80;250;160m\] %s✓%s' "$__c_frame" "$branch" "$__c_reset"
    else
        printf ' %s· \[\033[38;2;250;190;90m\] %s✗%s' "$__c_frame" "$branch" "$__c_reset"
    fi
}

# ── assemble PS1 fresh on every prompt ───────────────────────────────────────
__aur_set_ps1() {
    local exit_code=${__aur_exit:-0}   # captured first in PROMPT_COMMAND, since
                                       # __aur_precmd would otherwise clobber $?

    # arrow colour reflects the previous command's exit status
    local ar ag ab
    if [ "$exit_code" -eq 0 ]; then ar=$__c_ok_r;  ag=$__c_ok_g;  ab=$__c_ok_b
    else                            ar=$__c_bad_r; ag=$__c_bad_g; ab=$__c_bad_b; fi

    # optional duration segment (skip anything under 50ms — it's just noise)
    local dur_seg=''
    if [ -n "${__aur_dur:-}" ] && [ "$__aur_dur" -ge 50 ]; then
        dur_seg=" ${__c_frame}· ${__c_dim}⏱ $(__aur_fmt_dur "$__aur_dur")${__c_reset}"
    fi

    # optional exit-code badge when the last command failed
    local code_seg=''
    [ "$exit_code" -ne 0 ] && code_seg=" \[\033[38;2;255;70;90m\]✘ ${exit_code}${__c_reset}"

    PS1="${__c_frame}╭─ ${__c_dim}\t ${__c_frame}· \[\033[38;2;0;229;255m\]\u${__c_dim}@\h${__c_reset}"
    PS1+=" ${__c_frame}· $(__aur_grad "$(__aur_path)")"
    PS1+="$(__aur_git)${dur_seg}${code_seg}"
    PS1+="\n${__c_frame}╰─\[\033[38;2;${ar};${ag};${ab}m\]❯❯❯${__c_reset} "

    __aur_arm=1   # must be the last statement: arms the timer for the next command
}

PROMPT_COMMAND='__aur_exit=$?; __aur_precmd; __aur_set_ps1'
