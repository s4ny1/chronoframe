#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${PROJECT_ROOT}"

APP_PORT="${APP_PORT:-58081}"
SERVICE_NAME="${SERVICE_NAME:-chronoframe}"
COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.yml}"
PORT_OVERRIDE_FILE="${PORT_OVERRIDE_FILE:-docker-compose.port-override.yml}"
ALIYUN_DOCKER_MIRROR="${ALIYUN_DOCKER_MIRROR:-}"

log() {
  echo "[start-linux] $*"
}

die() {
  echo "[start-linux] ERROR: $*" >&2
  exit 1
}

SUDO=""
if [[ "${EUID}" -ne 0 ]]; then
  command -v sudo >/dev/null 2>&1 || die "sudo not found, please run as root."
  SUDO="sudo"
fi

run_root() {
  if [[ -n "${SUDO}" ]]; then
    "${SUDO}" "$@"
  else
    "$@"
  fi
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
  die "Unsupported Linux distro: apt/yum/dnf not found."
}

install_docker_apt() {
  log "Installing Docker (APT, Aliyun mirror)..."
  run_root apt-get update -y
  run_root apt-get install -y ca-certificates curl gnupg lsb-release jq

  run_root install -m 0755 -d /etc/apt/keyrings
  if [[ ! -f /etc/apt/keyrings/docker.gpg ]]; then
    run_root bash -c "curl -fsSL https://mirrors.aliyun.com/docker-ce/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg"
    run_root chmod a+r /etc/apt/keyrings/docker.gpg
  fi

  local codename arch
  codename="$(. /etc/os-release && echo "${VERSION_CODENAME:-}")"
  arch="$(dpkg --print-architecture)"
  [[ -n "${codename}" ]] || codename="jammy"

  run_root bash -c "cat > /etc/apt/sources.list.d/docker.list <<EOF
deb [arch=${arch} signed-by=/etc/apt/keyrings/docker.gpg] https://mirrors.aliyun.com/docker-ce/linux/ubuntu ${codename} stable
EOF"

  run_root apt-get update -y
  run_root apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
}

install_docker_yum_like() {
  local pm="$1"
  log "Installing Docker (${pm}, Aliyun mirror)..."
  if [[ "${pm}" == "dnf" ]]; then
    run_root dnf install -y dnf-plugins-core curl jq ca-certificates
    run_root dnf config-manager --add-repo https://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo || true
    run_root dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  else
    run_root yum install -y yum-utils curl jq ca-certificates
    run_root yum-config-manager --add-repo https://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo || true
    run_root yum install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  fi
}

install_docker_if_needed() {
  local pm
  pm="$(detect_pkg_manager)"
  if command -v docker >/dev/null 2>&1; then
    log "Docker already installed, skipping install."
  else
    case "${pm}" in
      apt) install_docker_apt ;;
      dnf|yum) install_docker_yum_like "${pm}" ;;
      *) die "Unsupported package manager: ${pm}" ;;
    esac
  fi

  log "Enabling and starting docker service..."
  run_root systemctl enable docker >/dev/null
  run_root systemctl restart docker >/dev/null
}

configure_docker_mirrors() {
  local mirror_json
  if [[ -n "${ALIYUN_DOCKER_MIRROR}" ]]; then
    mirror_json="\"${ALIYUN_DOCKER_MIRROR}\",\"https://docker.m.daocloud.io\",\"https://dockerproxy.cn\""
  else
    mirror_json="\"https://docker.m.daocloud.io\",\"https://dockerproxy.cn\",\"https://mirror.ccs.tencentyun.com\""
  fi

  run_root mkdir -p /etc/docker
  if [[ -f /etc/docker/daemon.json ]]; then
    run_root cp /etc/docker/daemon.json "/etc/docker/daemon.json.bak.$(date +%Y%m%d-%H%M%S)"
  fi

  run_root bash -c "cat > /etc/docker/daemon.json <<EOF
{
  \"registry-mirrors\": [${mirror_json}],
  \"log-driver\": \"json-file\",
  \"log-opts\": {
    \"max-size\": \"100m\",
    \"max-file\": \"3\"
  }
}
EOF"

  log "Restarting docker to apply mirror config..."
  run_root systemctl restart docker >/dev/null
}

compose_cmd() {
  if docker compose version >/dev/null 2>&1; then
    run_root docker compose "$@"
    return
  fi
  if command -v docker-compose >/dev/null 2>&1; then
    run_root docker-compose "$@"
    return
  fi
  die "docker compose/docker-compose not available."
}

prepare_project_files() {
  [[ -f "${COMPOSE_FILE}" ]] || die "${COMPOSE_FILE} not found."

  mkdir -p data

  if [[ ! -f .env && -f .env.example ]]; then
    log ".env not found, creating from .env.example"
    cp .env.example .env
  fi

  cat > "${PORT_OVERRIDE_FILE}" <<EOF
services:
  ${SERVICE_NAME}:
    ports:
      - "${APP_PORT}:3000"
EOF
}

start_service() {
  log "Building and starting service in background..."
  DOCKER_BUILDKIT=1 compose_cmd -f "${COMPOSE_FILE}" -f "${PORT_OVERRIDE_FILE}" up -d --build
}

print_summary() {
  local host_ip
  host_ip="$(hostname -I 2>/dev/null | awk '{print $1}' || true)"
  log "Service started."
  log "Local URL: http://127.0.0.1:${APP_PORT}"
  if [[ -n "${host_ip}" ]]; then
    log "LAN URL:   http://${host_ip}:${APP_PORT}"
  fi
  log "View logs:  docker compose -f ${COMPOSE_FILE} -f ${PORT_OVERRIDE_FILE} logs -f ${SERVICE_NAME}"
  log "Stop app:   docker compose -f ${COMPOSE_FILE} -f ${PORT_OVERRIDE_FILE} down"
}

main() {
  install_docker_if_needed
  configure_docker_mirrors
  prepare_project_files
  start_service
  print_summary
}

main "$@"
