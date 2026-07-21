```bash
#!/bin/bash

echo "============================================"
echo " iptables Configuration Report"
echo " $(date)"
echo "============================================"

echo ""
echo "--- iptables service status ---"
systemctl is-active iptables 2>/dev/null || echo "iptables service not found"

echo ""
echo "--- firewalld status ---"
systemctl is-active firewalld 2>/dev/null || echo "firewalld service not found"

echo ""
echo "--- filter table (INPUT/OUTPUT/FORWARD) ---"
sudo iptables -L -v -n --line-numbers

echo ""
echo "--- nat table ---"
sudo iptables -t nat -L -v -n --line-numbers

echo ""
echo "--- mangle table ---"
sudo iptables -t mangle -L -v -n --line-numbers

echo ""
echo "--- default policies ---"
sudo iptables -L | grep "^Chain" 

echo ""
echo "--- ip6tables filter ---"
sudo ip6tables -L -v -n --line-numbers

echo ""
echo "--- saved rules (/etc/sysconfig/iptables) ---"
if [ -f /etc/sysconfig/iptables ]; then
   sudo cat /etc/sysconfig/iptables
else
    echo "No saved rules found."
fi

echo ""
echo "============================================"
echo " Done"
echo "============================================"
```