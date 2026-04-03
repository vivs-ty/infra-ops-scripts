#!/bin/bash

######################################################################################

# Export Path Variable
export PATH=$PATH:/opt

######################################################################################

usage() {
  echo ""
  echo "User Audit Utility"
  echo ""
  echo "SYNTAX  = ./user_audit.sh [OPTIONS]"
  echo ""
  echo "OPTIONS:"
  echo "  -o, --output  FILE   - Write report to a file instead of stdout"
  echo "  -l, --log-only       - Skip console output, only write to log file"
  echo ""
  echo "EXAMPLES:"
  echo "  ./user_audit.sh"
  echo "  ./user_audit.sh --output /tmp/user_audit_report.txt"
  echo ""
  exit 1
}

######################################################################################

OUTPUT_FILE=""
LOG_ONLY=false

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    -o|--output)   OUTPUT_FILE="$2"; shift 2 ;;
    -l|--log-only) LOG_ONLY=true;    shift ;;
    -h|--help)     usage ;;
    *) echo "ERROR: Unknown option '$1'."; usage ;;
  esac
done

######################################################################################

HOSTNAME=$(hostname)
TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")
REPORT=""

line()  { REPORT+="$1"$'\n'; }
blank() { REPORT+=$'\n'; }

######################################################################################

line "============================================================"
line " User Audit Report"
line " Host      : $HOSTNAME"
line " Generated : $TIMESTAMP"
line "============================================================"
blank

# -----------------------------------------------------------------------
# Section 1: All users with login shells
# -----------------------------------------------------------------------
line "------------------------------------------------------------"
line " USERS WITH LOGIN SHELLS"
line "------------------------------------------------------------"
line "$(printf '%-20s %-6s %-30s %s' 'USERNAME' 'UID' 'HOME' 'SHELL')"
line "$(printf '%-20s %-6s %-30s %s' '--------' '---' '----' '-----')"

while IFS=: read -r username _ uid gid _ home shell; do
  if [[ "$shell" != "/usr/sbin/nologin" && "$shell" != "/bin/false" && "$shell" != "/sbin/nologin" ]]; then
    line "$(printf '%-20s %-6s %-30s %s' "$username" "$uid" "$home" "$shell")"
  fi
done < /etc/passwd
blank

# -----------------------------------------------------------------------
# Section 2: Users with sudo access
# -----------------------------------------------------------------------
line "------------------------------------------------------------"
line " USERS WITH SUDO ACCESS"
line "------------------------------------------------------------"

# Check /etc/sudoers
if [[ -f /etc/sudoers ]]; then
  SUDO_USERS=$(grep -v '^#' /etc/sudoers | grep -v '^$' | grep -v '^Defaults' | grep -v '^alias' | grep '%')
  if [[ -n "$SUDO_USERS" ]]; then
    line "From /etc/sudoers (group entries):"
    line "$SUDO_USERS"
  fi
fi

# Check /etc/sudoers.d/
if [[ -d /etc/sudoers.d ]]; then
  line ""
  line "From /etc/sudoers.d/:"
  for f in /etc/sudoers.d/*; do
    [[ -f "$f" ]] || continue
    CONTENT=$(grep -v '^#' "$f" | grep -v '^$')
    [[ -n "$CONTENT" ]] && line "  $(basename "$f"): $CONTENT"
  done
fi

# Check users in sudo/wheel group
for group in sudo wheel admin; do
  if getent group "$group" &>/dev/null; then
    MEMBERS=$(getent group "$group" | cut -d: -f4)
    if [[ -n "$MEMBERS" ]]; then
      line ""
      line "Members of '$group' group: $MEMBERS"
    fi
  fi
done
blank

# -----------------------------------------------------------------------
# Section 3: Last login times
# -----------------------------------------------------------------------
line "------------------------------------------------------------"
line " LAST LOGIN TIMES"
line "------------------------------------------------------------"
if command -v lastlog &>/dev/null; then
  line "$(lastlog | grep -v 'Never logged in' | head -40)"
else
  line "lastlog not available on this system."
fi
blank

# -----------------------------------------------------------------------
# Section 4: Currently logged-in users
# -----------------------------------------------------------------------
line "------------------------------------------------------------"
line " CURRENTLY LOGGED-IN USERS"
line "------------------------------------------------------------"
line "$(who)"
blank

# -----------------------------------------------------------------------
# Section 5: Failed login attempts (last 20)
# -----------------------------------------------------------------------
line "------------------------------------------------------------"
line " RECENT FAILED LOGIN ATTEMPTS (last 20)"
line "------------------------------------------------------------"
if command -v lastb &>/dev/null; then
  FAILED=$(lastb 2>/dev/null | head -20)
  if [[ -n "$FAILED" ]]; then
    line "$FAILED"
  else
    line "No failed login attempts recorded (or /var/log/btmp not accessible)."
  fi
else
  line "lastb not available on this system."
fi
blank

# -----------------------------------------------------------------------
# Section 6: Users with empty passwords
# -----------------------------------------------------------------------
line "------------------------------------------------------------"
line " USERS WITH EMPTY PASSWORDS"
line "------------------------------------------------------------"
EMPTY_PASS=$(awk -F: '($2 == "" || $2 == "!") {print $1}' /etc/shadow 2>/dev/null)
if [[ -n "$EMPTY_PASS" ]]; then
  line "$EMPTY_PASS"
else
  line "None found (or insufficient permissions to read /etc/shadow)."
fi
blank

# -----------------------------------------------------------------------
# Section 7: UID 0 accounts (root equivalents)
# -----------------------------------------------------------------------
line "------------------------------------------------------------"
line " ACCOUNTS WITH UID 0 (root equivalents)"
line "------------------------------------------------------------"
UID0=$(awk -F: '($3 == 0) {print $1}' /etc/passwd)
line "$UID0"
blank

line "============================================================"
line " End of Report"
line "============================================================"

######################################################################################

# Output
if [[ "$LOG_ONLY" == false ]]; then
  echo "$REPORT"
fi

if [[ -n "$OUTPUT_FILE" ]]; then
  echo "$REPORT" > "$OUTPUT_FILE"
  echo "Report written to: $OUTPUT_FILE"
fi
