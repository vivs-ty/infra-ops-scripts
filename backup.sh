#!/bin/bash

######################################################################################

# Export Path Variable
export PATH=$PATH:/opt

######################################################################################

# Usage help
usage() {
  echo ""
  echo "Backup Utility"
  echo ""
  echo "SYNTAX  = ./backup.sh <SOURCE_DIR> <BACKUP_DIR> [RETENTION_DAYS] [OPTIONS]"
  echo ""
  echo "  SOURCE_DIR     - Directory to back up"
  echo "  BACKUP_DIR     - Directory where backup archives will be stored"
  echo "  RETENTION_DAYS - Number of days to keep backups (default: 7)"
  echo ""
  echo "OPTIONS:"
  echo "  -r, --remote  USER@HOST:PATH  - Rsync archive to remote destination over SSH"
  echo "  -i, --identity FILE           - SSH identity file for rsync (optional)"
  echo ""
  echo "EXAMPLES:"
  echo "  ./backup.sh /etc/nginx /backups"
  echo "  ./backup.sh /var/www/html /backups 14"
  echo "  ./backup.sh /etc/nginx /backups 7 --remote backups@10.0.0.5:/mnt/remote-backups"
  echo "  ./backup.sh /etc/nginx /backups 7 --remote backups@10.0.0.5:/mnt/remote-backups --identity ~/.ssh/backup_key"
  echo ""
  exit 1
}

######################################################################################

SOURCE_DIR="$1"
BACKUP_DIR="$2"
RETENTION_DAYS="${3:-7}"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
HOSTNAME=$(hostname)
SOURCE_NAME=$(basename "$SOURCE_DIR")
ARCHIVE_NAME="${HOSTNAME}_${SOURCE_NAME}_${TIMESTAMP}.tar.gz"
LOG_FILE="${BACKUP_DIR}/backup.log"
REMOTE_DEST=""
SSH_IDENTITY=""

# Positional args already consumed; parse remaining options
shift 3 2>/dev/null || shift $#
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    -r|--remote)   REMOTE_DEST="$2";   shift 2 ;;
    -i|--identity) SSH_IDENTITY="$2"; shift 2 ;;
    -h|--help)     usage ;;
    *) echo "ERROR: Unknown option '$1'."; usage ;;
  esac
done

######################################################################################

# Validate inputs
if [[ -z "$SOURCE_DIR" || -z "$BACKUP_DIR" ]]; then
  echo "ERROR: SOURCE_DIR and BACKUP_DIR are required."
  usage
fi

if [[ ! -d "$SOURCE_DIR" ]]; then
  echo "ERROR: Source directory '$SOURCE_DIR' does not exist."
  exit 1
fi

if ! [[ "$RETENTION_DAYS" =~ ^[0-9]+$ ]] || [[ "$RETENTION_DAYS" -lt 1 ]]; then
  echo "ERROR: RETENTION_DAYS must be a positive integer >= 1."
  exit 1
fi

######################################################################################

# Create backup directory if it doesn't exist
if [[ ! -d "$BACKUP_DIR" ]]; then
  echo "Backup directory '$BACKUP_DIR' does not exist. Creating it..."
  mkdir -p "$BACKUP_DIR" || { echo "ERROR: Failed to create backup directory."; exit 1; }
fi

######################################################################################

# Create the backup archive
echo "------------------------------------------------------------"
echo "Backup started   : $(date)"
echo "Source           : $SOURCE_DIR"
echo "Destination      : $BACKUP_DIR/$ARCHIVE_NAME"
echo "Retention        : $RETENTION_DAYS days"
[[ -n "$REMOTE_DEST" ]] && echo "Remote           : $REMOTE_DEST"
echo "------------------------------------------------------------"

if tar -czf "$BACKUP_DIR/$ARCHIVE_NAME" -C "$(dirname "$SOURCE_DIR")" "$SOURCE_NAME"; then
  ARCHIVE_SIZE=$(du -sh "$BACKUP_DIR/$ARCHIVE_NAME" | cut -f1)
  echo "Backup created   : $ARCHIVE_NAME ($ARCHIVE_SIZE)"
  echo "$(date) | SUCCESS | $ARCHIVE_NAME | $ARCHIVE_SIZE" >> "$LOG_FILE"
else
  echo "ERROR: Backup failed for '$SOURCE_DIR'."
  echo "$(date) | FAILED  | $ARCHIVE_NAME" >> "$LOG_FILE"
  exit 1
fi

######################################################################################

# Verify the archive is readable
echo ""
echo "Verifying archive integrity..."
if tar -tzf "$BACKUP_DIR/$ARCHIVE_NAME" > /dev/null 2>&1; then
  echo "Integrity check  : PASSED"
else
  echo "ERROR: Archive integrity check failed. The backup may be corrupt."
  echo "$(date) | CORRUPT | $ARCHIVE_NAME" >> "$LOG_FILE"
  exit 1
fi

######################################################################################

# Rsync to remote destination (if configured)
if [[ -n "$REMOTE_DEST" ]]; then
  echo ""
  echo "Syncing archive to remote destination..."

  if ! command -v rsync &> /dev/null; then
    echo "ERROR: rsync is required for remote transfer but is not installed."
    echo "$(date) | RSYNC_SKIP | rsync not found" >> "$LOG_FILE"
  else
    RSYNC_OPTS=(-az --progress)
    if [[ -n "$SSH_IDENTITY" ]]; then
      RSYNC_OPTS+=(-e "ssh -i ${SSH_IDENTITY} -o StrictHostKeyChecking=no")
    fi

    if rsync "${RSYNC_OPTS[@]}" "$BACKUP_DIR/$ARCHIVE_NAME" "$REMOTE_DEST/"; then
      echo "Remote sync      : SUCCESS → $REMOTE_DEST"
      echo "$(date) | RSYNC_OK | $ARCHIVE_NAME | $REMOTE_DEST" >> "$LOG_FILE"
    else
      echo "ERROR: Remote sync failed. Archive is still available locally."
      echo "$(date) | RSYNC_FAIL | $ARCHIVE_NAME | $REMOTE_DEST" >> "$LOG_FILE"
      # Do not exit — local backup succeeded
    fi
  fi
fi

######################################################################################

# Remove backups older than RETENTION_DAYS
echo ""
echo "Removing backups older than $RETENTION_DAYS days..."
DELETED_COUNT=0
while IFS= read -r old_backup; do
  echo "  Deleting: $(basename "$old_backup")"
  rm -f "$old_backup"
  echo "$(date) | DELETED | $(basename "$old_backup")" >> "$LOG_FILE"
  ((DELETED_COUNT++))
done < <(find "$BACKUP_DIR" -maxdepth 1 -name "${HOSTNAME}_${SOURCE_NAME}_*.tar.gz" -mtime +"$RETENTION_DAYS")

if [[ "$DELETED_COUNT" -eq 0 ]]; then
  echo "  No old backups to remove."
else
  echo "  Removed $DELETED_COUNT old backup(s)."
fi

######################################################################################

# Summary
echo ""
echo "------------------------------------------------------------"
echo "Backup completed : $(date)"
echo "Archive          : $BACKUP_DIR/$ARCHIVE_NAME"
echo "Log              : $LOG_FILE"
echo "------------------------------------------------------------"
