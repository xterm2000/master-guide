## simple ports scanning

```bash
sudo ss -tulpn | grep 11434

# sudo dnf install lsof -y
sudo lsof -i :11434
sudo fuser 11434/tcp
```

## iprange scan 
```bash
# Ping scan only (no port scan) - fast
nmap -sn 100.99.229.0/24

# Show only live hosts
nmap -sn 100.99.229.0/24 | grep "Nmap scan report"

# Specific range
nmap -sn 100.99.229.100-110
```

```bash
# Install
dnf install fping -y

# Ping entire subnet
fping -a -g 100.99.229.0/24 2>/dev/null

# Specific range
fping -a -g 100.99.229.100 100.99.229.110 2>/dev/null
```

```bash
for i in {1..254}; do
  ping -c1 -W1 100.99.229.$i &>/dev/null && echo "100.99.229.$i is up" &
done
wait
```

 
