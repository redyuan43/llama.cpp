#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEFAULT_ENV_FILE="${HOME}/.config/llama.cpp/brave-mcp.env"
LEGACY_ENV_FILE="${HOME}/.config/gemma4/brave-mcp.env"
ENV_FILE="${BRAVE_MCP_ENV_FILE:-${DEFAULT_ENV_FILE}}"
PID_FILE="${BRAVE_MCP_PID_FILE:-${ROOT_DIR}/runtime/brave-mcp.pid}"
LOG_FILE="${BRAVE_MCP_LOG_FILE:-${ROOT_DIR}/logs/brave-mcp.log}"
HOST="${BRAVE_MCP_HOST:-127.0.0.1}"
PORT="${BRAVE_MCP_PORT:-8765}"
HEALTH_URL="${BRAVE_MCP_HEALTH_URL:-http://${HOST}:${PORT}/healthz}"

mkdir -p "$(dirname "${PID_FILE}")" "$(dirname "${LOG_FILE}")"

health_check() {
  local body
  body="$(curl -fsS "${HEALTH_URL}" 2>/dev/null || true)"
  if [[ "${body}" == *'"service":"brave-mcp-http-server"'* ]]; then
    printf '%s\n' "${body}"
    return 0
  fi
  return 1
}

if [[ ! -f "${ENV_FILE}" && -f "${LEGACY_ENV_FILE}" ]]; then
  ENV_FILE="${LEGACY_ENV_FILE}"
fi

if [[ -f "${ENV_FILE}" ]]; then
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
fi

if [[ -z "${BRAVE_API_KEY:-}" || "${BRAVE_API_KEY}" == "YOUR_BRAVE_API_KEY" ]]; then
  echo "ERROR: BRAVE_API_KEY is missing. Fill ${ENV_FILE} first." >&2
  exit 1
fi

if [[ -f "${PID_FILE}" ]]; then
  existing_pid="$(cat "${PID_FILE}")"
  if kill -0 "${existing_pid}" >/dev/null 2>&1; then
    if health_check >/dev/null; then
      echo "brave-mcp bridge already running: pid=${existing_pid}"
      exit 0
    fi
  fi
  rm -f "${PID_FILE}"
fi

setsid env \
  BRAVE_MCP_HOST="${HOST}" \
  BRAVE_MCP_PORT="${PORT}" \
  BRAVE_API_KEY="${BRAVE_API_KEY}" \
  HTTPS_PROXY="${HTTPS_PROXY:-}" \
  HTTP_PROXY="${HTTP_PROXY:-}" \
  ALL_PROXY="${ALL_PROXY:-}" \
  node "${ROOT_DIR}/scripts/brave_mcp_http_server.mjs" >"${LOG_FILE}" 2>&1 < /dev/null &

bridge_pid=$!
echo "${bridge_pid}" > "${PID_FILE}"

for _ in $(seq 1 20); do
  if health_check >/dev/null; then
    echo "brave-mcp bridge ready: ${HEALTH_URL}"
    exit 0
  fi
  if ! kill -0 "${bridge_pid}" >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

current_health="$(curl -fsS "${HEALTH_URL}" 2>/dev/null || true)"
if [[ -n "${current_health}" ]]; then
  echo "ERROR: ${HEALTH_URL} responded, but it is not brave-mcp: ${current_health}" >&2
else
  echo "ERROR: brave-mcp bridge did not become ready. See ${LOG_FILE}" >&2
fi
exit 1
