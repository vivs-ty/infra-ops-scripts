#!/bin/bash

######################################################################################

# Export Path Variable
export PATH=$PATH:/opt

######################################################################################

# Usage help
usage() {
  echo ""
  echo "Log Rotation Utility"
  echo ""
  echo "SYNTAX  = ./log_rotate.sh <LOG_DIR> [OPTIONS]"
  echo ""
  echo "  LOG_DIR              - Directory containing log files to rotate"
  echo ""
  echo "OPTIONS:"
  echo "  -a, --age     DAYS   - Compress logs older than N days (default: 3)"
  echo "  -d, --delete  DAYS   - Delete compressed logs older than N days (default: 30)"
  echo "  -e, --ext     EXT    - Log file extension to target (default: log)"
  echo "  -m, --maxdepth N     - Maximum directory depth for find (default: unlimited)"
  echo "  -n, --dry-run        - Show what would be done without making changes"
  echo ""
  echo "EXAMPLES:"
  echo "  ./log_rotate.sh /var/log/nginx"
  echo "  ./log_rotate.sh /var/log/nginx --age 7 --delete 60"
  echo "  ./log_rotate.sh /var/log/myapp --ext txt --dry-run"
  echo ""
  exit 1
}

######################################################################################

# Defaults
LOG_DIR=""
COMPRESS_AGE=3
DELETE_AGE=30
LOG_EXT="log"
MAX_DEPTH=""   # Empty = unlimited (no -maxdepth passed to find)
DRY_RUN=false
SCRIPT_LOG="/var/log/log_rotate.log"

######################################################################################

# Parse arguments
if [[ -z "$1" ]]; then
  usage
fi

LOG_DIR="$1"
shift

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    -a|--age)
      COMPRESS_AGE="$2"; shift 2 ;;
    -d|--delete)
      DELETE_AGE="$2"; shift 2 ;;
    -e|--ext)
      LOG_EXT="$2"; shift 2 ;;
    -m|--maxdepth)
      MAX_DEPTH="$2"; shift 2 ;;
    -n|--dry-run)
      DRY_RUN=true; shift ;;
    *)
      echo "ERROR: Unknown option '$1'."
      usage ;;
  esac
done

######################################################################################

# Validate inputs
if [[ ! -d "$LOG_DIR" ]]; then
  echo "ERROR: Log directory '$LOG_DIR' does not exist."
  exit 1
fi

if ! [[ "$COMPRESS_AGE" =~ ^[0-9]+$ ]] || ! [[ "$DELETE_AGE" =~ ^[0-9]+$ ]]; then
  echo "ERROR: --age and --delete must be positive integers."
  exit 1
fi

if [[ -n "$MAX_DEPTH" ]] && ! [[ "$MAX_DEPTH" =~ ^[0-9]+$ ]]; then
  echo "ERROR: --maxdepth must be a positive integer."
  exit 1
fi

if [[ "$COMPRESS_AGE" -ge "$DELETE_AGE" ]]; then
  echo "ERROR: --age ($COMPRESS_AGE) must be less than --delete ($DELETE_AGE)."
  exit 1
fi

######################################################################################

TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")
COMPRESSED_COUNT=0
DELETED_COUNT=0
ERRORS=0

log_entry() {
  echo "$1"
  echo "$(date +"%Y-%m-%d %H:%M:%S") | $1" >> "$SCRIPT_LOG"
}

######################################################################################

echo "------------------------------------------------------------"
echo "Log Rotation started : $TIMESTAMP"
echo "Log directory        : $LOG_DIR"
echo "Compress logs older  : $COMPRESS_AGE days"
echo "Delete logs older    : $DELETE_AGE days"
echo "File extension       : .$LOG_EXT"
echo "Max depth            : ${MAX_DEPTH:-unlimited}"
echo "Dry run              : $DRY_RUN"
echo "------------------------------------------------------------"
echo ""

######################################################################################

# Build depth argument for find (empty = no restriction)
DEPTH_ARG=()
[[ -n "$MAX_DEPTH" ]] && DEPTH_ARG=(-maxdepth "$MAX_DEPTH")

# Step 1 — Compress log files older than COMPRESS_AGE days
echo "==> Compressing .$LOG_EXT files older than $COMPRESS_AGE days..."

while IFS= read -r logfile; do
  if [[ "$DRY_RUN" == true ]]; then
    echo "  [DRY-RUN] Would compress: $logfile"
  else
    if gzip -f "$logfile"; then
      log_entry "COMPRESSED | $logfile"
      echo "  Compressed: $(basename "$logfile")"
      ((COMPRESSED_COUNT++))
    else
      log_entry "ERROR      | Failed to compress: $logfile"
      echo "  ERROR: Failed to compress '$logfile'."
      ((ERRORS++))
    fi
  fi
done < <(find "$LOG_DIR" "${DEPTH_ARG[@]}" -name "*.${LOG_EXT}" -not -name "*.gz" -mtime +"$COMPRESS_AGE" -type f)

if [[ "$COMPRESSED_COUNT" -eq 0 && "$DRY_RUN" == false ]]; then
  echo "  No files to compress."
fi

######################################################################################

# Step 2 — Delete compressed log files older than DELETE_AGE days
echo ""
echo "==> Deleting .${LOG_EXT}.gz files older than $DELETE_AGE days..."

while IFS= read -r gzfile; do
  if [[ "$DRY_RUN" == true ]]; then
    echo "  [DRY-RUN] Would delete: $gzfile"
  else
    if rm -f "$gzfile"; then
      log_entry "DELETED    | $gzfile"
      echo "  Deleted: $(basename "$gzfile")"
      ((DELETED_COUNT++))
    else
      log_entry "ERROR      | Failed to delete: $gzfile"
      echo "  ERROR: Failed to delete '$gzfile'."
      ((ERRORS++))
    fi
  fi
done < <(find "$LOG_DIR" "${DEPTH_ARG[@]}" -name "*.${LOG_EXT}.gz" -mtime +"$DELETE_AGE" -type f)

if [[ "$DELETED_COUNT" -eq 0 && "$DRY_RUN" == false ]]; then
  echo "  No files to delete."
fi

######################################################################################

# Step 3 — Report disk space reclaimed in the log directory
echo ""
DISK_USAGE=$(du -sh "$LOG_DIR" 2>/dev/null | cut -f1)

echo "------------------------------------------------------------"
echo "Log Rotation completed : $(date +"%Y-%m-%d %H:%M:%S")"
if [[ "$DRY_RUN" == false ]]; then
  echo "Files compressed       : $COMPRESSED_COUNT"
  echo "Files deleted          : $DELETED_COUNT"
  echo "Errors                 : $ERRORS"
fi
echo "Current dir size       : $DISK_USAGE"
echo "Script log             : $SCRIPT_LOG"
echo "------------------------------------------------------------"

if [[ "$ERRORS" -gt 0 ]]; then
  exit 1
fi
