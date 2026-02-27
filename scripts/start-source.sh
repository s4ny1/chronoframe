#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${PROJECT_ROOT}"

ACTION="${1:-start}"

APP_PORT="${APP_PORT:-58081}"
APP_HOST="${APP_HOST:-0.0.0.0}"
DATABASE_URL="${DATABASE_URL:-./data/app.sqlite3}"
UPDATE_ON_START="${UPDATE_ON_START:-1}"
NODE_ENV_VALUE="${NODE_ENV_VALUE:-production}"
NPM_REGISTRY="${NPM_REGISTRY:-https://registry.npmmirror.com}"
PNPM_REGISTRY="${PNPM_REGISTRY:-https://registry.npmmirror.com}"
NODE_MIN_MAJOR="${NODE_MIN_MAJOR:-18}"
PNPM_PREPARE_VERSION="${PNPM_PREPARE_VERSION:-pnpm@10.18.3}"
NODE_OPTIONS_VALUE="${NODE_OPTIONS_VALUE:---max-old-space-size=4096}"
SYSTEMD_SERVICE_NAME="${SYSTEMD_SERVICE_NAME:-chronoframe-source}"
REPO_UPDATED=0

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
  bash scripts/start-source.sh [start|stop|restart|status|update|install|uninstall]

Note:
  start/stop/restart/status operate systemd service.
  Use install first to register and enable auto-start.

Environment (optional):
  APP_PORT=58081
  APP_HOST=0.0.0.0
  DATABASE_URL=./data/app.sqlite3
  UPDATE_ON_START=1
  SYSTEMD_SERVICE_NAME=chronoframe-source
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
  npm config delete optional >/dev/null 2>&1 || true
  npm config delete omit >/dev/null 2>&1 || true
  export NPM_CONFIG_REGISTRY="${NPM_REGISTRY}"
  unset NPM_CONFIG_OMIT npm_config_omit || true
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
  pnpm config delete optional >/dev/null 2>&1 || true
  log "pnpm version: $(pnpm -v)"
}

update_repo() {
  REPO_UPDATED=0
  if ! command -v git >/dev/null 2>&1; then
    log "git not found, skipping repository update."
    return 0
  fi

  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    log "Not a git repository, skipping update."
    return 0
  fi

  if [[ -n "$(git status --porcelain 2>/dev/null || true)" ]]; then
    log "Working tree has local changes, skipping auto git pull to avoid conflicts."
    return 0
  fi

  local upstream
  upstream="$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true)"
  if [[ -z "${upstream}" ]]; then
    log "No upstream branch configured, skipping git pull."
    return 0
  fi

  log "Updating source code (git pull --ff-only)..."
  local before after
  before="$(git rev-parse HEAD 2>/dev/null || echo '')"
  git fetch --all --prune
  git pull --ff-only
  after="$(git rev-parse HEAD 2>/dev/null || echo '')"
  if [[ -n "${before}" && -n "${after}" && "${before}" != "${after}" ]]; then
    REPO_UPDATED=1
    log "Repository updated: ${before:0:7} -> ${after:0:7}"
  else
    log "Repository already up to date."
  fi
}

service_exists() {
  if ! command -v systemctl >/dev/null 2>&1; then
    return 1
  fi
  systemctl list-unit-files "${SYSTEMD_SERVICE_NAME}.service" --no-legend 2>/dev/null | grep -q "${SYSTEMD_SERVICE_NAME}.service"
}

service_action() {
  local action="$1"
  command -v systemctl >/dev/null 2>&1 || die "systemctl not found."
  service_exists || die "Service ${SYSTEMD_SERVICE_NAME} not installed. Run: bash scripts/start-source.sh install"

  case "${action}" in
    status)
      run_root systemctl --no-pager --full status "${SYSTEMD_SERVICE_NAME}"
      ;;
    start|stop|restart)
      run_root systemctl "${action}" "${SYSTEMD_SERVICE_NAME}"
      run_root systemctl --no-pager --full status "${SYSTEMD_SERVICE_NAME}" || true
      ;;
    *)
      die "Unsupported service action: ${action}"
      ;;
  esac
}

install_service() {
  command -v systemctl >/dev/null 2>&1 || die "systemctl not found, cannot install systemd service."

  local service_file="/etc/systemd/system/${SYSTEMD_SERVICE_NAME}.service"
  local script_path="${PROJECT_ROOT}/scripts/start-source.sh"
  local pid_file_abs="${PROJECT_ROOT}/run/chronoframe.pid"

  bootstrap_runtime

  if [[ ! -f "${script_path}" ]]; then
    die "script not found: ${script_path}"
  fi

  log "Installing systemd service: ${SYSTEMD_SERVICE_NAME}"
  run_root bash -c "cat > '${service_file}' <<EOF
[Unit]
Description=ChronoFrame Source Service
After=network-online.target
Wants=network-online.target

[Service]
Type=forking
WorkingDirectory=${PROJECT_ROOT}
ExecStart=/usr/bin/env bash ${script_path} daemon-start
ExecStop=/usr/bin/env bash ${script_path} daemon-stop
PIDFile=${pid_file_abs}
Restart=on-failure
RestartSec=5
Environment=APP_PORT=${APP_PORT}
Environment=APP_HOST=${APP_HOST}
Environment=DATABASE_URL=${DATABASE_URL}
Environment=UPDATE_ON_START=${UPDATE_ON_START}
Environment=NPM_REGISTRY=${NPM_REGISTRY}
Environment=PNPM_REGISTRY=${PNPM_REGISTRY}
Environment=NODE_ENV_VALUE=${NODE_ENV_VALUE}
Environment=NODE_OPTIONS_VALUE=${NODE_OPTIONS_VALUE}

[Install]
WantedBy=multi-user.target
EOF"

  run_root systemctl daemon-reload
  run_root systemctl enable --now "${SYSTEMD_SERVICE_NAME}"
  run_root systemctl --no-pager --full status "${SYSTEMD_SERVICE_NAME}" || true

  log "Service installed and enabled: ${SYSTEMD_SERVICE_NAME}"
  log "Boot auto-start: enabled"
}

uninstall_service() {
  command -v systemctl >/dev/null 2>&1 || die "systemctl not found, cannot uninstall systemd service."

  local service_file="/etc/systemd/system/${SYSTEMD_SERVICE_NAME}.service"
  log "Uninstalling systemd service: ${SYSTEMD_SERVICE_NAME}"

  run_root systemctl disable --now "${SYSTEMD_SERVICE_NAME}" >/dev/null 2>&1 || true
  if run_root test -f "${service_file}"; then
    run_root rm -f "${service_file}"
  fi
  run_root systemctl daemon-reload
  run_root systemctl reset-failed "${SYSTEMD_SERVICE_NAME}" >/dev/null 2>&1 || true

  log "Service removed: ${SYSTEMD_SERVICE_NAME}"
}

install_project_deps() {
  log "Installing project dependencies..."
  local install_log
  install_log="$(mktemp "${TMPDIR:-/tmp}/chronoframe-pnpm-install.XXXXXX.log")"

  if pnpm install --frozen-lockfile 2>&1 | tee "${install_log}"; then
    rm -f "${install_log}"
    return 0
  fi

  if grep -qiE 'Cannot find native binding|@oxc-parser/binding-linux|parser\.linux-.*\.node' "${install_log}"; then
    log "Detected oxc native binding issue, running recovery install..."
    rm -rf node_modules
    if ! pnpm install --frozen-lockfile --ignore-scripts; then
      pnpm install --ignore-scripts
    fi
    ensure_oxc_native_binding
    pnpm exec nuxt prepare
  else
    log "Frozen lockfile install failed, retrying with normal install..."
    pnpm install
  fi

  rm -f "${install_log}"
}

ensure_oxc_native_binding() {
  if [[ ! -f pnpm-lock.yaml ]]; then
    return 0
  fi

  local oxc_version
  oxc_version="$(grep -m1 -Eo 'oxc-parser@[0-9]+\.[0-9]+\.[0-9]+' pnpm-lock.yaml | sed 's/.*@//' || true)"
  if [[ -z "${oxc_version}" ]]; then
    log "Cannot detect oxc-parser version from pnpm-lock.yaml, skip binding fix."
    return 0
  fi

  local arch libc binding_pkg
  arch="$(node -p 'process.arch' 2>/dev/null || echo '')"
  case "${arch}" in
    x64|arm64) ;;
    *)
      log "Unsupported arch for oxc auto-fix: ${arch:-unknown}, skip."
      return 0
      ;;
  esac

  libc="gnu"
  if [[ -f /etc/alpine-release ]]; then
    libc="musl"
  fi

  binding_pkg="@oxc-parser/binding-linux-${arch}-${libc}"
  if node -e "require.resolve('${binding_pkg}')" >/dev/null 2>&1; then
    log "oxc binding already present: ${binding_pkg}"
    return 0
  fi

  log "Installing missing oxc binding: ${binding_pkg}@${oxc_version}"
  npm install --no-save --registry "${NPM_REGISTRY}" "${binding_pkg}@${oxc_version}"
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

ensure_runtime_artifacts() {
  if [[ ! -d node_modules ]]; then
    die "node_modules not found. Run: bash scripts/start-source.sh install"
  fi
  if [[ ! -f .output/server/index.mjs ]]; then
    die "Build output not found (.output/server/index.mjs). Run: bash scripts/start-source.sh install"
  fi
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
  if [[ "${UPDATE_ON_START}" == "1" ]]; then
    update_repo
  fi
  if [[ "${REPO_UPDATED}" == "1" ]]; then
    setup_registry_mirror
    ensure_pnpm
    install_project_deps
    build_project
  fi
  ensure_runtime_artifacts
  run_migration
  start_app
}

bootstrap_runtime() {
  install_system_deps
  validate_node
  setup_registry_mirror
  ensure_pnpm
  install_project_deps
  build_project
  run_migration
}

case "${ACTION}" in
  start)
    service_action start
    ;;
  stop)
    service_action stop
    ;;
  restart)
    service_action restart
    ;;
  status)
    service_action status
    ;;
  update)
    update_repo
    ;;
  daemon-start)
    start_flow
    ;;
  daemon-stop)
    stop_app
    ;;
  install)
    install_service
    ;;
  uninstall)
    uninstall_service
    ;;
  -h|--help|help)
    usage
    ;;
  *)
    usage
    die "Unknown action: ${ACTION}"
    ;;
esac
