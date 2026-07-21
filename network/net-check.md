```bash
#!/bin/bash
# verify-nat-setup.sh

PASS=0
FAIL=0

check() {
  local label="$1"
  local result="$2"
  if [ "$result" = "OK" ]; then
    echo "  [PASS] $label"
    ((PASS++))
  else
    echo "  [FAIL] $label - $result"
    ((FAIL++))
  fi
}

echo ""
echo "=== 1. IP Forwarding ==="

val=$(sysctl -n net.ipv4.ip_forward)
[ "$val" = "1" ] && r="OK" || r="net.ipv4.ip_forward=$val (expected 1)"
check "ip_forward active (runtime)" "$r"

grep -q "net.ipv4.ip_forward = 1" /etc/sysctl.d/99-ip-forward.conf 2>/dev/null \
  && r="OK" || r="not found in /etc/sysctl.d/99-ip-forward.conf"
check "ip_forward persisted (sysctl.d)" "$r"

echo ""
echo "=== 2. iptables-services ==="

rpm -q iptables-services &>/dev/null \
  && r="OK" || r="package not installed"
check "iptables-services installed" "$r"

systemctl is-active iptables &>/dev/null \
  && r="OK" || r="service not active ($(systemctl is-active iptables))"
check "iptables service running" "$r"

systemctl is-enabled iptables &>/dev/null \
  && r="OK" || r="service not enabled on boot"
check "iptables service enabled" "$r"

echo ""
echo "=== 3. NAT / MASQUERADE ==="

sudo iptables -t nat -L POSTROUTING -n | grep -q "MASQUERADE" \
  && r="OK" || r="MASQUERADE rule missing in nat POSTROUTING"
check "MASQUERADE rule" "$r"

echo ""
echo "=== 4. FORWARD Rules ==="

sudo iptables -L FORWARD -n | grep -q "10.0.0.0/8" \
  && r="OK" || r="no FORWARD rules matching 10.0.0.0/8"
check "FORWARD accept 10.0.0.0/8" "$r"

sudo iptables -L FORWARD -n | grep -q "RELATED,ESTABLISHED" \
  && r="OK" || r="RELATED,ESTABLISHED rule missing"
check "FORWARD stateful return traffic" "$r"

echo ""
echo "=== 5. Rules Persisted to Disk ==="

sudo iptables-save | grep -q "MASQUERADE" \
  && r="OK" || r="MASQUERADE not found in iptables-save output"
check "saved rules include MASQUERADE" "$r"

[ -f /etc/sysconfig/iptables ] \
  && r="OK" || r="/etc/sysconfig/iptables file missing"
check "/etc/sysconfig/iptables exists" "$r"

echo ""
echo "=== 6. Egress Connectivity (from this node) ==="

ping -c 2 -W 2 8.8.8.8 &>/dev/null \
  && r="OK" || r="ping to 8.8.8.8 failed"
check "ping 8.8.8.8" "$r"

nc -zw 3 registry-1.docker.io 443 &>/dev/null \
  && r="OK" || r="TCP 443 to registry-1.docker.io failed"
check "TCP 443 to Docker Hub" "$r"

curl -4 --max-time 8 -s -o /dev/null -w "%{http_code}" https://registry-1.docker.io/v2/ | grep -q "200\|401" \
  && r="OK" || r="curl to Docker Hub failed (got: $(curl -4 --max-time 8 -s -o /dev/null -w '%{http_code}' https://registry-1.docker.io/v2/))"
check "curl Docker Hub /v2/" "$r"

echo ""
echo "======================================="
echo "  PASSED: $PASS   FAILED: $FAIL"
echo "======================================="
echo ""

```