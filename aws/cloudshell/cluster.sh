#!/bin/bash
# -- Cluster Start/Stop Script --------------------------------

REGION="${AWS_DEFAULT_REGION:-us-east-1}"
ACTION="${1}"

STARTUP_LAMBDA="${STARTUP_LAMBDA:-k8s-lab-startup}"
SHUTDOWN_LAMBDA="${SHUTDOWN_LAMBDA:-k8s-lab-shutdown}"

# -- Invoke Lambda and stream logs ----------------------------
invoke_lambda() {
  local fn="$1"
  echo "Invoking Lambda: $fn"
  aws lambda invoke \
    --function-name "$fn" \
    --payload '{}' \
    --log-type Tail \
    --region "$REGION" \
    /tmp/lambda-response.json \
    --query 'LogResult' \
    --output text | base64 --decode
  echo ""
  echo "Response payload:"
  cat /tmp/lambda-response.json
  echo ""
}

# -- Print table of all instances -----------------------------
print_table() {
  echo ""
  echo "┌---------------------┬--------------┬---------------┬-----------------┬-----------------┬-----------------┐"
  echo "│ Instance ID         │ State        │ Type          │ Name            │ Private IP      │ Public IP       │"
  echo "├---------------------┼--------------┼---------------┼-----------------┼-----------------┼-----------------┤"
  aws ec2 describe-instances \
    --query "Reservations[].Instances[].[InstanceId, State.Name, InstanceType, Tags[?Key=='Name'].Value | [0], PrivateIpAddress, PublicIpAddress]" \
    --output text --region "$REGION" | \
  while IFS=$'\t' read -r id state type name private_ip public_ip; do
    name="${name:-<no name>}"
    name="${name:0:15}"
    private_ip="${private_ip:--}"
    public_ip="${public_ip:--}"
    printf "│ %-19s │ %-12s │ %-13s │ %-15s │ %-15s │ %-15s │\n" \
      "$id" "$state" "$type" "$name" "$private_ip" "$public_ip"
  done
  echo "└---------------------┴--------------┴---------------┴-----------------┴-----------------┴-----------------┘"
  echo ""
}

case "$ACTION" in
  start)
    invoke_lambda "$STARTUP_LAMBDA"
    ;;
  stop)
    invoke_lambda "$SHUTDOWN_LAMBDA"
    ;;
  ""|status)
    echo "Usage: $0 <start|stop|status>"
    echo "  start   - invoke $STARTUP_LAMBDA (recreates NAT + starts cluster)"
    echo "  stop    - invoke $SHUTDOWN_LAMBDA (stops cluster + removes NAT)"
    echo "  status  - show instance table"
    print_table
    ;;
  *)
    echo "Error: unknown action '$ACTION'. Use start, stop, or status." >&2
    exit 1
    ;;
esac
