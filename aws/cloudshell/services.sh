#!/bin/bash
# Full AWS EC2 resource inventory - us-east-1 only, with tags
# Run in AWS CloudShell. Covers: Instances, Key Pairs, Volumes, Elastic IPs,
# Internet Gateways, NAT Gateways, Security Groups, VPCs, Subnets,
# Snapshots, Load Balancers, AMIs (owned), Placement Groups

set -uo pipefail

BOLD="\033[1m"
CYAN="\033[36m"
YELLOW="\033[33m"
GREEN="\033[32m"
RESET="\033[0m"

REGION="us-east-1"
GRAND_TOTAL=0

divider() { printf '%0.s-' {1..170}; printf '\n'; }

section() {
  echo ""
  echo -e "${CYAN}${BOLD}██ $1${RESET}"
  divider
}

count_msg() {
  GRAND_TOTAL=$((GRAND_TOTAL + $1))
  echo -e "${GREEN}  ↳ $1 $2${RESET}"
}

echo ""
echo -e "${BOLD}${YELLOW}╔══════════════════════════════════════════════╗"
echo -e "║       AWS EC2 Full Resource Inventory        ║"
echo -e "╚══════════════════════════════════════════════╝${RESET}"
echo "  Account: $(aws sts get-caller-identity --query Account --output text)"
echo "  User:    $(aws sts get-caller-identity --query Arn --output text)"
echo "  Region:  $REGION"
echo "  Time:    $(date -u '+%Y-%m-%d %H:%M UTC')"

# -------------------------------------------------------------
# KEY PAIRS
# -------------------------------------------------------------
section "KEY PAIRS"
printf "  %-28s %-10s %-22s %-14s %s\n" "NAME" "TYPE" "FINGERPRINT" "CREATED" "TAGS"
divider
COUNT=0
while IFS=$'\t' read -r NAME TYPE FP CREATED TAGS; do
  TAGS_FMT=$(echo "$TAGS" | tr ',' '\n' | grep -E '^(Name|ClusterName|Role)=' | tr '\n' ',' | sed 's/,$//')
  printf "  %-28s %-10s %-22s %-14s %s\n" \
    "$NAME" "$TYPE" "${FP:0:20}" "${CREATED:0:10}" "$TAGS_FMT"
  COUNT=$((COUNT + 1))
done < <(aws ec2 describe-key-pairs \
  --region "$REGION" \
  --query "KeyPairs[].[KeyName, KeyType, KeyFingerprint, CreateTime||'N/A', join(',', Tags[*].join('=',[Key,Value]))||'']" \
  --output text 2>/dev/null || true)
count_msg $COUNT "key pair(s)"

# -------------------------------------------------------------
# EC2 INSTANCES
# -------------------------------------------------------------
section "EC2 INSTANCES"
printf "  %-22s %-24s %-14s %-10s %-16s %-16s %-20s %s\n" \
  "INSTANCE ID" "NAME" "TYPE" "STATE" "PUBLIC IP" "PRIVATE IP" "LAUNCHED" "TAGS"
divider
COUNT=0
while IFS=$'\t' read -r ID NAME TYPE STATE PUB PRIV LAUNCH TAGS; do
  TAGS_FMT=$(echo "$TAGS" | tr ',' '\n' | grep -E '^(Name|ClusterName|Role)=' | tr '\n' ',' | sed 's/,$//')
  printf "  %-22s %-24s %-14s %-10s %-16s %-16s %-20s %s\n" \
    "$ID" "$NAME" "$TYPE" "$STATE" "$PUB" "$PRIV" "${LAUNCH:0:19}" "$TAGS_FMT"
  COUNT=$((COUNT + 1))
done < <(aws ec2 describe-instances \
  --region "$REGION" \
  --query "Reservations[].Instances[].[InstanceId, Tags[?Key=='Name']|[0].Value||'(no name)', InstanceType, State.Name, PublicIpAddress||'-', PrivateIpAddress||'-', LaunchTime, join(',', Tags[*].join('=',[Key,Value]))||'']" \
  --output text 2>/dev/null || true)
count_msg $COUNT "instance(s)"

# -------------------------------------------------------------
# EBS VOLUMES
# -------------------------------------------------------------
section "EBS VOLUMES"
printf "  %-24s %-20s %-8s %-8s %-10s %-20s %-22s %s\n" \
  "VOLUME ID" "NAME" "SIZE(GB)" "TYPE" "STATE" "AZ" "ATTACHED TO" "TAGS"
divider
COUNT=0
while IFS=$'\t' read -r VID VNAME SIZE VTYPE VSTATE AZ ATTCH TAGS; do
  TAGS_FMT=$(echo "$TAGS" | tr ',' '\n' | grep -E '^(Name|ClusterName|Role)=' | tr '\n' ',' | sed 's/,$//')
  printf "  %-24s %-20s %-8s %-8s %-10s %-20s %-22s %s\n" \
    "$VID" "$VNAME" "$SIZE" "$VTYPE" "$VSTATE" "$AZ" "$ATTCH" "$TAGS_FMT"
  COUNT=$((COUNT + 1))
done < <(aws ec2 describe-volumes \
  --region "$REGION" \
  --query "Volumes[].[VolumeId, Tags[?Key=='Name']|[0].Value||'(no name)', Size, VolumeType, State, AvailabilityZone, Attachments[0].InstanceId||'-', join(',', Tags[*].join('=',[Key,Value]))||'']" \
  --output text 2>/dev/null || true)
count_msg $COUNT "volume(s)"

# -------------------------------------------------------------
# SNAPSHOTS (owned)
# -------------------------------------------------------------
section "SNAPSHOTS (owned by this account)"
printf "  %-24s %-20s %-8s %-10s %-22s %-30s %s\n" \
  "SNAPSHOT ID" "NAME" "SIZE(GB)" "STATE" "STARTED" "DESCRIPTION" "TAGS"
divider
COUNT=0
while IFS=$'\t' read -r SID SNAME SIZE SSTATE STIME DESC TAGS; do
  TAGS_FMT=$(echo "$TAGS" | tr ',' '\n' | grep -E '^(Name|ClusterName|Role)=' | tr '\n' ',' | sed 's/,$//')
  printf "  %-24s %-20s %-8s %-10s %-22s %-30s %s\n" \
    "$SID" "$SNAME" "$SIZE" "$SSTATE" "${STIME:0:19}" "${DESC:0:28}" "$TAGS_FMT"
  COUNT=$((COUNT + 1))
done < <(aws ec2 describe-snapshots \
  --region "$REGION" \
  --owner-ids self \
  --query "Snapshots[].[SnapshotId, Tags[?Key=='Name']|[0].Value||'(no name)', VolumeSize, State, StartTime, Description||'-', join(',', Tags[*].join('=',[Key,Value]))||'']" \
  --output text 2>/dev/null || true)
count_msg $COUNT "snapshot(s)"

# -------------------------------------------------------------
# ELASTIC IPs
# -------------------------------------------------------------
section "ELASTIC IPs"
printf "  %-18s %-26s %-20s %-22s %-22s %s\n" \
  "PUBLIC IP" "ALLOCATION ID" "NAME" "INSTANCE ID" "ENI ID" "TAGS"
divider
COUNT=0
while IFS=$'\t' read -r IP ALLOC NAME INST ENI TAGS; do
  TAGS_FMT=$(echo "$TAGS" | tr ',' '\n' | grep -E '^(Name|ClusterName|Role)=' | tr '\n' ',' | sed 's/,$//')
  printf "  %-18s %-26s %-20s %-22s %-22s %s\n" \
    "$IP" "$ALLOC" "$NAME" "$INST" "$ENI" "$TAGS_FMT"
  COUNT=$((COUNT + 1))
done < <(aws ec2 describe-addresses \
  --region "$REGION" \
  --query "Addresses[].[PublicIp, AllocationId, Tags[?Key=='Name']|[0].Value||'(no name)', InstanceId||'-', NetworkInterfaceId||'-', join(',', Tags[*].join('=',[Key,Value]))||'']" \
  --output text 2>/dev/null || true)
count_msg $COUNT "Elastic IP(s)"

# -------------------------------------------------------------
# INTERNET GATEWAYS
# -------------------------------------------------------------
section "INTERNET GATEWAYS"
printf "  %-24s %-24s %-24s %-12s %s\n" "IGW ID" "NAME" "VPC ID" "STATE" "TAGS"
divider
COUNT=0
while IFS=$'\t' read -r IGWID NAME VPC STATE TAGS; do
  TAGS_FMT=$(echo "$TAGS" | tr ',' '\n' | grep -E '^(Name|ClusterName|Role)=' | tr '\n' ',' | sed 's/,$//')
  printf "  %-24s %-24s %-24s %-12s %s\n" "$IGWID" "$NAME" "$VPC" "$STATE" "$TAGS_FMT"
  COUNT=$((COUNT + 1))
done < <(aws ec2 describe-internet-gateways \
  --region "$REGION" \
  --query "InternetGateways[].[InternetGatewayId, Tags[?Key=='Name']|[0].Value||'(no name)', Attachments[0].VpcId||'-', Attachments[0].State||'-', join(',', Tags[*].join('=',[Key,Value]))||'']" \
  --output text 2>/dev/null || true)
count_msg $COUNT "Internet Gateway(s)"

# -------------------------------------------------------------
# NAT GATEWAYS
# -------------------------------------------------------------
section "NAT GATEWAYS"
printf "  %-24s %-20s %-24s %-24s %-12s %-16s %s\n" \
  "NAT GW ID" "NAME" "VPC ID" "SUBNET ID" "STATE" "PUBLIC IP" "TAGS"
divider
COUNT=0
while IFS=$'\t' read -r NID NNAME VPC SUBNET NSTATE PIP TAGS; do
  TAGS_FMT=$(echo "$TAGS" | tr ',' '\n' | grep -E '^(Name|ClusterName|Role)=' | tr '\n' ',' | sed 's/,$//')
  printf "  %-24s %-20s %-24s %-24s %-12s %-16s %s\n" \
    "$NID" "$NNAME" "$VPC" "$SUBNET" "$NSTATE" "$PIP" "$TAGS_FMT"
  COUNT=$((COUNT + 1))
done < <(aws ec2 describe-nat-gateways \
  --region "$REGION" \
  --query "NatGateways[].[NatGatewayId, Tags[?Key=='Name']|[0].Value||'(no name)', VpcId, SubnetId, State, NatGatewayAddresses[0].PublicIp||'-', join(',', Tags[*].join('=',[Key,Value]))||'']" \
  --output text 2>/dev/null || true)
count_msg $COUNT "NAT Gateway(s)"

# -------------------------------------------------------------
# SECURITY GROUPS
# -------------------------------------------------------------
section "SECURITY GROUPS"
printf "  %-24s %-30s %-24s %-40s %s\n" "SG ID" "NAME" "VPC ID" "DESCRIPTION" "TAGS"
divider
COUNT=0
while IFS=$'\t' read -r SGID SGNAME VPC DESC TAGS; do
  TAGS_FMT=$(echo "$TAGS" | tr ',' '\n' | grep -E '^(Name|ClusterName|Role)=' | tr '\n' ',' | sed 's/,$//')
  printf "  %-24s %-30s %-24s %-40s %s\n" \
    "$SGID" "$SGNAME" "$VPC" "${DESC:0:38}" "$TAGS_FMT"
  COUNT=$((COUNT + 1))
done < <(aws ec2 describe-security-groups \
  --region "$REGION" \
  --query "SecurityGroups[].[GroupId, GroupName, VpcId||'-', Description, join(',', Tags[*].join('=',[Key,Value]))||'']" \
  --output text 2>/dev/null || true)
count_msg $COUNT "Security Group(s)"

# -------------------------------------------------------------
# VPCs
# -------------------------------------------------------------
section "VPCs"
printf "  %-24s %-24s %-20s %-10s %-8s %s\n" "VPC ID" "NAME" "CIDR" "STATE" "DEFAULT" "TAGS"
divider
COUNT=0
while IFS=$'\t' read -r VID VNAME CIDR VSTATE ISDEF TAGS; do
  TAGS_FMT=$(echo "$TAGS" | tr ',' '\n' | grep -E '^(Name|ClusterName|Role)=' | tr '\n' ',' | sed 's/,$//')
  printf "  %-24s %-24s %-20s %-10s %-8s %s\n" \
    "$VID" "$VNAME" "$CIDR" "$VSTATE" "$ISDEF" "$TAGS_FMT"
  COUNT=$((COUNT + 1))
done < <(aws ec2 describe-vpcs \
  --region "$REGION" \
  --query "Vpcs[].[VpcId, Tags[?Key=='Name']|[0].Value||'(no name)', CidrBlock, State, IsDefault, join(',', Tags[*].join('=',[Key,Value]))||'']" \
  --output text 2>/dev/null || true)
count_msg $COUNT "VPC(s)"

# -------------------------------------------------------------
# SUBNETS
# -------------------------------------------------------------
section "SUBNETS"
printf "  %-26s %-22s %-24s %-18s %-18s %-8s %-14s %s\n" \
  "SUBNET ID" "NAME" "VPC ID" "CIDR" "AZ" "STATE" "AUTO-PUBLIC-IP" "TAGS"
divider
COUNT=0
while IFS=$'\t' read -r SID SNAME VPC CIDR AZ SSTATE AUTOIP TAGS; do
  TAGS_FMT=$(echo "$TAGS" | tr ',' '\n' | grep -E '^(Name|ClusterName|Role)=' | tr '\n' ',' | sed 's/,$//')
  printf "  %-26s %-22s %-24s %-18s %-18s %-8s %-14s %s\n" \
    "$SID" "$SNAME" "$VPC" "$CIDR" "$AZ" "$SSTATE" "$AUTOIP" "$TAGS_FMT"
  COUNT=$((COUNT + 1))
done < <(aws ec2 describe-subnets \
  --region "$REGION" \
  --query "Subnets[].[SubnetId, Tags[?Key=='Name']|[0].Value||'(no name)', VpcId, CidrBlock, AvailabilityZone, State, MapPublicIpOnLaunch, join(',', Tags[*].join('=',[Key,Value]))||'']" \
  --output text 2>/dev/null || true)
count_msg $COUNT "Subnet(s)"

# -------------------------------------------------------------
# AMIs (owned)
# -------------------------------------------------------------
section "AMIs (owned by this account)"
printf "  %-24s %-36s %-10s %-20s %-8s %s\n" \
  "AMI ID" "NAME" "STATE" "CREATED" "ARCH" "TAGS"
divider
COUNT=0
while IFS=$'\t' read -r AID ANAME ASTATE ACREATED ARCH TAGS; do
  TAGS_FMT=$(echo "$TAGS" | tr ',' '\n' | grep -E '^(Name|ClusterName|Role)=' | tr '\n' ',' | sed 's/,$//')
  printf "  %-24s %-36s %-10s %-20s %-8s %s\n" \
    "$AID" "${ANAME:0:34}" "$ASTATE" "${ACREATED:0:19}" "$ARCH" "$TAGS_FMT"
  COUNT=$((COUNT + 1))
done < <(aws ec2 describe-images \
  --region "$REGION" \
  --owners self \
  --query "Images[].[ImageId, Name, State, CreationDate, Architecture, join(',', Tags[*].join('=',[Key,Value]))||'']" \
  --output text 2>/dev/null || true)
count_msg $COUNT "AMI(s)"

# -------------------------------------------------------------
# LOAD BALANCERS (ELBv2)
# -------------------------------------------------------------
section "LOAD BALANCERS (ELBv2)"
printf "  %-30s %-12s %-16s %-12s %s\n" "NAME" "TYPE" "SCHEME" "STATE" "DNS"
divider
COUNT=0
while IFS=$'\t' read -r LNAME LTYPE LSCHEME LSTATE LDNS; do
  printf "  %-30s %-12s %-16s %-12s %s\n" \
    "$LNAME" "$LTYPE" "$LSCHEME" "$LSTATE" "${LDNS:0:70}"
  COUNT=$((COUNT + 1))
done < <(aws elbv2 describe-load-balancers \
  --region "$REGION" \
  --query "LoadBalancers[].[LoadBalancerName, Type, Scheme, State.Code, DNSName]" \
  --output text 2>/dev/null || true)
count_msg $COUNT "Load Balancer(s)"

# -------------------------------------------------------------
# PLACEMENT GROUPS
# -------------------------------------------------------------
section "PLACEMENT GROUPS"
printf "  %-30s %-14s %-12s %s\n" "NAME" "STRATEGY" "STATE" "GROUP ID"
divider
COUNT=0
while IFS=$'\t' read -r PGNAME PGSTRAT PGSTATE PGID; do
  printf "  %-30s %-14s %-12s %s\n" "$PGNAME" "$PGSTRAT" "$PGSTATE" "$PGID"
  COUNT=$((COUNT + 1))
done < <(aws ec2 describe-placement-groups \
  --region "$REGION" \
  --query "PlacementGroups[].[GroupName, Strategy, State, GroupId]" \
  --output text 2>/dev/null || true)
count_msg $COUNT "Placement Group(s)"

# -------------------------------------------------------------
# GRAND TOTAL
# -------------------------------------------------------------
echo ""
divider
echo -e "${BOLD}${GREEN}  GRAND TOTAL: $GRAND_TOTAL resource(s) in $REGION${RESET}"
divider
echo ""