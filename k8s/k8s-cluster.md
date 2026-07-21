```bash
#!/usr/bin/env bash
# =============================================================================
# k8s-cluster.sh  -  Bare-metal-sim K8s cluster on AWS
# Nodes: 1 bastion, N control-planes, M workers
# Key  : top-key.pem
# Usage: ./k8s-cluster.sh [create|start|stop|terminate|status]
# =============================================================================

# Exit on any error, treat unset variables as errors, propagate pipe failures
set -euo pipefail

# ---------------------------------------------------------------------------
# ★  CONFIGURATION  -  edit these before first run
# ---------------------------------------------------------------------------
KEY_NAME="top-key"                    # EC2 key pair name (no .pem)
KEY_FILE="$HOME/top-key.pem"         # local path to the .pem

# Leave VPC_ID / SUBNET_ID empty to auto-detect the default VPC
VPC_ID="vpc-0a0a0efde1db4b211"
SUBNET_ID="subnet-063f68414265dfcdc"

# Instance types (bare-metal simulation - burstable is fine for practice)
BASTION_TYPE="t3.small"
CONTROL_TYPE="t3.medium"
WORKER_TYPE="t3.medium"

# Cluster topology - change these to scale up/down
NUM_CONTROL_PLANES="${NC:-1}"  # number of control-plane nodes (1 for single, 3 for HA)
NUM_WORKERS="${NW:-3}"         # number of worker nodes

# OS - Ubuntu 22.04 LTS (amd64). Script auto-detects latest AMI.
# Override here if needed:
# leave empty = auto-detect
# AMI_ID="ami-056244ee7f6e2feb8" # Red Hat Enterprise Linux 8 (RHEL) 8.7
AMI_ID="ami-0f2425d4cce4e97dd" # Rocky linux 9


# Prefer AWS_DEFAULT_REGION env var; fall back to aws CLI profile; then us-east-1
REGION="${AWS_DEFAULT_REGION:-$(aws configure get region 2>/dev/null || echo us-east-1)}"

# Tag used to find instances later - change if you run multiple clusters
TAG_PREFIX="k8s-lab"
# ---------------------------------------------------------------------------

# ANSI color codes for terminal output
RED='\033[0;31m'; GRN='\033[0;32m'; YLW='\033[1;33m'
BLU='\033[0;34m'; CYN='\033[0;36m'; RST='\033[0m'
BOLD='\033[1m'

# Logging helpers - all write to stderr so $(command substitution) captures only data
info()  { echo -e "${BLU}[INFO]${RST}  $*" >&2; }
ok()    { echo -e "${GRN}[OK]${RST}    $*" >&2; }
warn()  { echo -e "${YLW}[WARN]${RST}  $*" >&2; }
die()   { echo -e "${RED}[ERROR]${RST} $*" >&2; exit 1; }
hdr()   { echo -e "\n${BOLD}${CYN}══ $* ══${RST}" >&2; }

# ---------------------------------------------------------------------------
# IDS[]  -  global array of instance IDs for the current cluster
# Call load_ids before any operation that needs them.
# ---------------------------------------------------------------------------
declare -a IDS=()

load_ids() {
    # Default to all non-terminated states; callers can narrow (e.g. "stopped")
    local state_filter="${1:-pending,running,stopping,stopped}"
    local raw
    raw=$(aws ec2 describe-instances \
        --region "$REGION" \
        --filters \
            "Name=tag:Cluster,Values=${TAG_PREFIX}" \
            "Name=instance-state-name,Values=${state_filter}" \
        --query "Reservations[].Instances[].InstanceId" \
        --output text 2>/dev/null | tr -d '\r' || true)
        # tr -d '\r' strips Windows-style carriage returns that some AWS CLI
        # versions emit on certain platforms

    IDS=()
    # read -ra splits on whitespace (handles tabs that --output text produces)
    if [[ -n "$raw" ]]; then
        read -r -a IDS <<< "$raw"
    fi
}

# wait_for_state - uses IDS[] directly; no string-passing, no XML corruption
wait_for_state() {
    local state="$1"
    info "Waiting for ${#IDS[@]} instance(s) to reach: ${BOLD}${state}${RST} …"
    # aws ec2 wait polls every 15 s and times out after 40 attempts (~10 min)
    aws ec2 wait "instance-${state}" \
        --region "$REGION" \
        --instance-ids "${IDS[@]}"
    ok "All instances are ${state}."
}

# Print a human-readable table: Name, ID, type, state, public IP, private IP
print_table() {
    aws ec2 describe-instances \
        --region "$REGION" \
        --instance-ids "${IDS[@]}" \
        --query "Reservations[].Instances[].[Tags[?Key=='Name']|[0].Value,InstanceId,InstanceType,State.Name,PublicIpAddress,PrivateIpAddress]" \
        --output table
}

# ---------------------------------------------------------------------------
# Infrastructure helpers
# ---------------------------------------------------------------------------
resolve_vpc() {
    # Skip detection if both IDs are already configured at the top
    if [[ -n "$VPC_ID" && -n "$SUBNET_ID" ]]; then return; fi
    info "No VPC_ID/SUBNET_ID set - detecting default VPC …"

    VPC_ID=$(aws ec2 describe-vpcs \
        --region "$REGION" \
        --filters "Name=isDefault,Values=true" \
        --query "Vpcs[0].VpcId" --output text)
    [[ "$VPC_ID" == "None" || -z "$VPC_ID" ]] && \
        die "No default VPC found. Set VPC_ID and SUBNET_ID manually at the top of the script."

    # Pick the first default-for-AZ subnet in the detected VPC
    SUBNET_ID=$(aws ec2 describe-subnets \
        --region "$REGION" \
        --filters "Name=vpc-id,Values=${VPC_ID}" \
                  "Name=defaultForAz,Values=true" \
        --query "Subnets[0].SubnetId" --output text)
    [[ "$SUBNET_ID" == "None" || -z "$SUBNET_ID" ]] && \
        die "No default subnet found in VPC ${VPC_ID}."

    ok "VPC: ${VPC_ID}  |  Subnet: ${SUBNET_ID}"
}

resolve_ami() {
    # Skip lookup if AMI_ID is already hard-coded at the top
    if [[ -n "$AMI_ID" ]]; then return; fi
    info "Looking up latest Ubuntu 22.04 LTS AMI in ${REGION} …"
    # Owner 099720109477 is Canonical's official AWS account
    AMI_ID=$(aws ec2 describe-images \
        --region "$REGION" \
        --owners 099720109477 \
        --filters \
            "Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*" \
            "Name=state,Values=available" \
        --query "sort_by(Images,&CreationDate)[-1].ImageId" \
        --output text)
    [[ -z "$AMI_ID" || "$AMI_ID" == "None" ]] && \
        die "Could not find Ubuntu 22.04 AMI. Set AMI_ID manually."
    ok "AMI: ${AMI_ID}"
}

ensure_sg() {
    local sg_name="${TAG_PREFIX}-sg"
    # Try to find an existing SG with this name in the target VPC
    SG_ID=$(aws ec2 describe-security-groups \
        --region "$REGION" \
        --filters "Name=group-name,Values=${sg_name}" \
                  "Name=vpc-id,Values=${VPC_ID}" \
        --query "SecurityGroups[0].GroupId" --output text 2>/dev/null || true)

    if [[ -z "$SG_ID" || "$SG_ID" == "None" ]]; then
        info "Creating security group ${sg_name} …"
        SG_ID=$(aws ec2 create-security-group \
            --region "$REGION" \
            --group-name "$sg_name" \
            --description "k8s-lab cluster SG" \
            --vpc-id "$VPC_ID" \
            --query "GroupId" --output text)

        # SSH from anywhere (restrict to your IP for real clusters)
        aws ec2 authorize-security-group-ingress \
            --region "$REGION" --group-id "$SG_ID" \
            --protocol tcp --port 22 --cidr 0.0.0.0/0 >/dev/null

        # All traffic within the SG - cluster internal comms (CNI, etcd, kubelet…)
        # Self-referencing rule lets nodes talk to each other freely without
        # enumerating individual ports for each K8s component
        aws ec2 authorize-security-group-ingress \
            --region "$REGION" --group-id "$SG_ID" \
            --protocol -1 --source-group "$SG_ID" >/dev/null

        # K8s API server reachable from outside (kubectl, CI, etc.)
        aws ec2 authorize-security-group-ingress \
            --region "$REGION" --group-id "$SG_ID" \
            --protocol tcp --port 6443 --cidr 0.0.0.0/0 >/dev/null

        ok "Security group created: ${SG_ID}"
    else
        ok "Reusing existing security group: ${SG_ID}"
    fi
}

launch_instance() {
    local role="$1" itype="$2" suffix="$3"
    local name="${TAG_PREFIX}-${suffix}"
    info "  Launching ${name} (${itype}) …"

    # 20 GiB gp3 root volume; deleted automatically when instance terminates
    local block_devs='[{"DeviceName":"/dev/sda1","Ebs":{"VolumeSize":20,"VolumeType":"gp3","DeleteOnTermination":true}}]'

    # Tag both the instance and its EBS volume so cost allocation is clear
    # No --associate-public-ip-address: bastion/CP get Elastic IPs, workers stay private
    aws ec2 run-instances \
        --region "$REGION" \
        --image-id "$AMI_ID" \
        --instance-type "$itype" \
        --key-name "$KEY_NAME" \
        --subnet-id "$SUBNET_ID" \
        --security-group-ids "$SG_ID" \
        --no-associate-public-ip-address \
        --block-device-mappings "$block_devs" \
        --tag-specifications \
            "ResourceType=instance,Tags=[{Key=Name,Value=${name}},{Key=Cluster,Value=${TAG_PREFIX}},{Key=Role,Value=${role}}]" \
            "ResourceType=volume,Tags=[{Key=Cluster,Value=${TAG_PREFIX}}]" \
        --query "Instances[0].InstanceId" \
        --output text | tr -d '\r'
    # tr -d '\r' prevents IDs from carrying a carriage return into array slots
}

associate_eip() {
    local instance_id="$1" name="$2"
    info "  Allocating Elastic IP for ${name} …"
    local alloc_id public_ip

    alloc_id=$(aws ec2 allocate-address \
        --region "$REGION" \
        --domain vpc \
        --tag-specifications \
            "ResourceType=elastic-ip,Tags=[{Key=Name,Value=${name}-eip},{Key=Cluster,Value=${TAG_PREFIX}}]" \
        --query "AllocationId" --output text | tr -d '\r')

    aws ec2 associate-address \
        --region "$REGION" \
        --instance-id "$instance_id" \
        --allocation-id "$alloc_id" >/dev/null

    public_ip=$(aws ec2 describe-addresses \
        --region "$REGION" \
        --allocation-ids "$alloc_id" \
        --query "Addresses[0].PublicIp" --output text)

    ok "  ${name} → EIP ${public_ip} (${alloc_id})"
}

release_eips() {
    info "Releasing Elastic IPs for cluster '${TAG_PREFIX}' …"
    local raw alloc_id

    raw=$(aws ec2 describe-addresses \
        --region "$REGION" \
        --filters "Name=tag:Cluster,Values=${TAG_PREFIX}" \
        --query "Addresses[].AllocationId" \
        --output text 2>/dev/null | tr -d '\r' || true)

    if [[ -z "$raw" || "$raw" == "None" ]]; then
        info "No Elastic IPs found for cluster '${TAG_PREFIX}'."
        return
    fi

    for alloc_id in $raw; do
        info "  Releasing ${alloc_id} …"
        aws ec2 release-address --region "$REGION" --allocation-id "$alloc_id" 2>/dev/null && \
            ok "  Released ${alloc_id}." || \
            warn "  Could not release ${alloc_id} - free it manually to avoid charges."
    done
}

# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------
cmd_create() {
    hdr "CREATE - spinning up k8s-lab cluster (1 bastion + ${NUM_CONTROL_PLANES} control-plane(s) + ${NUM_WORKERS} worker(s))"

    # Validate topology values
    [[ "$NUM_CONTROL_PLANES" -ge 1 ]] || die "NUM_CONTROL_PLANES must be >= 1."
    [[ "$NUM_WORKERS"        -ge 1 ]] || die "NUM_WORKERS must be >= 1."

    # Warn about HA etcd requirements for even-numbered control planes
    if (( NUM_CONTROL_PLANES % 2 == 0 )); then
        warn "Even number of control-plane nodes (${NUM_CONTROL_PLANES}) detected."
        warn "etcd requires an odd quorum (1, 3, 5 …) to avoid split-brain. Consider using an odd count."
    fi

    # Guard against double-create: fail fast if tagged instances already exist
    load_ids
    if [[ ${#IDS[@]} -gt 0 ]]; then
        warn "Instances already exist for cluster '${TAG_PREFIX}':"
        print_table
        die "Run './k8s-cluster.sh terminate' first, or change TAG_PREFIX."
    fi

    resolve_vpc
    resolve_ami
    ensure_sg

    local total=$(( 1 + NUM_CONTROL_PLANES + NUM_WORKERS ))
    info "Launching ${total} node(s) …"

    IDS=()

    # --- bastion (always exactly one) ---
    local bastion
    bastion=$(launch_instance "bastion" "$BASTION_TYPE" "bastion")
    IDS+=("$bastion")

    # --- control-plane node(s) ---
    # Single node keeps the plain name "control-plane" for familiarity.
    # Multiple nodes get numeric suffixes: control-plane-1, control-plane-2, …
    declare -a CP_IDS=()
    if (( NUM_CONTROL_PLANES == 1 )); then
        local cp
        cp=$(launch_instance "control-plane" "$CONTROL_TYPE" "control-plane")
        IDS+=("$cp")
        CP_IDS+=("$cp")
    else
        for (( i=1; i<=NUM_CONTROL_PLANES; i++ )); do
            local cp
            cp=$(launch_instance "control-plane" "$CONTROL_TYPE" "control-plane-${i}")
            IDS+=("$cp")
            CP_IDS+=("$cp")
        done
    fi

    # --- worker node(s) ---
    for (( i=1; i<=NUM_WORKERS; i++ )); do
        local w
        w=$(launch_instance "worker" "$WORKER_TYPE" "worker-${i}")
        IDS+=("$w")
    done

    info "Instance IDs: ${IDS[*]}"
    wait_for_state "running"

    hdr "Associating Elastic IPs"
    associate_eip "$bastion" "${TAG_PREFIX}-bastion"
    # Uncomment below to also assign EIPs to every control-plane node:
    # for (( i=0; i<${#CP_IDS[@]}; i++ )); do
    #     local label="control-plane"
    #     (( NUM_CONTROL_PLANES > 1 )) && label="control-plane-$(( i+1 ))"
    #     associate_eip "${CP_IDS[$i]}" "${TAG_PREFIX}-${label}"
    # done

    hdr "Cluster ready"
    print_table

    echo ""
    ok "SSH into bastion:  ssh -i ${KEY_FILE} rocky@<bastion-eip>"
    ok "Elastic IPs are stable - they survive stop/start."
    warn "Workers have no public IP - reach them through the bastion."
    if (( NUM_CONTROL_PLANES > 1 )); then
        warn "HA control-plane: configure a load balancer (or kube-vip) in front of the ${NUM_CONTROL_PLANES} control-plane nodes before running kubeadm."
    fi
    warn "Next: set up kubespray on the bastion and use private IPs for the inventory."
}

cmd_stop() {
    hdr "STOP - shutting down cluster instances"
    load_ids
    [[ ${#IDS[@]} -eq 0 ]] && die "No instances found for cluster '${TAG_PREFIX}'."
    info "Stopping ${#IDS[@]} instance(s): ${IDS[*]}"
    aws ec2 stop-instances --region "$REGION" --instance-ids "${IDS[@]}" --output text >/dev/null
    wait_for_state "stopped"
    # EBS volumes and private IPs are retained while stopped; only compute billing pauses
    ok "Done. EBS volumes and private IPs are preserved."
}

cmd_stop_nodes() {
    hdr "STOP NODES - shutting down control-plane and workers (bastion stays up)"
    local raw
    raw=$(aws ec2 describe-instances \
        --region "$REGION" \
        --filters \
            "Name=tag:Cluster,Values=${TAG_PREFIX}" \
            "Name=tag:Role,Values=control-plane,worker" \
            "Name=instance-state-name,Values=pending,running,stopping,stopped" \
        --query "Reservations[].Instances[].InstanceId" \
        --output text 2>/dev/null | tr -d '\r' || true)

    IDS=()
    [[ -n "$raw" ]] && read -r -a IDS <<< "$raw"
    [[ ${#IDS[@]} -eq 0 ]] && die "No control-plane or worker instances found for cluster '${TAG_PREFIX}'."

    info "Stopping ${#IDS[@]} instance(s): ${IDS[*]}"
    aws ec2 stop-instances --region "$REGION" --instance-ids "${IDS[@]}" --output text >/dev/null
    wait_for_state "stopped"
    ok "Done. Bastion is still running."
}

cmd_start_bastion() {
    hdr "START BASTION - bringing bastion back up"
    local raw
    raw=$(aws ec2 describe-instances \
        --region "$REGION" \
        --filters \
            "Name=tag:Cluster,Values=${TAG_PREFIX}" \
            "Name=tag:Role,Values=bastion" \
            "Name=instance-state-name,Values=stopped" \
        --query "Reservations[].Instances[].InstanceId" \
        --output text 2>/dev/null | tr -d '\r' || true)

    IDS=()
    [[ -n "$raw" ]] && read -r -a IDS <<< "$raw"
    [[ ${#IDS[@]} -eq 0 ]] && die "No stopped bastion found for cluster '${TAG_PREFIX}'."

    aws ec2 start-instances --region "$REGION" --instance-ids "${IDS[@]}" --output text >/dev/null
    wait_for_state "running"
    load_ids
    print_table
}

cmd_start() {
    hdr "START - bringing cluster instances back up"
    # Only look for stopped instances to avoid trying to start already-running ones
    load_ids "stopped"
    [[ ${#IDS[@]} -eq 0 ]] && die "No stopped instances found for cluster '${TAG_PREFIX}'."
    info "Starting ${#IDS[@]} instance(s): ${IDS[*]}"
    aws ec2 start-instances --region "$REGION" --instance-ids "${IDS[@]}" --output text >/dev/null
    wait_for_state "running"

    hdr "Updated IPs (public IPs may have changed)"
    load_ids   # reload so print_table has fresh running state
    print_table
}

cmd_terminate() {
    hdr "TERMINATE - permanently destroying cluster"
    load_ids
    if [[ ${#IDS[@]} -eq 0 ]]; then
        warn "No instances found for '${TAG_PREFIX}'. Nothing to do."
        return
    fi

    # Show what will be deleted before asking for confirmation
    echo -e "${RED}${BOLD}WARNING: This will permanently delete all instances and their storage!${RST}"
    print_table
    echo ""
    read -r -p "Type 'yes' to confirm permanent deletion: " confirm
    [[ "$confirm" != "yes" ]] && { info "Aborted."; exit 0; }

    aws ec2 terminate-instances --region "$REGION" --instance-ids "${IDS[@]}" --output text >/dev/null
    wait_for_state "terminated"
    ok "All instances terminated."

    release_eips

    # Clean up the security group - must happen after instances are fully terminated
    # because a running ENI will block SG deletion
    local sg_name="${TAG_PREFIX}-sg"
    local sg
    sg=$(aws ec2 describe-security-groups \
        --region "$REGION" \
        --filters "Name=group-name,Values=${sg_name}" \
        --query "SecurityGroups[0].GroupId" --output text 2>/dev/null || true)
    if [[ -n "$sg" && "$sg" != "None" ]]; then
        info "Deleting security group ${sg} …"
        # Brief pause to let AWS finish detaching ENIs from just-terminated instances
        sleep 8
        aws ec2 delete-security-group --region "$REGION" --group-id "$sg" 2>/dev/null && \
            ok "Security group deleted." || \
            warn "SG still held - delete manually: aws ec2 delete-security-group --region ${REGION} --group-id ${sg}"
    fi
}

cmd_status() {
    hdr "STATUS - cluster '${TAG_PREFIX}' (region: ${REGION})"
    load_ids
    if [[ ${#IDS[@]} -eq 0 ]]; then
        warn "No instances found for cluster '${TAG_PREFIX}'."
        return
    fi
    print_table
}

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------
case "${1:-help}" in
    create)         cmd_create         ;;
    stop)           cmd_stop           ;;
    stop-nodes)     cmd_stop_nodes     ;;
    start)          cmd_start          ;;
    start-bastion)  cmd_start_bastion  ;;
    terminate)      cmd_terminate      ;;
    status)         cmd_status         ;;
    *)
        # Default/help - print usage when no argument or unknown argument given
        echo ""
        echo -e "${BOLD}k8s-cluster.sh${RST} - AWS k8s bare-metal-sim cluster manager"
        echo ""
        echo "  Usage: $0 [command]"
        echo ""
        echo -e "  Topology (edit at top of script or pass as env vars NC / NW):"
				echo -e "    NC=${NUM_CONTROL_PLANES}   - control-plane nodes (1 = single, 3 or 5 = HA)"
				echo -e "    NW=${NUM_WORKERS}          - worker nodes"
        echo ""
        echo -e "  ${GRN}create${RST}        Launch all nodes (1 bastion + NUM_CONTROL_PLANES + NUM_WORKERS)"
        echo -e "  ${YLW}stop${RST}          Stop all instances - compute billing pauses, EBS stays"
        echo -e "  ${YLW}stop-nodes${RST}    Stop control-plane + workers only (bastion stays running)"
        echo -e "  ${GRN}start${RST}         Start all stopped instances - public IPs will change!"
        echo -e "  ${GRN}start-bastion${RST} Start the bastion only"
        echo -e "  ${RED}terminate${RST}     Permanently destroy everything (asks for confirmation)"
        echo -e "  ${BLU}status${RST}        Print current state and IPs for all nodes"
        echo ""
        ;;
esac
```