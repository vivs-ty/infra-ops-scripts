#!/bin/bash

######################################################################################

# Export Path Variable
export PATH=$PATH:/opt

######################################################################################

usage() {
  echo ""
  echo "SSL Certificate Expiry Checker"
  echo ""
  echo "SYNTAX  = ./ssl_cert_check.sh <HOSTS_FILE> [OPTIONS]"
  echo ""
  echo "  HOSTS_FILE           - File with one host:port per line (default port: 443)"
  echo ""
  echo "OPTIONS:"
  echo "  -w, --warn   DAYS    - Warn when cert expires within N days (default: 30)"
  echo "  -c, --crit   DAYS    - Critical alert when cert expires within N days (default: 7)"
  echo "  -t, --timeout SEC    - Connection timeout in seconds (default: 10)"
  echo "  -l, --log    FILE    - Log file path (default: /var/log/ssl_cert_check.log)"
  echo "  -e, --email  ADDR    - Email address to alert (optional)"
  echo ""
  echo "HOSTS FILE FORMAT:"
  echo "  example.com"
  echo "  example.com:8443"
  echo "  192.168.1.10:443"
  echo ""
  echo "EXAMPLES:"
  echo "  ./ssl_cert_check.sh hosts.txt"
  echo "  ./ssl_cert_check.sh hosts.txt --warn 30 --crit 7"
  echo "  ./ssl_cert_check.sh hosts.txt --email ops@example.com"
  echo ""
  exit 1
}

######################################################################################

HOSTS_FILE=""
WARN_DAYS=30
CRIT_DAYS=7
TIMEOUT=10
LOG_FILE="/var/log/ssl_cert_check.log"
ALERT_EMAIL=""

if [[ -z "$1" ]]; then usage; fi
HOSTS_FILE="$1"
shift

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    -w|--warn)    WARN_DAYS="$2";  shift 2 ;;
    -c|--crit)    CRIT_DAYS="$2";  shift 2 ;;
    -t|--timeout) TIMEOUT="$2";    shift 2 ;;
    -l|--log)     LOG_FILE="$2";   shift 2 ;;
    -e|--email)   ALERT_EMAIL="$2";shift 2 ;;
    -h|--help)    usage ;;
    *) echo "ERROR: Unknown option '$1'."; usage ;;
  esac
done

######################################################################################

if [[ ! -f "$HOSTS_FILE" ]]; then
  echo "ERROR: Hosts file '$HOSTS_FILE' not found."
  exit 1
fi

if ! command -v openssl &> /dev/null; then
  echo "ERROR: openssl is required but not installed."
  exit 1
fi

######################################################################################

# Helper: parse an OpenSSL date string to a Unix epoch in a cross-platform way.
# openssl enddate format: "Apr  5 12:34:56 2026 GMT"
# GNU date  : date -d "..." +%s          (Linux)
# BSD date  : date -j -f "%b %e %H:%M:%S %Y %Z" "..." +%s  (macOS/FreeBSD)
# Perl      : fallback when neither works
parse_date_epoch() {
  local raw="$1"
  local epoch
  epoch=$(date -d "$raw" +%s 2>/dev/null)
  if [[ -n "$epoch" ]]; then echo "$epoch"; return; fi
  epoch=$(date -j -f "%b %e %H:%M:%S %Y %Z" "$raw" +%s 2>/dev/null)
  if [[ -n "$epoch" ]]; then echo "$epoch"; return; fi
  perl -MTime::Piece -e "print Time::Piece->strptime('$raw','%b %e %H:%M:%S %Y %Z')->epoch" 2>/dev/null
}

check_cert() {
  local host="$1"
  local port="$2"

  # Fetch certificate expiry date
  local expiry_raw
  expiry_raw=$(echo | timeout "$TIMEOUT" openssl s_client -servername "$host" \
    -connect "${host}:${port}" 2>/dev/null \
    | openssl x509 -noout -enddate 2>/dev/null \
    | cut -d= -f2)

  if [[ -z "$expiry_raw" ]]; then
    echo "ERROR" "$host:$port" "Could not retrieve certificate"
    return
  fi

  local expiry_epoch
  expiry_epoch=$(parse_date_epoch "$expiry_raw")
  if [[ -z "$expiry_epoch" ]]; then
    echo "ERROR" "$host:$port" "Could not parse expiry date: $expiry_raw"
    return
  fi

  local now_epoch days_left
  now_epoch=$(date +%s)
  days_left=$(( (expiry_epoch - now_epoch) / 86400 ))

  local status="OK"
  if [[ "$days_left" -le "$CRIT_DAYS" ]]; then
    status="CRITICAL"
  elif [[ "$days_left" -le "$WARN_DAYS" ]]; then
    status="WARNING"
  fi

  echo "$status" "$host:$port" "$days_left days remaining (expires: $expiry_raw)"
}

######################################################################################

TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")
OK_COUNT=0; WARN_COUNT=0; CRIT_COUNT=0; ERR_COUNT=0
ALERT_LINES=()

echo "------------------------------------------------------------"
echo "SSL Certificate Check : $TIMESTAMP"
echo "Hosts file            : $HOSTS_FILE"
echo "Warn threshold        : $WARN_DAYS days"
echo "Critical threshold    : $CRIT_DAYS days"
echo "------------------------------------------------------------"

while IFS= read -r line || [[ -n "$line" ]]; do
  # Skip empty lines and comments
  [[ -z "$line" || "$line" =~ ^# ]] && continue

  HOST=$(echo "$line" | cut -d: -f1)
  PORT=$(echo "$line" | cut -d: -f2)
  [[ "$PORT" == "$HOST" || -z "$PORT" ]] && PORT=443

  read -r STATUS ENDPOINT MSG <<< "$(check_cert "$HOST" "$PORT")"

  LOG_LINE="$TIMESTAMP | $STATUS | $ENDPOINT | $MSG"
  echo "  [$STATUS] $ENDPOINT — $MSG"
  echo "$LOG_LINE" >> "$LOG_FILE"

  case "$STATUS" in
    OK)       (( OK_COUNT++ )) ;;
    WARNING)  (( WARN_COUNT++ )); ALERT_LINES+=("$LOG_LINE") ;;
    CRITICAL) (( CRIT_COUNT++ )); ALERT_LINES+=("$LOG_LINE") ;;
    ERROR)    (( ERR_COUNT++ )); ALERT_LINES+=("$LOG_LINE") ;;
  esac

done < "$HOSTS_FILE"

######################################################################################

echo ""
echo "------------------------------------------------------------"
echo "Summary : OK=$OK_COUNT  WARNING=$WARN_COUNT  CRITICAL=$CRIT_COUNT  ERROR=$ERR_COUNT"
echo "Log     : $LOG_FILE"
echo "------------------------------------------------------------"

# Send alert email if there are warnings or critical certs
if [[ "${#ALERT_LINES[@]}" -gt 0 && -n "$ALERT_EMAIL" ]] && command -v mail &> /dev/null; then
  SUBJECT="SSL Certificate Alert — $(hostname) — WARN:$WARN_COUNT CRIT:$CRIT_COUNT"
  BODY=$(printf '%s\n' "${ALERT_LINES[@]}")
  echo "$BODY" | mail -s "$SUBJECT" "$ALERT_EMAIL"
fi

# Exit with non-zero if any critical or errors
if [[ "$CRIT_COUNT" -gt 0 || "$ERR_COUNT" -gt 0 ]]; then
  exit 2
elif [[ "$WARN_COUNT" -gt 0 ]]; then
  exit 1
fi
