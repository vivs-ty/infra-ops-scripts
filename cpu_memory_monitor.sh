#!/bin/bash

######################################################################################

# Export Path Variable
export PATH=$PATH:/opt

######################################################################################

# Usage help
usage() {
  echo ""
  echo "CPU & Memory Monitor"
  echo ""
  echo "SYNTAX  = ./cpu_memory_monitor.sh [OPTIONS]"
  echo ""
  echo "OPTIONS:"
  echo "  -c, --cpu-threshold    PCT   - Alert when CPU usage exceeds PCT% (default: 80)"
  echo "  -m, --mem-threshold    PCT   - Alert when memory usage exceeds PCT% (default: 80)"
  echo "  -d, --disk-threshold   PCT   - Alert when any disk mount usage exceeds PCT% (default: 90)"
  echo "  -i, --interval         SEC   - Check interval in seconds (default: 60)"
  echo "  -r, --repeat           NUM   - Number of checks to run; 0 = run forever (default: 0)"
  echo "  -l, --log-file         FILE  - Log file path (default: /var/log/resource_monitor.log)"
  echo "  -e, --email            ADDR  - Email address to alert (optional)"
  echo ""
  echo "EXAMPLES:"
  echo "  ./cpu_memory_monitor.sh"
  echo "  ./cpu_memory_monitor.sh --cpu-threshold 90 --mem-threshold 85 --interval 30"
  echo "  ./cpu_memory_monitor.sh --email ops@example.com --repeat 10"
  echo ""
  exit 1
}

######################################################################################

# Defaults
CPU_THRESHOLD=80
MEM_THRESHOLD=80
DISK_THRESHOLD=90
INTERVAL=60
REPEAT=0
LOG_FILE="/var/log/resource_monitor.log"
ALERT_EMAIL=""

######################################################################################

# Parse arguments
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    -c|--cpu-threshold)  CPU_THRESHOLD="$2";  shift 2 ;;
    -m|--mem-threshold)  MEM_THRESHOLD="$2";  shift 2 ;;
    -d|--disk-threshold) DISK_THRESHOLD="$2"; shift 2 ;;
    -i|--interval)       INTERVAL="$2";       shift 2 ;;
    -r|--repeat)        REPEAT="$2";        shift 2 ;;
    -l|--log-file)      LOG_FILE="$2";      shift 2 ;;
    -e|--email)         ALERT_EMAIL="$2";   shift 2 ;;
    -h|--help)          usage ;;
    *) echo "ERROR: Unknown option '$1'."; usage ;;
  esac
done

######################################################################################

# Validate inputs
for VAR in CPU_THRESHOLD MEM_THRESHOLD DISK_THRESHOLD INTERVAL REPEAT; do
  if ! [[ "${!VAR}" =~ ^[0-9]+$ ]]; then
    echo "ERROR: $VAR must be a positive integer."
    exit 1
  fi
done

######################################################################################

# Helper: get current CPU usage %
get_cpu_usage() {
  # Read two snapshots 1 second apart from /proc/stat for accuracy
  local cpu1 cpu2 idle1 idle2 total1 total2
  read -ra cpu1 < <(grep '^cpu ' /proc/stat)
  sleep 1
  read -ra cpu2 < <(grep '^cpu ' /proc/stat)

  local idle1=${cpu1[4]} idle2=${cpu2[4]}
  local total1=0 total2=0
  for val in "${cpu1[@]:1}"; do (( total1 += val )); done
  for val in "${cpu2[@]:1}"; do (( total2 += val )); done

  local diff_total=$(( total2 - total1 ))
  local diff_idle=$(( idle2 - idle1 ))

  if [[ "$diff_total" -eq 0 ]]; then
    echo 0
  else
    echo $(( 100 * (diff_total - diff_idle) / diff_total ))
  fi
}

# Helper: get current memory usage %
get_mem_usage() {
  local mem_total mem_available
  mem_total=$(grep MemTotal /proc/meminfo | awk '{print $2}')
  mem_available=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
  echo $(( 100 * (mem_total - mem_available) / mem_total ))
}

# Helper: print "PCT MOUNT" lines for mounts exceeding threshold
get_disk_alerts() {
  local threshold="$1"
  df -h --output=pcent,target 2>/dev/null \
    | tail -n +2 \
    | awk -v thr="$threshold" '{
        pct=$1; sub(/%/, "", pct);
        if (pct+0 >= thr+0) print pct, $2
      }'
}

# Helper: send alert email
send_alert() {
  local subject="$1"
  local body="$2"
  if [[ -n "$ALERT_EMAIL" ]] && command -v mail &> /dev/null; then
    echo "$body" | mail -s "$subject" "$ALERT_EMAIL"
  fi
}

######################################################################################

HOSTNAME=$(hostname)
CHECK_NUM=0

echo "------------------------------------------------------------"
echo "Resource Monitor started : $(date)"
echo "Host                     : $HOSTNAME"
echo "CPU threshold            : ${CPU_THRESHOLD}%"
echo "Memory threshold         : ${MEM_THRESHOLD}%"
echo "Disk threshold           : ${DISK_THRESHOLD}%"
echo "Check interval           : ${INTERVAL}s"
echo "Repeat                   : $([ "$REPEAT" -eq 0 ] && echo 'forever' || echo $REPEAT)"
echo "Log file                 : $LOG_FILE"
echo "Alert email              : ${ALERT_EMAIL:-not configured}"
echo "------------------------------------------------------------"

######################################################################################

while true; do
  (( CHECK_NUM++ ))
  TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")

  CPU_USAGE=$(get_cpu_usage)
  MEM_USAGE=$(get_mem_usage)
  DISK_ALERT_LINES=$(get_disk_alerts "$DISK_THRESHOLD")

  MEM_TOTAL_MB=$(( $(grep MemTotal /proc/meminfo | awk '{print $2}') / 1024 ))
  MEM_USED_MB=$(( MEM_TOTAL_MB * MEM_USAGE / 100 ))

  STATUS="OK"
  ALERTS=()

  if [[ "$CPU_USAGE" -ge "$CPU_THRESHOLD" ]]; then
    ALERTS+=("CPU usage ${CPU_USAGE}% exceeds threshold ${CPU_THRESHOLD}%")
    STATUS="ALERT"
  fi

  if [[ "$MEM_USAGE" -ge "$MEM_THRESHOLD" ]]; then
    ALERTS+=("Memory usage ${MEM_USAGE}% (${MEM_USED_MB}MB / ${MEM_TOTAL_MB}MB) exceeds threshold ${MEM_THRESHOLD}%")
    STATUS="ALERT"
  fi

  if [[ -n "$DISK_ALERT_LINES" ]]; then
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      pct=$(awk '{print $1}' <<< "$line")
      mnt=$(awk '{print $2}' <<< "$line")
      ALERTS+=("Disk usage ${pct}% on ${mnt} exceeds threshold ${DISK_THRESHOLD}%")
    done <<< "$DISK_ALERT_LINES"
    STATUS="ALERT"
  fi

  LOG_LINE="$TIMESTAMP | $HOSTNAME | CPU: ${CPU_USAGE}% | MEM: ${MEM_USAGE}% (${MEM_USED_MB}MB/${MEM_TOTAL_MB}MB) | $STATUS"
  echo "$LOG_LINE"
  echo "$LOG_LINE" >> "$LOG_FILE"

  for alert in "${ALERTS[@]}"; do
    ALERT_MSG="[$HOSTNAME] ALERT: $alert at $TIMESTAMP"
    echo "  *** $ALERT_MSG"
    echo "$TIMESTAMP | ALERT | $alert" >> "$LOG_FILE"
    send_alert "Resource Alert: $HOSTNAME" "$ALERT_MSG"
  done

  # Exit if repeat count reached
  if [[ "$REPEAT" -gt 0 && "$CHECK_NUM" -ge "$REPEAT" ]]; then
    echo "------------------------------------------------------------"
    echo "Completed $CHECK_NUM check(s). Exiting."
    break
  fi

  sleep "$INTERVAL"
done
