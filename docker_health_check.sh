#!/bin/bash

######################################################################################

# Export Path Variable
export PATH=$PATH:/opt

######################################################################################

usage() {
  echo ""
  echo "Docker Container Health Check"
  echo ""
  echo "SYNTAX  = ./docker_health_check.sh [OPTIONS]"
  echo ""
  echo "OPTIONS:"
  echo "  -a, --all              - Check all running containers (default)"
  echo "  -n, --name  NAME       - Check a specific container by name or ID"
  echo "  -r, --restart          - Restart containers that are unhealthy"
  echo "  -l, --log    FILE      - Log file path (default: /var/log/docker_health.log)"
  echo "  -e, --email  ADDR      - Email address to alert on unhealthy containers"
  echo ""
  echo "EXAMPLES:"
  echo "  ./docker_health_check.sh"
  echo "  ./docker_health_check.sh --name myapp --restart"
  echo "  ./docker_health_check.sh --all --restart --email ops@example.com"
  echo ""
  exit 1
}

######################################################################################

CHECK_ALL=true
TARGET_NAME=""
AUTO_RESTART=false
LOG_FILE="/var/log/docker_health.log"
ALERT_EMAIL=""

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    -a|--all)      CHECK_ALL=true;         shift ;;
    -n|--name)     TARGET_NAME="$2"; CHECK_ALL=false; shift 2 ;;
    -r|--restart)  AUTO_RESTART=true;      shift ;;
    -l|--log)      LOG_FILE="$2";          shift 2 ;;
    -e|--email)    ALERT_EMAIL="$2";       shift 2 ;;
    -h|--help)     usage ;;
    *) echo "ERROR: Unknown option '$1'."; usage ;;
  esac
done

######################################################################################

if ! command -v docker &>/dev/null; then
  echo "ERROR: docker is not installed or not in PATH."
  exit 1
fi

######################################################################################

TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")
HEALTHY=0; UNHEALTHY=0; NO_HEALTHCHECK=0; RESTARTED=0
ALERT_LINES=()

echo "------------------------------------------------------------"
echo "Docker Health Check : $TIMESTAMP"
echo "Auto-restart        : $AUTO_RESTART"
echo "------------------------------------------------------------"

######################################################################################

check_container() {
  local id="$1"
  local name="$2"
  local status="$3"
  local health="$4"

  local display_health="${health:-no healthcheck}"
  local log_status="INFO"

  if [[ "$status" != "running" ]]; then
    echo "  [STOPPED   ] $name ($id) — status: $status"
    log_status="STOPPED"
    (( UNHEALTHY++ ))
    ALERT_LINES+=("$TIMESTAMP | STOPPED | $name | status: $status")
  elif [[ "$health" == "unhealthy" ]]; then
    echo "  [UNHEALTHY ] $name ($id) — health: $health"
    log_status="UNHEALTHY"
    (( UNHEALTHY++ ))
    ALERT_LINES+=("$TIMESTAMP | UNHEALTHY | $name | $id")

    if [[ "$AUTO_RESTART" == true ]]; then
      echo "    --> Restarting $name..."
      if docker restart "$id" &>/dev/null; then
        echo "    --> Restarted successfully."
        log_status="RESTARTED"
        (( RESTARTED++ ))
      else
        echo "    --> ERROR: Failed to restart $name."
      fi
    fi
  elif [[ "$health" == "healthy" ]]; then
    echo "  [HEALTHY   ] $name ($id)"
    (( HEALTHY++ ))
  else
    echo "  [NO CHECK  ] $name ($id) — no HEALTHCHECK defined in image"
    (( NO_HEALTHCHECK++ ))
  fi

  echo "$TIMESTAMP | $log_status | $name | $id | status=$status health=${health:-none}" >> "$LOG_FILE"
}

######################################################################################

if [[ "$CHECK_ALL" == true ]]; then
  echo ""
  while IFS='|' read -r id name status health; do
    check_container "$id" "$name" "$status" "$health"
  done < <(docker ps --format "{{.ID}}|{{.Names}}|{{.Status}}|{{.State}}" \
    | awk -F'|' '{
        split($3, s, " ");
        status=s[1];
        health="";
        if ($3 ~ /healthy/)  health="healthy";
        if ($3 ~ /unhealthy/) health="unhealthy";
        if ($3 ~ /starting/)  health="starting";
        print $1"|"$2"|"status"|"health
      }')
else
  CONTAINER_ID=$(docker ps --filter "name=$TARGET_NAME" --format "{{.ID}}" | head -1)
  if [[ -z "$CONTAINER_ID" ]]; then
    echo "ERROR: Container '$TARGET_NAME' not found or not running."
    exit 1
  fi
  STATUS=$(docker inspect --format '{{.State.Status}}' "$CONTAINER_ID")
  HEALTH=$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{end}}' "$CONTAINER_ID")
  check_container "$CONTAINER_ID" "$TARGET_NAME" "$STATUS" "$HEALTH"
fi

######################################################################################

echo ""
echo "------------------------------------------------------------"
echo "Summary : HEALTHY=$HEALTHY  UNHEALTHY=$UNHEALTHY  NO_HEALTHCHECK=$NO_HEALTHCHECK  RESTARTED=$RESTARTED"
echo "Log     : $LOG_FILE"
echo "------------------------------------------------------------"

# Send alert email if any unhealthy
if [[ "${#ALERT_LINES[@]}" -gt 0 && -n "$ALERT_EMAIL" ]] && command -v mail &>/dev/null; then
  SUBJECT="Docker Health Alert — $(hostname) — $UNHEALTHY unhealthy container(s)"
  BODY=$(printf '%s\n' "${ALERT_LINES[@]}")
  echo "$BODY" | mail -s "$SUBJECT" "$ALERT_EMAIL"
fi

if [[ "$UNHEALTHY" -gt 0 ]]; then
  exit 1
fi
