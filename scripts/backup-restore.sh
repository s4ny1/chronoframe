#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${PROJECT_ROOT}"

ACTION="${1:-}"
if [[ -z "${ACTION}" ]]; then
  echo "Usage: $0 <backup|restore> [options]"
  exit 1
fi
shift || true

BACKUP_DIR="${PROJECT_ROOT}/backups"
ARCHIVE_PATH=""
SERVICE_NAME="chronoframe"
CONTAINER_NAME="chronoframe"
NO_STOP=0

if docker compose version >/dev/null 2>&1; then
  COMPOSE_CMD=(docker compose)
elif command -v docker-compose >/dev/null 2>&1; then
  COMPOSE_CMD=(docker-compose)
else
  echo "Error: docker compose/docker-compose not found."
  exit 1
fi

compose() {
  "${COMPOSE_CMD[@]}" "$@"
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Error: command not found: $1"
    exit 1
  fi
}

usage() {
  cat <<'EOF'
Usage:
  backup:
    ./scripts/backup-restore.sh backup [--archive <path>] [--backup-dir <dir>] [--service <name>] [--container <name>] [--no-stop]

  restore:
    ./scripts/backup-restore.sh restore [--archive <path>] [--backup-dir <dir>] [--service <name>] [--container <name>]

Options:
  --archive      Backup archive path. If omitted:
                 backup -> backups/chronoframe-backup-YYYYmmdd-HHMMSS.tar.gz
                 restore -> latest file in backup-dir matching chronoframe-backup-*.tar.gz
  --backup-dir   Default backup directory (default: ./backups)
  --service      Docker Compose service name (default: chronoframe)
  --container    Docker container name (default: chronoframe)
  --no-stop      Backup without stopping service (may produce inconsistent sqlite backup)
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --archive)
      ARCHIVE_PATH="${2:-}"
      shift 2
      ;;
    --backup-dir)
      BACKUP_DIR="${2:-}"
      shift 2
      ;;
    --service)
      SERVICE_NAME="${2:-}"
      shift 2
      ;;
    --container)
      CONTAINER_NAME="${2:-}"
      shift 2
      ;;
    --no-stop)
      NO_STOP=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      usage
      exit 1
      ;;
  esac
done

require_cmd docker
require_cmd tar
require_cmd date
require_cmd mktemp

get_image_ref() {
  local image_ref
  image_ref="$(docker inspect --format '{{.Image}}' "${CONTAINER_NAME}" 2>/dev/null || true)"
  image_ref="$(echo "${image_ref}" | tr -d '[:space:]')"
  if [[ -z "${image_ref}" ]]; then
    image_ref="$(compose images --quiet "${SERVICE_NAME}" 2>/dev/null | head -n1 | tr -d '[:space:]' || true)"
  fi
  echo "${image_ref}"
}

backup() {
  if [[ ! -d "${PROJECT_ROOT}/data" ]]; then
    echo "Error: data directory not found: ${PROJECT_ROOT}/data"
    exit 1
  fi

  mkdir -p "${BACKUP_DIR}"
  local ts
  ts="$(date +%Y%m%d-%H%M%S)"
  if [[ -z "${ARCHIVE_PATH}" ]]; then
    ARCHIVE_PATH="${BACKUP_DIR}/chronoframe-backup-${ts}.tar.gz"
  fi
  mkdir -p "$(dirname "${ARCHIVE_PATH}")"

  local stage
  stage="$(mktemp -d "${TMPDIR:-/tmp}/chronoframe-backup.XXXXXX")"
  local should_restart=0
  local was_running=0

  cleanup() {
    if [[ ${should_restart} -eq 1 ]]; then
      echo "Restarting service ${SERVICE_NAME}..."
      compose up -d "${SERVICE_NAME}" >/dev/null
    fi
    rm -rf "${stage}"
  }
  trap cleanup EXIT

  local image_ref
  image_ref="$(get_image_ref)"
  if [[ -z "${image_ref}" ]]; then
    echo "Error: cannot find image for ${CONTAINER_NAME}/${SERVICE_NAME}. Start/build container first."
    exit 1
  fi

  if docker ps --format '{{.Names}}' | grep -Fxq "${CONTAINER_NAME}"; then
    was_running=1
  fi

  if [[ ${was_running} -eq 1 && ${NO_STOP} -eq 0 ]]; then
    echo "Stopping service ${SERVICE_NAME} for consistent backup..."
    compose stop "${SERVICE_NAME}" >/dev/null
    should_restart=1
  elif [[ ${was_running} -eq 1 && ${NO_STOP} -eq 1 ]]; then
    echo "Warning: --no-stop enabled, backup may be inconsistent."
  fi

  echo "Exporting docker image: ${image_ref}"
  docker image save -o "${stage}/docker-image.tar" "${image_ref}" >/dev/null

  echo "Copying data directory..."
  cp -a "${PROJECT_ROOT}/data" "${stage}/data"

  if [[ -f "${PROJECT_ROOT}/docker-compose.yml" ]]; then
    cp -a "${PROJECT_ROOT}/docker-compose.yml" "${stage}/docker-compose.yml"
  fi
  if [[ -f "${PROJECT_ROOT}/.env" ]]; then
    cp -a "${PROJECT_ROOT}/.env" "${stage}/.env"
  fi

  cat > "${stage}/manifest.txt" <<EOF
timestamp=${ts}
service=${SERVICE_NAME}
container=${CONTAINER_NAME}
image_ref=${image_ref}
project_root=${PROJECT_ROOT}
EOF

  echo "Packing backup archive..."
  tar -C "${stage}" -czf "${ARCHIVE_PATH}" .

  echo "Backup completed: ${ARCHIVE_PATH}"
}

restore() {
  if [[ -z "${ARCHIVE_PATH}" ]]; then
    ARCHIVE_PATH="$(ls -1t "${BACKUP_DIR}"/chronoframe-backup-*.tar.gz 2>/dev/null | head -n1 || true)"
  fi

  if [[ -z "${ARCHIVE_PATH}" || ! -f "${ARCHIVE_PATH}" ]]; then
    echo "Error: backup archive not found."
    exit 1
  fi

  local ts
  ts="$(date +%Y%m%d-%H%M%S)"
  local stage
  stage="$(mktemp -d "${TMPDIR:-/tmp}/chronoframe-restore.XXXXXX")"
  trap 'rm -rf "${stage}"' EXIT

  echo "Extracting archive: ${ARCHIVE_PATH}"
  tar -C "${stage}" -xzf "${ARCHIVE_PATH}"

  if [[ ! -f "${stage}/docker-image.tar" ]]; then
    echo "Error: docker-image.tar not found in archive."
    exit 1
  fi
  if [[ ! -d "${stage}/data" ]]; then
    echo "Error: data directory not found in archive."
    exit 1
  fi

  echo "Stopping current services..."
  compose down >/dev/null || true

  echo "Loading docker image..."
  docker image load -i "${stage}/docker-image.tar" >/dev/null

  local data_backup_path=""
  if [[ -d "${PROJECT_ROOT}/data" ]]; then
    data_backup_path="${PROJECT_ROOT}/data.before-restore-${ts}"
    mv "${PROJECT_ROOT}/data" "${data_backup_path}"
  fi
  cp -a "${stage}/data" "${PROJECT_ROOT}/data"

  if [[ -f "${stage}/docker-compose.yml" ]]; then
    if [[ -f "${PROJECT_ROOT}/docker-compose.yml" ]]; then
      cp -a "${PROJECT_ROOT}/docker-compose.yml" "${PROJECT_ROOT}/docker-compose.yml.before-restore-${ts}"
    fi
    cp -a "${stage}/docker-compose.yml" "${PROJECT_ROOT}/docker-compose.yml"
  fi

  if [[ -f "${stage}/.env" ]]; then
    if [[ -f "${PROJECT_ROOT}/.env" ]]; then
      cp -a "${PROJECT_ROOT}/.env" "${PROJECT_ROOT}/.env.before-restore-${ts}"
    fi
    cp -a "${stage}/.env" "${PROJECT_ROOT}/.env"
  fi

  echo "Starting service ${SERVICE_NAME}..."
  if ! compose up -d --no-build "${SERVICE_NAME}" >/dev/null; then
    compose up -d "${SERVICE_NAME}" >/dev/null
  fi

  echo "Restore completed from: ${ARCHIVE_PATH}"
  if [[ -n "${data_backup_path}" ]]; then
    echo "Previous data backup: ${data_backup_path}"
  fi
}

case "${ACTION}" in
  backup)
    backup
    ;;
  restore)
    restore
    ;;
  -h|--help|help)
    usage
    ;;
  *)
    echo "Unknown action: ${ACTION}"
    usage
    exit 1
    ;;
esac
