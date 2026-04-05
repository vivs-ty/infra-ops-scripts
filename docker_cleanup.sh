#!/bin/bash

######################################################################################

# Export Path Variable
export PATH=$PATH:/opt

######################################################################################

usage() {
  echo ""
  echo "Docker Cleanup Utility"
  echo ""
  echo "SYNTAX  = ./docker_cleanup.sh [OPTIONS]"
  echo ""
  echo "OPTIONS:"
  echo "  -c, --containers  - Remove stopped containers"
  echo "  -i, --images      - Remove dangling (untagged) images"
  echo "  -v, --volumes     - Remove unused volumes"
  echo "  -n, --networks    - Remove unused networks"
  echo "  -a, --all         - Run all of the above (default if no options given)"
  echo "  --dry-run         - Show what would be removed without making changes"
  echo ""
  echo "EXAMPLES:"
  echo "  ./docker_cleanup.sh"
  echo "  ./docker_cleanup.sh --containers --images"
  echo "  ./docker_cleanup.sh --all --dry-run"
  echo ""
  exit 1
}

######################################################################################

DO_CONTAINERS=false
DO_IMAGES=false
DO_VOLUMES=false
DO_NETWORKS=false
DRY_RUN=false
ANY_FLAG=false

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    -c|--containers) DO_CONTAINERS=true; ANY_FLAG=true; shift ;;
    -i|--images)     DO_IMAGES=true;     ANY_FLAG=true; shift ;;
    -v|--volumes)    DO_VOLUMES=true;    ANY_FLAG=true; shift ;;
    -n|--networks)   DO_NETWORKS=true;   ANY_FLAG=true; shift ;;
    -a|--all)        DO_CONTAINERS=true; DO_IMAGES=true; DO_VOLUMES=true; DO_NETWORKS=true; ANY_FLAG=true; shift ;;
    --dry-run)       DRY_RUN=true; shift ;;
    -h|--help)       usage ;;
    *) echo "ERROR: Unknown option '$1'."; usage ;;
  esac
done

# Default: run all if no flags given
if [[ "$ANY_FLAG" == false ]]; then
  DO_CONTAINERS=true; DO_IMAGES=true; DO_VOLUMES=true; DO_NETWORKS=true
fi

######################################################################################

if ! command -v docker &>/dev/null; then
  echo "ERROR: docker is not installed or not in PATH."
  exit 1
fi

######################################################################################

TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")

echo "------------------------------------------------------------"
echo "Docker Cleanup started : $TIMESTAMP"
echo "Dry run                : $DRY_RUN"
echo "------------------------------------------------------------"

# -----------------------------------------------------------------------
# Stopped containers
# -----------------------------------------------------------------------
if [[ "$DO_CONTAINERS" == true ]]; then
  echo ""
  echo "==> Stopped containers..."
  STOPPED=$(docker ps -a --filter "status=exited" --filter "status=created" --format "{{.ID}}  {{.Names}}  {{.Status}}")
  if [[ -z "$STOPPED" ]]; then
    echo "  None found."
  else
    echo "$STOPPED" | while read -r line; do echo "  $line"; done
    if [[ "$DRY_RUN" == false ]]; then
      if docker container prune -f; then
        echo "  Stopped containers removed."
      else
        echo "  ERROR: docker container prune failed (exit $?)."
      fi
    fi
  fi
fi

# -----------------------------------------------------------------------
# Dangling images
# -----------------------------------------------------------------------
if [[ "$DO_IMAGES" == true ]]; then
  echo ""
  echo "==> Dangling images (untagged)..."
  DANGLING=$(docker images --filter "dangling=true" --format "{{.ID}}  {{.Repository}}:{{.Tag}}  {{.Size}}")
  if [[ -z "$DANGLING" ]]; then
    echo "  None found."
  else
    echo "$DANGLING" | while read -r line; do echo "  $line"; done
    if [[ "$DRY_RUN" == false ]]; then
      if docker image prune -f; then
        echo "  Dangling images removed."
      else
        echo "  ERROR: docker image prune failed (exit $?)."
      fi
    fi
  fi
fi

# -----------------------------------------------------------------------
# Unused volumes
# -----------------------------------------------------------------------
if [[ "$DO_VOLUMES" == true ]]; then
  echo ""
  echo "==> Unused volumes..."
  VOLUMES=$(docker volume ls --filter "dangling=true" --format "{{.Name}}")
  if [[ -z "$VOLUMES" ]]; then
    echo "  None found."
  else
    echo "$VOLUMES" | while read -r line; do echo "  $line"; done
    if [[ "$DRY_RUN" == false ]]; then
      if docker volume prune -f; then
        echo "  Unused volumes removed."
      else
        echo "  ERROR: docker volume prune failed (exit $?)."
      fi
    fi
  fi
fi

# -----------------------------------------------------------------------
# Unused networks
# -----------------------------------------------------------------------
if [[ "$DO_NETWORKS" == true ]]; then
  echo ""
  echo "==> Unused networks..."
  NETWORKS=$(docker network ls --filter "dangling=true" --format "{{.ID}}  {{.Name}}")
  if [[ -z "$NETWORKS" ]]; then
    echo "  None found."
  else
    echo "$NETWORKS" | while read -r line; do echo "  $line"; done
    if [[ "$DRY_RUN" == false ]]; then
      if docker network prune -f; then
        echo "  Unused networks removed."
      else
        echo "  ERROR: docker network prune failed (exit $?)."
      fi
    fi
  fi
fi

# -----------------------------------------------------------------------
# Disk usage summary
# -----------------------------------------------------------------------
echo ""
echo "------------------------------------------------------------"
echo "Docker disk usage after cleanup:"
docker system df
echo "------------------------------------------------------------"
echo "Docker Cleanup completed : $(date +"%Y-%m-%d %H:%M:%S")"
echo "------------------------------------------------------------"
