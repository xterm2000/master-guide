#!/usr/bin/env bash
#
# Custom two-line colorized bash prompt.
# Install: add `source ~/prompt.sh` to the end of your ~/.bashrc, then `source ~/.bashrc`.
#
# ┌─[user@host]─[~/path]─[git:branch✗]
# └─❯
#
# The bottom arrow turns green after a successful command and red after a
# failed one, giving instant pass/fail feedback on the previous command.

# --- colors (256-color escapes, wrapped in \[ \] so readline counts width correctly) ---
__c_reset='\[\033[0m\]'
__c_user='\[\033[1;38;5;51m\]'      # bright cyan
__c_host='\[\033[1;38;5;51m\]'      # bright cyan
__c_at='\[\033[0;38;5;245m\]'       # grey
__c_path='\[\033[1;38;5;33m\]'      # bold blue
__c_frame='\[\033[0;38;5;240m\]'    # dim grey box-drawing
__c_git_clean='\[\033[1;38;5;76m\]' # green
__c_git_dirty='\[\033[1;38;5;178m\]'# yellow
__c_ok='\[\033[1;38;5;46m\]'        # bright green
__c_fail='\[\033[1;38;5;196m\]'     # bright red

__git_prompt_info() {
    local branch status
    branch=$(git symbolic-ref --short HEAD 2>/dev/null || git rev-parse --short HEAD 2>/dev/null)
    [ -z "$branch" ] && return

    if git diff --quiet --ignore-submodules HEAD -- 2>/dev/null; then
        status="${__c_git_clean}${branch}✓${__c_reset}"
    else
        status="${__c_git_dirty}${branch}✗${__c_reset}"
    fi
    printf '%s─[git:%s]' "${__c_frame}" "$status"
}

__set_ps1() {
    local exit_code=$?

    local arrow_color="${__c_ok}"
    [ "$exit_code" -ne 0 ] && arrow_color="${__c_fail}"

    local git_info
    git_info=$(__git_prompt_info)

    PS1="${__c_frame}┌─${__c_reset}[${__c_user}\u${__c_at}@${__c_host}\h${__c_reset}]${__c_frame}─${__c_reset}[${__c_path}\w${__c_reset}]${git_info}${__c_reset}\n${__c_frame}└─${arrow_color}❯${__c_reset} "
}

PROMPT_COMMAND=__set_ps1
