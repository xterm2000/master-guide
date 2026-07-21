#!/usr/bin/env bash
# =============================================================================
# kube_scale.sh - Scale all deployments in a namespace up or down
#
# Usage:
#   kube_scale.sh <namespace> <up|down>
#
# Actions:
#   down  Save replica counts to <namespace>_replica_count.ini, then
#         scale every deployment to 0.
#   up    Read replica counts from <namespace>_replica_count.ini and
#         restore each deployment to its saved count.
#
# The .ini file is written next to this script (or the directory set by
# KUBE_SCALE_DIR env var).
# =============================================================================

set -euo pipefail

# -- helpers ------------------------------------------------------------------

RED=$'\033[0;31m'
YEL=$'\033[1;33m'
GRN=$'\033[0;32m'
CYN=$'\033[0;36m'
RST=$'\033[0m'

info()    { printf "${CYN}[INFO]${RST}  %s\n" "$*"; }
success() { printf "${GRN}[OK]${RST}    %s\n" "$*"; }
warn()    { printf "${YEL}[WARN]${RST}  %s\n" "$*"; }
error()   { printf "${RED}[ERROR]${RST} %s\n" "$*" >&2; }
die()     { error "$*"; exit 1; }

usage() {
  printf "\n"
  printf "${CYN}Usage:${RST}\n"
  printf "  %s <namespace> <up|down>\n" "$(basename "$0")"
  printf "\n"
  printf "${CYN}Arguments:${RST}\n"
  printf "  namespace   Kubernetes namespace to operate on\n"
  printf "  up          Restore deployments to previously saved replica counts\n"
  printf "  down        Save replica counts and scale all deployments to zero\n"
  printf "\n"
  printf "${CYN}Environment:${RST}\n"
  printf "  KUBE_SCALE_DIR   Directory where .ini files are stored\n"
  printf "                   (default: same directory as this script)\n"
  printf "  KUBECONFIG       Standard kubectl config override\n"
  printf "\n"
  printf "${CYN}Examples:${RST}\n"
  printf "  %s g124 down    # scale g124 to zero, save counts\n" "$(basename "$0")"
  printf "  %s g124 up      # restore g124 from saved counts\n" "$(basename "$0")"
  printf "\n"
  exit 1
}

# -- argument validation -------------------------------------------------------

[[ $# -ne 2 ]] && { error "Expected exactly 2 arguments, got $#."; usage; }

NAMESPACE="$1"
ACTION="${2,,}"   # lowercase

[[ "$ACTION" == "up" || "$ACTION" == "down" ]] || {
  error "Second argument must be 'up' or 'down', got: '$2'"
  usage
}

# -- paths --------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STORE_DIR="${KUBE_SCALE_DIR:-$SCRIPT_DIR}"
INI_FILE="${STORE_DIR}/${NAMESPACE}_replica_count.ini"

# -- preflight checks ---------------------------------------------------------

command -v kubectl &>/dev/null || die "'kubectl' not found in PATH. Please install it first."

# Verify the namespace exists in the cluster
if ! kubectl get namespace "$NAMESPACE" &>/dev/null; then
  die "Namespace '${NAMESPACE}' does not exist in the current cluster context."
fi

info "Namespace : ${NAMESPACE}"
info "Action    : ${ACTION}"
info "INI file  : ${INI_FILE}"
echo

# -- scale DOWN ---------------------------------------------------------------

scale_down() {
  # Fetch all deployments in the namespace
  mapfile -t DEPLOYMENTS < <(
    kubectl get deployments -n "$NAMESPACE" \
      --no-headers \
      -o custom-columns="NAME:.metadata.name" 2>/dev/null
  )

  if [[ ${#DEPLOYMENTS[@]} -eq 0 ]]; then
    warn "No deployments found in namespace '${NAMESPACE}'. Nothing to do."
    exit 0
  fi

  info "Found ${#DEPLOYMENTS[@]} deployment(s). Saving replica counts…"
  echo

  # Create / overwrite the ini file
  mkdir -p "$STORE_DIR"
  {
    echo "# kube_scale replica snapshot"
    echo "# namespace : ${NAMESPACE}"
    echo "# timestamp : $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    echo
  } > "$INI_FILE"

  local failed=0

  for DEPLOY in "${DEPLOYMENTS[@]}"; do
    REPLICAS=$(
      kubectl get deployment "$DEPLOY" -n "$NAMESPACE" \
        -o jsonpath='{.spec.replicas}' 2>/dev/null
    )

    # jsonpath returns empty string if the field is missing (edge case)
    if [[ -z "$REPLICAS" ]]; then
      warn "Could not read replica count for '${DEPLOY}' - defaulting to 1"
      REPLICAS=1
    fi

    echo "${DEPLOY}=${REPLICAS}" >> "$INI_FILE"
    printf "  %-45s replicas saved: %s\n" "$DEPLOY" "$REPLICAS"

    if kubectl scale deployment "$DEPLOY" -n "$NAMESPACE" --replicas=0 &>/dev/null; then
      printf "  %-45s %b\n" "$DEPLOY" "${GRN}scaled to 0${RST}"
    else
      printf "  %-45s %b\n" "$DEPLOY" "${RED}FAILED to scale${RST}"
      (( failed++ )) || true
    fi
    echo
  done

  success "Replica counts saved to: ${INI_FILE}"

  if [[ $failed -gt 0 ]]; then
    die "${failed} deployment(s) failed to scale. Check the output above."
  fi

  success "All deployments in '${NAMESPACE}' scaled to zero."
}

# -- scale UP -----------------------------------------------------------------

scale_up() {
  [[ -f "$INI_FILE" ]] || die \
    "INI file not found: '${INI_FILE}'.
       Run '$(basename "$0") ${NAMESPACE} down' first to create it."

  info "Reading replica counts from: ${INI_FILE}"
  echo

  local restored=0
  local failed=0
  local skipped=0

  while IFS='=' read -r DEPLOY REPLICAS; do
    # Skip blank lines and comments
    [[ -z "$DEPLOY" || "$DEPLOY" =~ ^# ]] && continue

    # Trim whitespace (handles Windows-style CR too)
    DEPLOY="${DEPLOY//[$'\r\n ']/}"
    REPLICAS="${REPLICAS//[$'\r\n ']/}"

    # Validate replica value is a non-negative integer
    if ! [[ "$REPLICAS" =~ ^[0-9]+$ ]]; then
      warn "Skipping '${DEPLOY}': invalid replica value '${REPLICAS}' in INI file."
      (( skipped++ )) || true
      continue
    fi

    # Check the deployment still exists
    if ! kubectl get deployment "$DEPLOY" -n "$NAMESPACE" &>/dev/null; then
      warn "Deployment '${DEPLOY}' no longer exists in '${NAMESPACE}' - skipping."
      (( skipped++ )) || true
      continue
    fi

    if kubectl scale deployment "$DEPLOY" -n "$NAMESPACE" --replicas="$REPLICAS" &>/dev/null; then
      printf "  %-45s %b\n" "$DEPLOY" "${GRN}restored to ${REPLICAS} replica(s)${RST}"
      (( restored++ )) || true
    else
      printf "  %-45s %b\n" "$DEPLOY" "${RED}FAILED to scale${RST}"
      (( failed++ )) || true
    fi

  done < "$INI_FILE"

  echo
  success "Restored: ${restored}  |  Skipped: ${skipped}  |  Failed: ${failed}"
  
  # Remove INI file after successful restore
  if [[ $failed -eq 0 ]]; then
    rm -f "$INI_FILE" && info "Removed INI file: ${INI_FILE}"
  else
    warn "INI file kept due to failures: ${INI_FILE}"
  fi

  if [[ $failed -gt 0 ]]; then
    die "${failed} deployment(s) failed to scale up."
  fi

  [[ $restored -eq 0 && $skipped -gt 0 ]] && \
    warn "No deployments were restored (all entries skipped)."

  [[ $restored -gt 0 ]] && \
    success "Namespace '${NAMESPACE}' is back up."
}

# -- dispatch ------------------------------------------------------------------

case "$ACTION" in
  down) scale_down ;;
  up)   scale_up   ;;
esac

