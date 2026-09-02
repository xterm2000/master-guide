#!/usr/bin/env bash
#
# ssh-login-report.sh — generates a detailed report on SSH login activity:
# failed attempts, top offending IPs, successful logins, and fail2ban status.
#
# Usage:
#   sudo ./ssh-login-report.sh                 # last 24 hours (default)
#   sudo ./ssh-login-report.sh "7 days ago"    # custom journalctl --since window
#
# Requires: sudo (for journalctl -u sshd), optional fail2ban, optional geoiplookup

set -euo pipefail

SINCE="${1:-24 hours ago}"
TOP_N=20
GEOIP_URL="${GEOIP_URL:-http://localhost:7900}"   # local geoip HTTP service; queried as ${GEOIP_URL}/<ip>
REPORT_FILE="ssh-report-$(date +%Y%m%d-%H%M%S).txt"

# --- guard: needs root for full journalctl access on most systems ---
if [[ $EUID -ne 0 ]]; then
    echo "This script reads sshd's journal and should be run with sudo." >&2
    exec sudo -- "$0" "$@"
fi

# geo_for <ip>  ->  "City, State, CC  lat=.. long=.."  (or a fallback label)
# used by the "last N logins" blocks in sections 3 and 4
geo_for() {
    local ip="$1" g
    command -v curl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1 || { echo "(geo lookup skipped)"; return; }
    [[ -n "${ip}" ]] || { echo "(no ip)"; return; }
    g="$(curl -s --max-time 5 "${GEOIP_URL}/${ip}" 2>/dev/null \
        | jq -r '([.city, .stateprov, .country] | map(select(. != null and . != "")) | join(", ")) as $loc
                 | (if $loc == "" then "location unknown" else $loc end)
                   + "  lat=" + (.latitude  // "?" | tostring)
                   + " long=" + (.longitude // "?" | tostring)' 2>/dev/null || true)"
    [[ -n "${g}" ]] && echo "${g}" || echo "(geo lookup failed)"
}

{
echo "=================================================================="
echo " SSH Login Report"
echo " Window : since '${SINCE}'"
echo " Host   : $(hostname)"
echo " Run at : $(date)"
echo "=================================================================="
echo

# --- Section 1: failed / invalid attempts ---
echo "------ Failed / invalid login attempts ------"
FAILED_LINES="$(journalctl -u sshd --since "${SINCE}" -o short-iso | grep -iE 'failed|invalid' || true)"
FAILED_COUNT="$(printf '%s\n' "${FAILED_LINES}" | grep -c . || true)"
echo "Total failed/invalid lines: ${FAILED_COUNT}"
echo

# --- Section 2: top offending IPs ---
echo "------ Top ${TOP_N} source IPs by failed attempts ------"
if [[ -n "${FAILED_LINES}" ]]; then
    printf '%s\n' "${FAILED_LINES}" \
        | { grep -oE 'from ([0-9]{1,3}\.){3}[0-9]{1,3}' || true; } \
        | awk '{print $2}' \
        | sort | uniq -c | sort -rn | head -n "${TOP_N}" \
        | awk '{printf "  %6d attempts  %s\n", $1, $2}' || true
else
    echo "  (none found in this window)"
fi
echo

# --- Section 3: usernames targeted ---
echo "------ Top targeted usernames ------"
if [[ -n "${FAILED_LINES}" ]]; then
    printf '%s\n' "${FAILED_LINES}" \
        | { grep -oiE 'for invalid user [^ ]+ from|for [^ ]+ from|invalid user [^ ]+ from|invalid user [^ ]+' || true; } \
        | sed -E 's/^for //I; s/^invalid user //I; s/ from$//I' \
        | sort | uniq -c | sort -rn | head -n "${TOP_N}" \
        | awk '{printf "  %6d attempts  %s\n", $1, $2}' || true
else
    echo "  (none found in this window)"
fi
echo

echo "------ Last 5 failed / invalid logins (newest first) ------"
FAILED_WITH_IP="$(printf '%s\n' "${FAILED_LINES}" | grep -E ' from ([0-9]{1,3}\.){3}[0-9]{1,3}' || true)"
if [[ -n "${FAILED_WITH_IP}" ]]; then
    printf '%s\n' "${FAILED_WITH_IP}" | tail -n 5 | tac | while read -r line; do
        ts="$(awk '{print $1}' <<<"${line}" | sed 's/T/ /')"
        ip="$( { grep -oE 'from ([0-9]{1,3}\.){3}[0-9]{1,3}' <<<"${line}" || true; } | awk '{print $2}' | head -n1)"
        user="$( { grep -oiE 'for invalid user [^ ]+ from|for [^ ]+ from|invalid user [^ ]+ from' <<<"${line}" || true; } \
                | head -n1 | sed -E 's/^for //I; s/^invalid user //I; s/ from$//I')"
        [[ -z "${user}" ]] && user="(unknown)"
        printf "  %s  %-15s  user=%-16s  %s\n" "${ts}" "${ip}" "${user}" "$(geo_for "${ip}")"
    done
else
    echo "  (none with a source IP in this window)"
fi
echo

# --- Section 4: successful logins (the important one) ---
# short-iso gives a machine-parseable leading timestamp (2026-08-31T12:00:00+0000)
ACCEPTED_LINES="$(journalctl -u sshd --since "${SINCE}" -o short-iso | grep -i 'Accepted' || true)"

echo "------ Successful logins — summary (ip / user / method x count) ------"
if [[ -n "${ACCEPTED_LINES}" ]]; then
    printf '%s\n' "${ACCEPTED_LINES}" \
        | { grep -oiE 'Accepted [a-z0-9/-]+ for [^ ]+ from ([0-9]{1,3}\.){3}[0-9]{1,3}' || true; } \
        | awk '{print $6, $4, $2}' \
        | sort | uniq -c | sort -rn \
        | awk '{printf "  %5d x  ip=%-15s  user=%-16s  method=%s\n", $1, $2, $3, $4}'
else
    echo "  (none in this window)"
fi
echo

echo "------ Last 5 successful logins (newest first) ------"
if [[ -n "${ACCEPTED_LINES}" ]]; then
    printf '%s\n' "${ACCEPTED_LINES}" | tail -n 5 | tac | while read -r line; do
        ts="$(awk '{print $1}' <<<"${line}" | sed 's/T/ /')"
        ip="$( { grep -oE 'from ([0-9]{1,3}\.){3}[0-9]{1,3}' <<<"${line}" || true; } | awk '{print $2}' | head -n1)"
        user="$( { grep -oiE 'for [^ ]+ from' <<<"${line}" || true; } | head -n1 | sed -E 's/^for //I; s/ from$//I')"
        printf "  %s  %-15s  user=%-16s  %s\n" "${ts}" "${ip}" "${user}" "$(geo_for "${ip}")"
    done
else
    echo "  (none in this window)"
fi
echo

# --- Section 5: fail2ban status, if installed ---
echo "------ fail2ban status ------"
if command -v fail2ban-client >/dev/null 2>&1; then
    fail2ban-client status sshd 2>/dev/null || echo "  (fail2ban installed but sshd jail not active/found)"
else
    echo "  fail2ban not installed"
fi
echo

# `status` only lists *currently* active bans; the ban history (including bans that have
# since expired) lives in fail2ban's own journal.
echo "------ fail2ban ban events (this window) ------"
BAN_LINES="$(journalctl -u fail2ban --since "${SINCE}" -o short-iso 2>/dev/null \
    | { grep -oE '^[0-9T:+-]+ .* NOTICE +\[[^]]+\] (Ban|Unban|Restore Ban) ([0-9]{1,3}\.){3}[0-9]{1,3}' || true; })"
if [[ -n "${BAN_LINES}" ]]; then
    printf '%s\n' "${BAN_LINES}" | while read -r line; do
        ts="$(awk '{print $1}' <<<"${line}" | sed 's/T/ /')"
        action="$( { grep -oE '(Ban|Unban|Restore Ban) ([0-9]{1,3}\.){3}[0-9]{1,3}$' <<<"${line}" || true; } | sed -E 's/ [0-9.]+$//')"
        ip="$( { grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}$' <<<"${line}" || true; } )"
        if [[ "${action}" == Unban ]]; then
            printf "  %s  %-11s  %s\n" "${ts}" "${action}" "${ip}"
        else
            printf "  %s  %-11s  %-15s  %s\n" "${ts}" "${action}" "${ip}" "$(geo_for "${ip}")"
        fi
    done
else
    echo "  (no ban/unban events in this window, or fail2ban journal unavailable)"
fi
echo

# --- Section 6: optional geolocation of top offending IPs ---
echo "------ Geolocation of top offending IPs (optional) ------"
echo "  Source: ${GEOIP_URL}"
if command -v curl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1 && [[ -n "${FAILED_LINES}" ]]; then
    printf '%s\n' "${FAILED_LINES}" \
        | { grep -oE 'from ([0-9]{1,3}\.){3}[0-9]{1,3}' || true; } \
        | awk '{print $2}' \
        | sort -u | head -n "${TOP_N}" \
        | while read -r ip; do
            geo="$(curl -s --max-time 5 "${GEOIP_URL}/${ip}" 2>/dev/null \
                | jq -r '[.city, .stateprov, .country, .continent]
                         | map(select(. != null and . != ""))
                         | if length == 0 then "no data"
                           else join(", ") end' 2>/dev/null || true)"
            [[ -z "${geo}" ]] && geo="lookup failed"
            echo "  ${ip}: ${geo}"
          done || true
else
    echo "  curl/jq not installed, or no offending IPs to look up"
fi
echo

echo "=================================================================="
echo " Report saved to: ${REPORT_FILE}"
echo "=================================================================="
} | tee "${REPORT_FILE}"
