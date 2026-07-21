#!/bin/bash
# iptables-explain.sh

MINIKUBE_IP="${MINIKUBE_IP:-$(minikube ip 2>/dev/null)}"
IFACE="${IFACE:-$(ip route get 8.8.8.8 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev") print $(i+1)}' | head -1)}"
SEP="─────────────────────────────────────────────"

section() { echo ""; echo "╔══ $1"; echo ""; }
good()    { echo "  ✓  $1"; }
warn()    { echo "  ⚠  $1"; }
bad()     { echo "  ✗  $1"; }
info()    { echo "     $1"; }

# ── token extractor (no grep -P) ─────────────────────────────
token_after() {
  local key="$1" rule="$2"
  echo "$rule" | awk -v k="$key" '{for(i=1;i<=NF;i++) if($i==k) {print $(i+1); exit}}'
}

has() { echo "$1" | grep -qF "$2"; }

# ── RAW ──────────────────────────────────────────────────────

explain_raw() {
  local rule="$1"
  local dst
  dst=$(token_after "-d" "$rule")

  if has "$rule" "-j DROP"; then
    if has "$rule" "! -i docker0" || has "$rule" "! --in-interface docker0"; then
      warn "RAW DROP for $dst (not from docker0)"
      info "Drops spoofed packets pretending to be from minikube/docker."
      info "Expected — added automatically by Docker/minikube as a security measure."
    elif has "$rule" "! -i lo"; then
      local dport
      dport=$(token_after "--dport" "$rule")
      warn "RAW DROP for $dst port $dport (not from lo)"
      info "Blocks external access to a localhost-mapped Docker port ($dport)."
      info "Expected — Docker maps container ports to 127.0.0.1 to prevent"
      info "unintended external exposure while still allowing local access."
    else
      bad "RAW DROP rule: $rule"
      info "Drops packets very early. Verify this is intentional."
    fi
  else
    info "Other RAW rule: $rule"
  fi
}

# ── INPUT ────────────────────────────────────────────────────

explain_input() {
  local rule="$1"
  local dport
  dport=$(token_after "--dport" "$rule")

  if has "$rule" "RELATED,ESTABLISHED"; then
    good "Allow established/related inbound"
    info "Lets reply packets for connections you initiated come back in. Essential."
  elif has "$rule" "icmp" && has "$rule" "ACCEPT"; then
    good "Allow ICMP (ping)"
    info "Lets you ping the host and receive ICMP error messages."
  elif has "$rule" "-i lo"; then
    good "Allow loopback"
    info "Permits local services to talk to each other via 127.0.0.1."
  elif has "$rule" "ACCEPT" && [ "$dport" = "22" ]; then
    good "Allow SSH (port 22)"
    info "Keeps remote access to the host open."
  elif has "$rule" "ACCEPT" && [ -n "$dport" ]; then
    good "Allow inbound port $dport"
    info "Explicitly permits new connections on port $dport."
  elif has "$rule" "REJECT" || has "$rule" "DROP"; then
    warn "Default deny — blocks anything not matched above"
    info "Normal for a restrictive host firewall. All unmatched traffic is dropped."
  else
    info "Other INPUT rule: $rule"
  fi
}

# ── FORWARD ──────────────────────────────────────────────────

explain_forward() {
  local rule="$1"
  local in_if out_if src dst dport

  in_if=$(token_after "-i" "$rule")
  out_if=$(token_after "-o" "$rule")
  src=$(token_after "-s" "$rule")
  dst=$(token_after "-d" "$rule")
  dport=$(token_after "--dport" "$rule")

  if has "$rule" "REJECT" || has "$rule" "DROP"; then
    bad "REJECT/DROP rule in FORWARD"
    info "Blocks all forwarding not matched by earlier rules."
    info "If this appears BEFORE your ACCEPT rules, nothing gets forwarded."
    info "→ Delete: sudo iptables -D FORWARD -j REJECT --reject-with icmp-host-prohibited"
    return
  fi

  # Interface + stateful (combined rule)
  if [ -n "$in_if" ] && [ -n "$out_if" ] && has "$rule" "RELATED,ESTABLISHED"; then
    good "Stateful return: $in_if → $out_if (RELATED,ESTABLISHED only)"
    info "Allows reply packets back through from $out_if to $in_if."
    info "Pairs with the ACCEPT rule for the same interface direction."
    return
  fi

  # Interface-only ACCEPT
  if [ -n "$in_if" ] && [ -n "$out_if" ]; then
    good "Interface forwarding: $in_if → $out_if (all new traffic)"
    if [ "$in_if" = "docker0" ] && [ "$out_if" = "$IFACE" ]; then
      info "Allows minikube pods to initiate outbound connections (internet access)."
    elif [ "$in_if" = "$IFACE" ] && [ "$out_if" = "docker0" ]; then
      info "Allows external traffic to enter minikube pods (inbound)."
    else
      info "Custom interface pair — verify this is intentional."
    fi
    return
  fi

  # Stateful only (no interface)
  if has "$rule" "RELATED,ESTABLISHED"; then
    good "Global stateful return traffic"
    info "Allows reply packets for any established connection. Essential."
    return
  fi

  # CIDR-based
  if [ -n "$src" ] && has "$rule" "ACCEPT"; then
    good "ACCEPT from $src${dst:+ to $dst}"
    info "Explicitly permits forwarding from this source network."
    [ -n "$dst" ] && info "Destination restricted to $dst."
    return
  fi

  info "Other FORWARD rule: $rule"
}

# ── NAT ──────────────────────────────────────────────────────

explain_nat() {
  local rule="$1"
  local src dst dport dest

  src=$(token_after "-s"   "$rule")
  dst=$(token_after "-d"   "$rule")
  dport=$(token_after "--dport" "$rule")
  dest=$(token_after "--to-destination" "$rule")

  if has "$rule" "MASQUERADE"; then
    local scope="${src:-all subnets}"
    good "MASQUERADE — source NAT for $scope"
    info "Rewrites source IP to the host's IP as packets leave."
    info "Required for $scope to reach the internet."
    info "Without this, reply packets have no valid return address."
    return
  fi

  if has "$rule" "-j DOCKER"; then
    good "Jump to DOCKER chain"
    info "Docker's internal hook — it manages its own DNAT port mappings here."
    return
  fi

  if has "$rule" "DNAT"; then
    good "DNAT port $dport → $dest"
    info "Incoming TCP on port $dport gets redirected to $dest."
    if [ "$dport" = "30080" ]; then
      info "This is your ingress NodePort — external HTTP traffic → minikube."
    fi
    return
  fi

  info "Other NAT rule: $rule"
}

explain_docker_nat() {
  local rule="$1"
  local dport dest
  dport=$(token_after "--dport" "$rule")
  dest=$(token_after "--to-destination" "$rule")

  if has "$rule" "DNAT"; then
    local svc=""
    case "$dest" in
      *:22)    svc=" (SSH into minikube)" ;;
      *:2376)  svc=" (Docker daemon API)" ;;
      *:5000)  svc=" (image registry)" ;;
      *:8443)  svc=" (Kubernetes API server)" ;;
      *:32443) svc=" (Kubernetes dashboard HTTPS)" ;;
    esac
    good "Docker DNAT: localhost:$dport → $dest$svc"
    info "Minikube service accessible on this host at 127.0.0.1:$dport."
    return
  fi

  info "Other DOCKER chain rule: $rule"
}

# ════════════════════════════════════════════════════════════
#  MAIN
# ════════════════════════════════════════════════════════════

section "System configuration"
val=$(sysctl -n net.ipv4.ip_forward 2>/dev/null)
if [ "$val" = "1" ]; then
  good "net.ipv4.ip_forward = 1"
  info "IP forwarding is ON — the kernel routes packets between interfaces."
else
  bad "net.ipv4.ip_forward = $val (expected 1)"
  info "The kernel will silently drop all forwarded packets."
  info "→ Fix: echo 'net.ipv4.ip_forward = 1' | sudo tee /etc/sysctl.d/99-ip-forward.conf"
  info "        sudo sysctl -p /etc/sysctl.d/99-ip-forward.conf"
fi
echo ""
info "Detected interface : ${IFACE:-unknown}"
info "Detected minikube  : ${MINIKUBE_IP:-not found}"

section "RAW table (earliest filter stage — before conntrack)"
sudo iptables -t raw -S | grep "^-A" | while IFS= read -r rule; do
  chain=$(echo "$rule" | awk '{print $2}')
  echo "  [$chain] $rule"
  explain_raw "$rule"
  echo ""
done

section "INPUT chain (traffic destined for this host)"
sudo iptables -S INPUT | grep "^-A" | while IFS= read -r rule; do
  echo "  $rule"
  explain_input "$rule"
  echo ""
done

section "FORWARD chain (traffic passing through this host)"

# Warn on ordering issue
all_fwd=$(sudo iptables -S FORWARD | grep "^-A")
reject_line=$(echo "$all_fwd" | grep -n "REJECT\|DROP" | head -1)
accept_line=$(echo "$all_fwd" | grep -n "ACCEPT"       | head -1)
reject_pos=$(echo "$reject_line" | cut -d: -f1)
accept_pos=$(echo "$accept_line" | cut -d: -f1)

if [ -n "$reject_pos" ] && [ -n "$accept_pos" ] && [ "$reject_pos" -lt "$accept_pos" ]; then
  bad "ORDERING PROBLEM: REJECT at line $reject_pos comes before first ACCEPT at line $accept_pos"
  info "iptables stops at the first matching rule — your ACCEPT rules are unreachable."
  info "→ Delete the REJECT: sudo iptables -D FORWARD -j REJECT --reject-with icmp-host-prohibited"
  echo ""
fi

echo "$all_fwd" | nl -ba | while IFS= read -r line; do
  num=$(echo "$line" | awk '{print $1}')
  rule=$(echo "$line" | cut -f2-)
  echo "  [$num] $rule"
  explain_forward "$rule"
  echo ""
done

section "NAT — PREROUTING (rewrite destination before routing decision)"
sudo iptables -t nat -S PREROUTING | grep "^-A" | while IFS= read -r rule; do
  echo "  $rule"
  explain_nat "$rule"
  echo ""
done

section "NAT — POSTROUTING (rewrite source after routing decision)"
sudo iptables -t nat -S POSTROUTING | grep "^-A" | while IFS= read -r rule; do
  echo "  $rule"
  explain_nat "$rule"
  echo ""
done

section "NAT — DOCKER chain (Docker-managed port mappings)"
sudo iptables -t nat -S DOCKER | grep "^-A" | while IFS= read -r rule; do
  echo "  $rule"
  explain_docker_nat "$rule"
  echo ""
done

section "Persistence"
if [ -f /etc/sysconfig/iptables ]; then
  saved_count=$(grep -c "^-A" /etc/sysconfig/iptables)
  live_count=$(sudo iptables-save | grep -c "^-A")
  good "/etc/sysconfig/iptables exists"
  info "Saved rules : $saved_count"
  info "Live rules  : $live_count"
  if [ "$saved_count" -ne "$live_count" ]; then
    warn "Counts differ — live rules will be lost on reboot"
    info "→ Save now: sudo iptables-save | sudo tee /etc/sysconfig/iptables"
  else
    good "Saved and live rules match"
  fi
else
  bad "/etc/sysconfig/iptables not found"
  info "Rules will not survive a reboot."
  info "→ Save: sudo iptables-save | sudo tee /etc/sysconfig/iptables"
fi

echo ""
echo "$SEP"
echo "Done."
echo "$SEP"
echo ""