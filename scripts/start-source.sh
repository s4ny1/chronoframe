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
if [[ "${EUID}" -ne 0 ]] && command -v sudo >/dev/null 2>&1; then
  SUDO="sudo"
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
  bash scripts/start-source.sh [install|start|status|restart|stop|update]

Actions:
  install   Install system deps + project deps + build + migrate
  start     Start app in background only
  status    Show app status by PID file
  restart   Restart app
  stop      Stop app
  update    Git pull update (ff-only, skipped when local changes exist)

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
      die "Unsupported distro: apt/dnf/yum not found."
      ;;
  esac
}

validate_node() {
  command -v node >/dev/null 2>&1 || die "Node.js not found. Run: bash scripts/start-source.sh install"
  local node_major
  node_major="$(node -p 'process.versions.node.split(".")[0]' 2>/dev/null || echo 0)"
  if [[ "${node_major}" -lt "${NODE_MIN_MAJOR}" ]]; then
    die "Node.js >= ${NODE_MIN_MAJOR} required, current: $(node -v)"
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

  command -v pnpm >/dev/null 2>&1 || die "pnpm install failed."
  pnpm config set registry "${PNPM_REGISTRY}" >/dev/null
  pnpm config delete optional >/dev/null 2>&1 || true
  log "pnpm version: $(pnpm -v)"
}

update_repo() {
  if ! command -v git >/dev/null 2>&1; then
    log "git not found, skip update."
    return 0
  fi
  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    log "Not a git repository, skip update."
    return 0
  fi
  if [[ -n "$(git status --porcelain 2>/dev/null || true)" ]]; then
    log "Working tree has local changes, skip git pull."
    return 0
  fi

  local upstream
  upstream="$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true)"
  if [[ -z "${upstream}" ]]; then
    log "No upstream branch configured, skip git pull."
    return 0
  fi

  log "Updating source code (git pull --ff-only)..."
  git fetch --all --prune
  git pull --ff-only
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
  [[ -f pnpm-lock.yaml ]] || return 0
  local oxc_version
  oxc_version="$(
    node -e "
      const fs = require('fs')
      const path = require('path')
      const base = path.join(process.cwd(), 'node_modules', '.pnpm')
      try {
        const dir = fs.readdirSync(base).find(d => /^oxc-parser@\\d+\\.\\d+\\.\\d+/.test(d))
        if (dir) {
          const pkg = path.join(base, dir, 'node_modules', 'oxc-parser', 'package.json')
          if (fs.existsSync(pkg)) {
            const json = JSON.parse(fs.readFileSync(pkg, 'utf8'))
            if (json && json.version) process.stdout.write(String(json.version))
          }
        }
      } catch {}
    " 2>/dev/null || true
  )"
  if [[ -z "${oxc_version}" ]]; then
    oxc_version="$(grep -Eo 'oxc-parser@[0-9]+\.[0-9]+\.[0-9]+' pnpm-lock.yaml | sed 's/.*@//' | sort -V | tail -n1 || true)"
  fi
  if [[ -z "${oxc_version}" ]]; then
    log "Cannot detect oxc-parser version, skip binding fix."
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
  [[ -f /etc/alpine-release ]] && libc="musl"
  binding_pkg="@oxc-parser/binding-linux-${arch}-${libc}"

  if node -e "require.resolve('${binding_pkg}')" >/dev/null 2>&1; then
    return 0
  fi

  log "Injecting missing oxc binding: ${binding_pkg}@${oxc_version}"
  local target_dir tmp_dir tarball
  target_dir="node_modules/${binding_pkg}"
  tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/oxc-binding.XXXXXX")"

  tarball="$(cd "${tmp_dir}" && npm pack --silent --registry "${NPM_REGISTRY}" "${binding_pkg}@${oxc_version}" | tail -n1)"
  [[ -n "${tarball}" && -f "${tmp_dir}/${tarball}" ]] || die "Failed to download ${binding_pkg}@${oxc_version}"

  mkdir -p "${tmp_dir}/extract"
  tar -xzf "${tmp_dir}/${tarball}" -C "${tmp_dir}/extract"
  [[ -d "${tmp_dir}/extract/package" ]] || die "Invalid package archive for ${binding_pkg}"

  rm -rf "${target_dir}"
  mkdir -p "${target_dir}"
  cp -a "${tmp_dir}/extract/package/." "${target_dir}/"
  rm -rf "${tmp_dir}"
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
  [[ -d node_modules ]] || die "node_modules not found. Run: bash scripts/start-source.sh install"
  [[ -f .output/server/index.mjs ]] || die "Build output missing. Run: bash scripts/start-source.sh install"
}

is_running() {
  [[ -f "${PID_FILE}" ]] || return 1
  local pid
  pid="$(cat "${PID_FILE}" 2>/dev/null || true)"
  [[ -n "${pid}" ]] || return 1
  kill -0 "${pid}" >/dev/null 2>&1
}

start_app() {
  mkdir -p data "${LOG_DIR}" "${RUN_DIR}"

  if is_running; then
    log "Service is already running. PID=$(cat "${PID_FILE}")"
    return 0
  fi

  [[ -f "${PID_FILE}" ]] && rm -f "${PID_FILE}"
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
  validate_node
  ensure_runtime_artifacts
  start_app
}

install_flow() {
  install_system_deps
  validate_node
  setup_registry_mirror
  ensure_pnpm
  install_project_deps
  build_project
  run_migration
  log "Install completed: system deps + project deps + build + migrate."
}

case "${ACTION}" in
  install)
    install_flow
    ;;
  start)
    start_flow
    ;;
  status)
    status_app
    ;;
  restart)
    stop_app
    start_flow
    ;;
  stop)
    stop_app
    ;;
  update)
    update_repo
    ;;
  -h|--help|help)
    usage
    ;;
  *)
    usage
    die "Unknown action: ${ACTION}"
    ;;
esac
