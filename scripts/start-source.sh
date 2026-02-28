#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${PROJECT_ROOT}"

ENV_FILE="${ENV_FILE:-${PROJECT_ROOT}/.env}"
if [[ -f "${ENV_FILE}" ]]; then
  set -a
  # shellcheck disable=SC1090
  . "${ENV_FILE}"
  set +a
fi

ACTION="${1:-start}"

APP_PORT="${APP_PORT:-58081}"
APP_HOST="${APP_HOST:-0.0.0.0}"
DATABASE_URL="${DATABASE_URL:-./data/app.sqlite3}"
NODE_ENV_VALUE="${NODE_ENV_VALUE:-production}"
NPM_REGISTRY="${NPM_REGISTRY:-https://registry.npmmirror.com}"
PNPM_REGISTRY="${PNPM_REGISTRY:-https://registry.npmmirror.com}"
PNPM_PREPARE_VERSION="${PNPM_PREPARE_VERSION:-pnpm@10.18.3}"
NODE_OPTIONS_VALUE="${NODE_OPTIONS_VALUE:-}"
NODE_INSTALL_VERSION="${NODE_INSTALL_VERSION:-22.12.0}"
NODE_MIRROR="${NODE_MIRROR:-https://npmmirror.com/mirrors/node}"
CI_MODE="${CI_MODE:-1}"
NUXT_TELEMETRY_DISABLED_VALUE="${NUXT_TELEMETRY_DISABLED_VALUE:-1}"
AUTO_SWAP_FOR_BUILD="${AUTO_SWAP_FOR_BUILD:-1}"
BUILD_MIN_MEMORY_MB="${BUILD_MIN_MEMORY_MB:-4096}"
BUILD_SWAP_FILE="${BUILD_SWAP_FILE:-/swapfile-chronoframe}"
BUILD_SWAP_MB="${BUILD_SWAP_MB:-2048}"
SESSION_PASSWORD_FILE="${SESSION_PASSWORD_FILE:-${PROJECT_ROOT}/data/session-password}"
SESSION_PASSWORD_MIN_LEN="${SESSION_PASSWORD_MIN_LEN:-32}"

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

ensure_session_password() {
  if [[ -z "${NUXT_SESSION_PASSWORD:-}" && -f "${SESSION_PASSWORD_FILE}" ]]; then
    NUXT_SESSION_PASSWORD="$(tr -d '\r\n' < "${SESSION_PASSWORD_FILE}" || true)"
    export NUXT_SESSION_PASSWORD
  fi

  if [[ -z "${NUXT_SESSION_PASSWORD:-}" ]]; then
    local generated
    if command -v openssl >/dev/null 2>&1; then
      generated="$(openssl rand -hex 32)"
    else
      generated="$(node -e "const crypto=require('crypto');console.log(crypto.randomBytes(32).toString('hex'))")"
    fi
    NUXT_SESSION_PASSWORD="${generated}"
    export NUXT_SESSION_PASSWORD

    mkdir -p "$(dirname "${SESSION_PASSWORD_FILE}")"
    umask 077
    printf '%s\n' "${NUXT_SESSION_PASSWORD}" > "${SESSION_PASSWORD_FILE}"
    chmod 600 "${SESSION_PASSWORD_FILE}" || true
    log "NUXT_SESSION_PASSWORD not found. Generated and saved to ${SESSION_PASSWORD_FILE}"
  fi

  if (( ${#NUXT_SESSION_PASSWORD} < SESSION_PASSWORD_MIN_LEN )); then
    die "NUXT_SESSION_PASSWORD is too short (${#NUXT_SESSION_PASSWORD}). Require at least ${SESSION_PASSWORD_MIN_LEN} characters."
  fi
}

resolve_node_options() {
  if [[ -n "${NODE_OPTIONS_VALUE}" ]]; then
    log "Using NODE_OPTIONS: ${NODE_OPTIONS_VALUE}"
    return 0
  fi

  local mem_total_mb=4096
  if [[ -r /proc/meminfo ]]; then
    mem_total_mb="$(( $(awk '/^MemTotal:/{print $2}' /proc/meminfo) / 1024 ))"
  fi

  local heap_mb
  heap_mb="$(( mem_total_mb * 70 / 100 ))"
  if (( heap_mb < 1024 )); then
    heap_mb=1024
  fi
  if (( heap_mb > 8192 )); then
    heap_mb=8192
  fi
  NODE_OPTIONS_VALUE="--max-old-space-size=${heap_mb}"
  log "Auto NODE_OPTIONS: ${NODE_OPTIONS_VALUE} (MemTotal=${mem_total_mb}MB)"
}

setup_noninteractive_env() {
  export CI="${CI_MODE}"
  export NUXT_TELEMETRY_DISABLED="${NUXT_TELEMETRY_DISABLED_VALUE}"
}

ensure_build_swap() {
  [[ "${AUTO_SWAP_FOR_BUILD}" == "1" ]] || return 0
  command -v swapon >/dev/null 2>&1 || return 0
  command -v mkswap >/dev/null 2>&1 || return 0
  [[ -r /proc/meminfo ]] || return 0

  local mem_mb swap_mb total_mb
  mem_mb="$(( $(awk '/^MemTotal:/{print $2}' /proc/meminfo) / 1024 ))"
  swap_mb="$(( $(awk '/^SwapTotal:/{print $2}' /proc/meminfo) / 1024 ))"
  total_mb="$(( mem_mb + swap_mb ))"

  if (( total_mb >= BUILD_MIN_MEMORY_MB )); then
    log "Build memory check OK: RAM ${mem_mb}MB + SWAP ${swap_mb}MB"
    return 0
  fi

  if swapon --show=NAME --noheadings 2>/dev/null | tr -d ' ' | grep -qx "${BUILD_SWAP_FILE}"; then
    log "Build swap already enabled: ${BUILD_SWAP_FILE}"
    return 0
  fi

  local need_mb target_swap_mb avail_mb
  need_mb="$(( BUILD_MIN_MEMORY_MB - total_mb ))"
  target_swap_mb="${BUILD_SWAP_MB}"
  if (( target_swap_mb < need_mb )); then
    target_swap_mb="${need_mb}"
  fi

  avail_mb="$(df -Pm "$(dirname "${BUILD_SWAP_FILE}")" | awk 'NR==2{print $4}')"
  if [[ -z "${avail_mb}" || "${avail_mb}" -le $(( target_swap_mb + 256 )) ]]; then
    log "Skip auto swap: insufficient free disk for ${target_swap_mb}MB at $(dirname "${BUILD_SWAP_FILE}")"
    return 0
  fi

  log "Memory low for build (RAM ${mem_mb}MB + SWAP ${swap_mb}MB), creating swap ${target_swap_mb}MB at ${BUILD_SWAP_FILE}"
  run_root swapoff "${BUILD_SWAP_FILE}" >/dev/null 2>&1 || true
  run_root rm -f "${BUILD_SWAP_FILE}"
  if command -v fallocate >/dev/null 2>&1; then
    run_root fallocate -l "${target_swap_mb}M" "${BUILD_SWAP_FILE}"
  else
    run_root dd if=/dev/zero of="${BUILD_SWAP_FILE}" bs=1M count="${target_swap_mb}" status=none
  fi
  run_root chmod 600 "${BUILD_SWAP_FILE}"
  run_root mkswap "${BUILD_SWAP_FILE}" >/dev/null
  run_root swapon "${BUILD_SWAP_FILE}"
  log "Auto swap enabled."
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
  NUXT_SESSION_PASSWORD=<at least 32 chars>
  SESSION_PASSWORD_FILE=./data/session-password
  NPM_REGISTRY=https://registry.npmmirror.com
  PNPM_REGISTRY=https://registry.npmmirror.com
  NODE_INSTALL_VERSION=22.12.0
  NODE_MIRROR=https://npmmirror.com/mirrors/node
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
      run_root apt-get install -y ca-certificates curl git python3 make g++ perl jq xz-utils
      if ! command -v exiftool >/dev/null 2>&1; then
        run_root apt-get install -y exiftool || run_root apt-get install -y libimage-exiftool-perl
      fi
      if ! command -v node >/dev/null 2>&1; then
        run_root apt-get install -y nodejs npm
      fi
      ;;
    dnf)
      run_root dnf install -y ca-certificates curl git python3 make gcc-c++ perl jq xz
      if ! command -v exiftool >/dev/null 2>&1; then
        run_root dnf install -y perl-Image-ExifTool || true
      fi
      if ! command -v node >/dev/null 2>&1; then
        run_root dnf install -y nodejs npm
      fi
      ;;
    yum)
      run_root yum install -y ca-certificates curl git python3 make gcc-c++ perl jq xz
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
  local version
  version="$(node -p 'process.versions.node' 2>/dev/null || echo 0.0.0)"
  if ! node_version_supported "${version}"; then
    die "Unsupported Node.js ${version}. Vite requires 20.19+ or 22.12+. Run: bash scripts/start-source.sh install"
  fi
  log "Node.js version: v${version}"
}

version_ge() {
  local v1="$1"
  local v2="$2"
  [[ "$(printf '%s\n%s\n' "${v1}" "${v2}" | sort -V | head -n1)" == "${v2}" ]]
}

node_version_supported() {
  local version="$1"
  if version_ge "${version}" "22.12.0"; then
    return 0
  fi
  if version_ge "${version}" "20.19.0" && ! version_ge "${version}" "21.0.0"; then
    return 0
  fi
  return 1
}

ensure_supported_node_runtime() {
  if command -v node >/dev/null 2>&1; then
    local cur
    cur="$(node -p 'process.versions.node' 2>/dev/null || echo 0.0.0)"
    if node_version_supported "${cur}"; then
      log "Node.js already supported: v${cur}"
      return 0
    fi
    log "Node.js v${cur} is not supported by Vite, upgrading..."
  else
    log "Node.js not found, installing..."
  fi

  command -v npm >/dev/null 2>&1 || die "npm not found. Install system deps first."
  run_root npm install -g n --registry "${NPM_REGISTRY}" >/dev/null
  run_root env N_NODE_MIRROR="${NODE_MIRROR}" n "${NODE_INSTALL_VERSION}" >/dev/null

  export PATH="/usr/local/bin:/usr/local/sbin:${PATH}"
  hash -r
  validate_node
}

setup_registry_mirror() {
  log "Configuring npm/pnpm registry mirrors..."
  setup_noninteractive_env
  npm config set registry "${NPM_REGISTRY}" >/dev/null
  npm config delete optional >/dev/null 2>&1 || true
  npm config delete omit >/dev/null 2>&1 || true
  export NPM_CONFIG_REGISTRY="${NPM_REGISTRY}"
  unset NPM_CONFIG_OMIT npm_config_omit || true
}

ensure_pnpm() {
  local want_version="${PNPM_PREPARE_VERSION#pnpm@}"
  log "Installing/refreshing pnpm ${want_version} via npm registry mirror..."
  run_root npm install -g "${PNPM_PREPARE_VERSION}" --registry "${NPM_REGISTRY}" >/dev/null
  export PATH="/usr/local/bin:/usr/local/sbin:${PATH}"
  hash -r
  command -v pnpm >/dev/null 2>&1 || die "pnpm installation failed."
  pnpm config set registry "${PNPM_REGISTRY}" >/dev/null
  pnpm config delete optional >/dev/null 2>&1 || true
  log "pnpm path: $(command -v pnpm)"
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
  resolve_node_options
  setup_noninteractive_env
  local install_log
  install_log="$(mktemp "${TMPDIR:-/tmp}/chronoframe-pnpm-install.XXXXXX.log")"

  if NODE_OPTIONS="${NODE_OPTIONS_VALUE}" pnpm install --frozen-lockfile 2>&1 | tee "${install_log}"; then
    rm -f "${install_log}"
    return 0
  fi

  if grep -qiE 'Cannot find native binding|@oxc-(parser|minify|transform)/binding-linux|\.linux-.*\.node' "${install_log}"; then
    log "Detected oxc native binding issue, running recovery install..."
    rm -rf node_modules
    if ! NODE_OPTIONS="${NODE_OPTIONS_VALUE}" pnpm install --frozen-lockfile --ignore-scripts; then
      NODE_OPTIONS="${NODE_OPTIONS_VALUE}" pnpm install --ignore-scripts
    fi
    ensure_oxc_native_bindings "${install_log}"

    local prepare_log prepared_ok=0 attempt
    prepare_log="$(mktemp "${TMPDIR:-/tmp}/chronoframe-nuxt-prepare.XXXXXX.log")"
    for attempt in 1 2 3; do
      if NODE_OPTIONS="${NODE_OPTIONS_VALUE}" pnpm exec nuxt prepare 2>&1 | tee "${prepare_log}"; then
        prepared_ok=1
        break
      fi
      if grep -qiE 'Cannot find native binding|@oxc-(parser|minify|transform)/binding-linux|\.linux-.*\.node' "${prepare_log}"; then
        log "nuxt prepare failed on attempt ${attempt}, patching missing oxc bindings..."
        ensure_oxc_native_bindings "${prepare_log}"
      else
        break
      fi
    done
    rm -f "${prepare_log}"
    [[ "${prepared_ok}" -eq 1 ]] || die "nuxt prepare failed after oxc binding recovery."
  else
    log "Frozen lockfile install failed, retrying with normal install..."
    NODE_OPTIONS="${NODE_OPTIONS_VALUE}" pnpm install
  fi

  rm -f "${install_log}"
}

get_oxc_core_versions() {
  local core="$1"
  local log_file="${2:-}"
  {
    if [[ -n "${log_file}" && -f "${log_file}" ]]; then
      grep -Eo "node_modules/.pnpm/${core}@[0-9]+\.[0-9]+\.[0-9]+" "${log_file}" | sed -E "s#.*${core}@##" || true
    fi

    if [[ -d node_modules/.pnpm ]]; then
      find node_modules/.pnpm -maxdepth 1 -type d -name "${core}@*" 2>/dev/null \
        | sed -E "s#^.*/${core}@([0-9]+\.[0-9]+\.[0-9]+).*$#\1#" || true
    fi

    if [[ -f pnpm-lock.yaml ]]; then
      grep -Eo "${core}@[0-9]+\.[0-9]+\.[0-9]+" pnpm-lock.yaml | sed -E "s#${core}@##" || true
    fi
  } | awk 'NF' | sort -Vu
}

get_binding_payload_dir() {
  local binding_pkg="$1"
  local version="$2"
  local cache_root cache_key payload_dir tmp_dir tarball

  cache_root="${TMPDIR:-/tmp}/chronoframe-oxc-bindings-cache"
  cache_key="$(echo "${binding_pkg}-${version}" | tr '/:@' '___')"
  payload_dir="${cache_root}/${cache_key}"

  if [[ -d "${payload_dir}" && -f "${payload_dir}/package.json" ]]; then
    echo "${payload_dir}"
    return 0
  fi

  mkdir -p "${cache_root}"
  tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/oxc-binding.XXXXXX")"
  tarball="$(cd "${tmp_dir}" && npm pack --silent --registry "${NPM_REGISTRY}" "${binding_pkg}@${version}" | tail -n1)"
  [[ -n "${tarball}" && -f "${tmp_dir}/${tarball}" ]] || die "Failed to download ${binding_pkg}@${version}"

  mkdir -p "${tmp_dir}/extract"
  tar -xzf "${tmp_dir}/${tarball}" -C "${tmp_dir}/extract"
  [[ -d "${tmp_dir}/extract/package" ]] || die "Invalid package archive for ${binding_pkg}"

  rm -rf "${payload_dir}"
  mkdir -p "${payload_dir}"
  cp -a "${tmp_dir}/extract/package/." "${payload_dir}/"
  rm -rf "${tmp_dir}"
  echo "${payload_dir}"
}

inject_oxc_binding_to_target() {
  local binding_pkg="$1"
  local version="$2"
  local target_dir="$3"
  local current_version=""

  if [[ -f "${target_dir}/package.json" ]]; then
    current_version="$(node -e "const fs=require('fs');const p='${target_dir}/package.json';try{const j=JSON.parse(fs.readFileSync(p,'utf8'));process.stdout.write(String(j.version||''))}catch{}" 2>/dev/null || true)"
  fi
  if [[ "${current_version}" == "${version}" ]]; then
    return 0
  fi

  local payload_dir
  payload_dir="$(get_binding_payload_dir "${binding_pkg}" "${version}")"
  log "Injecting missing oxc binding: ${binding_pkg}@${version} -> ${target_dir}"
  rm -rf "${target_dir}"
  mkdir -p "${target_dir}"
  cp -a "${payload_dir}/." "${target_dir}/"
}

inject_oxc_binding_for_core_version() {
  local core_pkg="$1"
  local version="$2"
  local binding_pkg="$3"
  local injected=0
  local base target_dir

  while IFS= read -r base; do
    [[ -n "${base}" ]] || continue
    target_dir="${base}/node_modules/${binding_pkg}"
    inject_oxc_binding_to_target "${binding_pkg}" "${version}" "${target_dir}"
    injected=1
  done < <(find node_modules/.pnpm -maxdepth 1 -type d -name "${core_pkg}@${version}*" 2>/dev/null || true)

  if [[ "${injected}" -eq 0 ]]; then
    target_dir="node_modules/${binding_pkg}"
    inject_oxc_binding_to_target "${binding_pkg}" "${version}" "${target_dir}"
  fi
}

ensure_oxc_native_bindings() {
  local log_file="${1:-}"
  [[ -f pnpm-lock.yaml ]] || return 0

  local arch libc
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

  local cores=("parser" "minify" "transform")
  local core core_pkg binding_pkg version
  for core in "${cores[@]}"; do
    core_pkg="oxc-${core}"
    binding_pkg="@oxc-${core}/binding-linux-${arch}-${libc}"
    while IFS= read -r version; do
      [[ -n "${version}" ]] || continue
      inject_oxc_binding_for_core_version "${core_pkg}" "${version}" "${binding_pkg}"
    done < <(get_oxc_core_versions "${core_pkg}" "${log_file}")
  done
}

verify_oxc_bindings() {
  local arch libc
  arch="$(node -p 'process.arch' 2>/dev/null || echo '')"
  case "${arch}" in
    x64|arm64) ;;
    *) return 0 ;;
  esac
  libc="gnu"
  [[ -f /etc/alpine-release ]] && libc="musl"

  local cores=("parser" "minify" "transform")
  local core core_pkg binding_pkg version base target_dir
  for core in "${cores[@]}"; do
    core_pkg="oxc-${core}"
    binding_pkg="@oxc-${core}/binding-linux-${arch}-${libc}"
    while IFS= read -r version; do
      [[ -n "${version}" ]] || continue
      while IFS= read -r base; do
        [[ -n "${base}" ]] || continue
        target_dir="${base}/node_modules/${binding_pkg}"
        [[ -f "${target_dir}/package.json" ]] || return 1
      done < <(find node_modules/.pnpm -maxdepth 1 -type d -name "${core_pkg}@${version}*" 2>/dev/null || true)
    done < <(get_oxc_core_versions "${core_pkg}")
  done
  return 0
}

ensure_oxc_bindings_before_build() {
  if verify_oxc_bindings; then
    return 0
  fi

  log "Some oxc bindings are missing, attempting auto recovery..."
  ensure_oxc_native_bindings
  verify_oxc_bindings || die "oxc native bindings are still missing after recovery."
}

build_project() {
  resolve_node_options
  setup_noninteractive_env
  ensure_build_swap
  ensure_oxc_bindings_before_build
  log "Cleaning previous build artifacts..."
  rm -rf .nuxt .output
  log "Building project with NODE_OPTIONS=${NODE_OPTIONS_VALUE}..."
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
    NUXT_SESSION_PASSWORD="${NUXT_SESSION_PASSWORD}" \
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
  setup_noninteractive_env
  validate_node
  ensure_session_password
  ensure_runtime_artifacts
  start_app
}

install_flow() {
  setup_noninteractive_env
  install_system_deps
  ensure_supported_node_runtime
  resolve_node_options
  setup_registry_mirror
  ensure_pnpm
  ensure_build_swap
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
