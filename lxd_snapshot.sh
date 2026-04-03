#!/bin/bash

######################################################################################

# Export Path Variable
export PATH=$PATH:/opt

######################################################################################

usage() {
  echo ""
  echo "LXD Container Snapshot Manager"
  echo ""
  echo "SYNTAX  = ./lxd_snapshot.sh <COMMAND> [OPTIONS]"
  echo ""
  echo "COMMANDS:"
  echo "  create   <CONTAINER>              - Create a snapshot of a container"
  echo "  list     <CONTAINER>              - List all snapshots for a container"
  echo "  restore  <CONTAINER> <SNAPSHOT>   - Restore a container to a snapshot"
  echo "  delete   <CONTAINER> <SNAPSHOT>   - Delete a specific snapshot"
  echo "  auto     <CONTAINER>              - Create snapshot + prune old ones"
  echo "  all                               - Snapshot all running containers"
  echo ""
  echo "OPTIONS:"
  echo "  -r, --retain  NUM   - Number of snapshots to keep during auto/all (default: 5)"
  echo "  -l, --log     FILE  - Log file path (default: /var/log/lxd_snapshot.log)"
  echo ""
  echo "EXAMPLES:"
  echo "  ./lxd_snapshot.sh create rocky"
  echo "  ./lxd_snapshot.sh list rocky"
  echo "  ./lxd_snapshot.sh restore rocky snap0"
  echo "  ./lxd_snapshot.sh delete rocky snap0"
  echo "  ./lxd_snapshot.sh auto rocky --retain 7"
  echo "  ./lxd_snapshot.sh all --retain 3"
  echo ""
  exit 1
}

######################################################################################

COMMAND="$1"
if [[ -z "$COMMAND" ]]; then usage; fi
shift

RETAIN=5
LOG_FILE="/var/log/lxd_snapshot.log"

# Parse remaining options
POSITIONAL=()
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    -r|--retain) RETAIN="$2"; shift 2 ;;
    -l|--log)    LOG_FILE="$2"; shift 2 ;;
    -h|--help)   usage ;;
    *)           POSITIONAL+=("$1"); shift ;;
  esac
done

CONTAINER="${POSITIONAL[0]}"
SNAPSHOT="${POSITIONAL[1]}"

######################################################################################

if ! command -v lxc &>/dev/null; then
  echo "ERROR: lxc is not installed or not in PATH."
  exit 1
fi

log_entry() {
  echo "$(date +"%Y-%m-%d %H:%M:%S") | $1" >> "$LOG_FILE"
}

######################################################################################

do_create() {
  local container="$1"
  local snap_name="snap_$(date +%Y%m%d_%H%M%S)"

  echo "Creating snapshot '$snap_name' for container '$container'..."
  if lxc snapshot "$container" "$snap_name"; then
    echo "Snapshot '$snap_name' created successfully."
    log_entry "CREATED | $container | $snap_name"
    echo "$snap_name"  # Return name for use in auto
  else
    echo "ERROR: Failed to create snapshot for '$container'."
    log_entry "ERROR | FAILED to create snapshot for $container"
    exit 1
  fi
}

do_list() {
  local container="$1"
  echo "Snapshots for container '$container':"
  echo "------------------------------------------------------------"
  lxc info "$container" | grep -A 100 "Snapshots:" | tail -n +2 | grep -v '^$' || echo "  No snapshots found."
}

do_restore() {
  local container="$1"
  local snapshot="$2"
  echo "Restoring '$container' to snapshot '$snapshot'..."
  echo "WARNING: This will overwrite the current state of '$container'."
  read -p "Are you sure? (yes/no): " CONFIRM
  if [[ "$CONFIRM" != "yes" ]]; then
    echo "Aborted."
    exit 0
  fi
  if lxc restore "$container" "$snapshot"; then
    echo "Container '$container' restored to '$snapshot'."
    log_entry "RESTORED | $container | $snapshot"
  else
    echo "ERROR: Restore failed."
    log_entry "ERROR | FAILED to restore $container to $snapshot"
    exit 1
  fi
}

do_delete() {
  local container="$1"
  local snapshot="$2"
  echo "Deleting snapshot '$snapshot' from container '$container'..."
  if lxc delete "${container}/${snapshot}"; then
    echo "Snapshot '$snapshot' deleted."
    log_entry "DELETED | $container | $snapshot"
  else
    echo "ERROR: Failed to delete snapshot '$snapshot'."
    log_entry "ERROR | FAILED to delete $container/$snapshot"
    exit 1
  fi
}

do_prune() {
  local container="$1"
  # List snapshots sorted by name (timestamp-based names sort correctly)
  mapfile -t SNAPS < <(lxc info "$container" 2>/dev/null \
    | grep -A 100 "Snapshots:" | tail -n +2 \
    | awk '/^snap_/{print $1}' | sort)

  local count="${#SNAPS[@]}"
  local to_delete=$(( count - RETAIN ))

  if [[ "$to_delete" -le 0 ]]; then
    echo "  Retention OK — $count snapshot(s), keeping up to $RETAIN."
    return
  fi

  echo "  Pruning $to_delete old snapshot(s) (keeping $RETAIN)..."
  for (( i=0; i<to_delete; i++ )); do
    local old="${SNAPS[$i]}"
    if lxc delete "${container}/${old}" 2>/dev/null; then
      echo "  Pruned: $old"
      log_entry "PRUNED | $container | $old"
    fi
  done
}

######################################################################################

case "$COMMAND" in

  create)
    [[ -z "$CONTAINER" ]] && { echo "ERROR: Please provide a container name."; usage; }
    do_create "$CONTAINER"
    ;;

  list)
    [[ -z "$CONTAINER" ]] && { echo "ERROR: Please provide a container name."; usage; }
    do_list "$CONTAINER"
    ;;

  restore)
    [[ -z "$CONTAINER" || -z "$SNAPSHOT" ]] && { echo "ERROR: Please provide a container name and snapshot name."; usage; }
    do_restore "$CONTAINER" "$SNAPSHOT"
    ;;

  delete)
    [[ -z "$CONTAINER" || -z "$SNAPSHOT" ]] && { echo "ERROR: Please provide a container name and snapshot name."; usage; }
    do_delete "$CONTAINER" "$SNAPSHOT"
    ;;

  auto)
    [[ -z "$CONTAINER" ]] && { echo "ERROR: Please provide a container name."; usage; }
    echo "==> Auto snapshot: $CONTAINER (retain: $RETAIN)"
    do_create "$CONTAINER" > /dev/null
    do_prune  "$CONTAINER"
    echo "Done."
    ;;

  all)
    echo "==> Snapshotting all running containers (retain: $RETAIN)..."
    while IFS= read -r c; do
      echo ""
      echo "Container: $c"
      do_create "$c" > /dev/null
      do_prune  "$c"
    done < <(lxc list --format csv -c n,s | awk -F, '$2=="RUNNING"{print $1}')
    echo ""
    echo "Done."
    ;;

  *)
    echo "ERROR: Unknown command '$COMMAND'."
    usage
    ;;
esac

######################################################################################
