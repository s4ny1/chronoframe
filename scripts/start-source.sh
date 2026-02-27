#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${PROJECT_ROOT}"

ACTION="${1:-start}"

APP_PORT="${APP_PORT:-58081}"
APP_HOST="${APP_HOST:-0.0.0.0}"
DATABASE_URL="${DATABASE_URL:-./data/app.sqlite3}"
NODE_ENV_VALUE="${NODE_ENV_VALUE:-production}"
NPM_REGISTRY="${NPM_REGISTRY:-https://registry.npmmirror.com}"
PNPM_REGISTRY="${PNPM_REGISTRY:-https://registry.npmmirror.com}"
NODE_MIN_MAJOR="${NODE_MIN_MAJOR:-18}"
PNPM_PREPARE_VERSION="${PNPM_PREPARE_VERSION:-pnpm@10.18.3}"
NODE_OPTIONS_VALUE="${NODE_OPTIONS_VALUE:---max-old-space-size=4096}"

LOG_DIR="${LOG_DIR:-${PROJECT_ROOT}/logs}"
RUN_DIR="${RUN_DIR:-${PROJECT_ROOT}/run}"
PID_FILE="${PID_FILE:-${RUN_DIR}/chronoframe.pid}"
LOG_FILE="${LOG_FILE:-${LOG_DIR}/chronoframe.log}"

log() {
  echo "[start-source] $*"
}

die() {
  echo "[start-source] ERROR: $*" >&2
  exit 1
}

SUDO=""
if [[ "${EUID}" -ne 0 ]]; then
  if command -v sudo >/dev/null 2>&1; then
    SUDO="sudo"
  fi
fi

run_root() {
  if [[ -n "${SUDO}" ]]; then
    "${SUDO}" "$@"
  else
    "$@"
  fi
}

usage() {
  cat <<'EOF'
Usage:
  bash scripts/start-source.sh [start|stop|restart|status]

Environment (optional):
  APP_PORT=58081
  APP_HOST=0.0.0.0
  DATABASE_URL=./data/app.sqlite3
  NPM_REGISTRY=https://registry.npmmirror.com
  PNPM_REGISTRY=https://registry.npmmirror.com
EOF
}

detect_pkg_manager() {
  if command -v apt-get >/dev/null 2>&1; then
    echo "apt"
    return
  fi
  if command -v dnf >/dev/null 2>&1; then
    echo "dnf"
    return
  fi
  if command -v yum >/dev/null 2>&1; then
    echo "yum"
    return
  fi
  echo "unknown"
}

install_system_deps() {
  local pm
  pm="$(detect_pkg_manager)"
  log "Installing system dependencies via ${pm}..."

  case "${pm}" in
    apt)
      run_root apt-get update -y
      run_root apt-get install -y ca-certificates curl git python3 make g++ perl jq
      if ! command -v exiftool >/dev/null 2>&1; then
        run_root apt-get install -y exiftool || run_root apt-get install -y libimage-exiftool-perl
      fi
      if ! command -v node >/dev/null 2>&1; then
        run_root apt-get install -y nodejs npm
      fi
      ;;
    dnf)
      run_root dnf install -y ca-certificates curl git python3 make gcc-c++ perl jq
      if ! command -v exiftool >/dev/null 2>&1; then
        run_root dnf install -y perl-Image-ExifTool || true
      fi
      if ! command -v node >/dev/null 2>&1; then
        run_root dnf install -y nodejs npm
      fi
      ;;
    yum)
      run_root yum install -y ca-certificates curl git python3 make gcc-c++ perl jq
      if ! command -v exiftool >/dev/null 2>&1; then
        run_root yum install -y perl-Image-ExifTool || true
      fi
      if ! command -v node >/dev/null 2>&1; then
        run_root yum install -y nodejs npm
      fi
      ;;
    *)
      log "No supported package manager found, skipping system package auto-install."
      ;;
  esac
}

validate_node() {
  command -v node >/dev/null 2>&1 || die "Node.js not found after install step."
  local node_major
  node_major="$(node -p 'process.versions.node.split(".")[0]' 2>/dev/null || echo 0)"
  if [[ "${node_major}" -lt "${NODE_MIN_MAJOR}" ]]; then
    die "Node.js >= ${NODE_MIN_MAJOR} is required. Current: $(node -v). Please upgrade Node and rerun."
  fi
  log "Node.js version: $(node -v)"
}

setup_registry_mirror() {
  log "Configuring npm/pnpm registry mirrors..."
  npm config set registry "${NPM_REGISTRY}" >/dev/null
  export NPM_CONFIG_REGISTRY="${NPM_REGISTRY}"
}

ensure_pnpm() {
  if command -v corepack >/dev/null 2>&1; then
    corepack enable >/dev/null 2>&1 || true
    corepack prepare "${PNPM_PREPARE_VERSION}" --activate >/dev/null 2>&1 || true
  fi

  if ! command -v pnpm >/dev/null 2>&1; then
    log "pnpm not found, installing with npm mirror..."
    npm install -g "${PNPM_PREPARE_VERSION%%@*}" --registry "${NPM_REGISTRY}" >/dev/null
  fi

  command -v pnpm >/dev/null 2>&1 || die "pnpm installation failed."
  pnpm config set registry "${PNPM_REGISTRY}" >/dev/null
  log "pnpm version: $(pnpm -v)"
}

install_project_deps() {
  log "Installing project dependencies..."
  if ! pnpm install --frozen-lockfile; then
    log "Frozen lockfile install failed, retrying with normal install..."
    pnpm install
  fi
}

build_project() {
  log "Building project..."
  NODE_OPTIONS="${NODE_OPTIONS_VALUE}" pnpm run build:deps
  NODE_OPTIONS="${NODE_OPTIONS_VALUE}" pnpm run build
}

run_migration() {
  log "Running database migration..."
  DATABASE_URL="${DATABASE_URL}" node scripts/migrate.mjs
}

is_running() {
  if [[ ! -f "${PID_FILE}" ]]; then
    return 1
  fi
  local pid
  pid="$(cat "${PID_FILE}" 2>/dev/null || true)"
  if [[ -z "${pid}" ]]; then
    return 1
  fi
  if kill -0 "${pid}" >/dev/null 2>&1; then
    return 0
  fi
  return 1
}

start_app() {
  mkdir -p data "${LOG_DIR}" "${RUN_DIR}"

  if is_running; then
    local pid
    pid="$(cat "${PID_FILE}")"
    log "Service is already running. PID=${pid}"
    return 0
  fi

  if [[ -f "${PID_FILE}" ]]; then
    rm -f "${PID_FILE}"
  fi

  log "Starting app in background on ${APP_HOST}:${APP_PORT}..."
  nohup env \
    NODE_ENV="${NODE_ENV_VALUE}" \
    NITRO_HOST="${APP_HOST}" \
    NITRO_PORT="${APP_PORT}" \
    DATABASE_URL="${DATABASE_URL}" \
    node .output/server/index.mjs >> "${LOG_FILE}" 2>&1 &

  local pid=$!
  echo "${pid}" > "${PID_FILE}"
  sleep 1

  if kill -0 "${pid}" >/dev/null 2>&1; then
    log "Started successfully. PID=${pid}"
    log "URL: http://127.0.0.1:${APP_PORT}"
    log "Log: ${LOG_FILE}"
  else
    die "Failed to start. Check log: ${LOG_FILE}"
  fi
}

stop_app() {
  if ! is_running; then
    log "Service is not running."
    [[ -f "${PID_FILE}" ]] && rm -f "${PID_FILE}"
    return 0
  fi

  local pid
  pid="$(cat "${PID_FILE}")"
  log "Stopping PID=${pid}..."
  kill "${pid}" >/dev/null 2>&1 || true

  for _ in $(seq 1 20); do
    if ! kill -0 "${pid}" >/dev/null 2>&1; then
      rm -f "${PID_FILE}"
      log "Stopped."
      return 0
    fi
    sleep 0.5
  done

  log "Force killing PID=${pid}..."
  kill -9 "${pid}" >/dev/null 2>&1 || true
  rm -f "${PID_FILE}"
  log "Stopped."
}

status_app() {
  if is_running; then
    log "Running. PID=$(cat "${PID_FILE}") URL=http://127.0.0.1:${APP_PORT}"
  else
    log "Not running."
    return 1
  fi
}

start_flow() {
  install_system_deps
  validate_node
  setup_registry_mirror
  ensure_pnpm
  install_project_deps
  build_project
  run_migration
  start_app
}

case "${ACTION}" in
  start)
    start_flow
    ;;
  stop)
    stop_app
    ;;
  restart)
    stop_app
    start_flow
    ;;
  status)
    status_app
    ;;
  -h|--help|help)
    usage
    ;;
  *)
    usage
    die "Unknown action: ${ACTION}"
    ;;
esac
