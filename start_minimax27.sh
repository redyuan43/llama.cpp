#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

MODEL_PATH="${MINIMAX27_MODEL_PATH:-/home/dgx/.lmstudio/models/unsloth/MiniMax-M2.7-GGUF/MiniMax-M2.7-UD-Q3_K_S-00001-of-00003.gguf}"
SERVER_BIN="${LLAMA_SERVER:-${ROOT_DIR}/build/bin/llama-server}"
HOST="${MINIMAX27_HOST:-127.0.0.1}"
PORT="${MINIMAX27_PORT:-8093}"
CTX_SIZE="${MINIMAX27_CTX_SIZE:-65536}"
BATCH_SIZE="${MINIMAX27_BATCH_SIZE:-1024}"
UBATCH_SIZE="${MINIMAX27_UBATCH_SIZE:-1024}"
PARALLEL="${MINIMAX27_PARALLEL:-1}"
NGL="${MINIMAX27_NGL:-999}"
XDG_CACHE_DIR="${MINIMAX27_XDG_CACHE_HOME:-/tmp/llama-cache-test}"
DEFAULT_BRAVE_MCP_ENV_FILE="${HOME}/.config/llama.cpp/brave-mcp.env"
LEGACY_BRAVE_MCP_ENV_FILE="${HOME}/.config/gemma4/brave-mcp.env"
BRAVE_MCP_ENV_FILE="${BRAVE_MCP_ENV_FILE:-${DEFAULT_BRAVE_MCP_ENV_FILE}}"
WEBUI_CONFIG_FILE="${WEBUI_CONFIG_FILE:-${ROOT_DIR}/config/webui-brave-mcp.json}"
WEBUI_MCP_PROXY="${WEBUI_MCP_PROXY:-1}"

cd "${ROOT_DIR}"

if [[ ! -x "${SERVER_BIN}" ]]; then
  echo "ERROR: llama-server not found or not executable: ${SERVER_BIN}" >&2
  echo "hint: build it first with cmake --build \"${ROOT_DIR}/build\" --target llama-server" >&2
  exit 1
fi

if [[ ! -f "${MODEL_PATH}" ]]; then
  echo "ERROR: model file not found: ${MODEL_PATH}" >&2
  exit 1
fi

if [[ ! -f "${BRAVE_MCP_ENV_FILE}" && -f "${LEGACY_BRAVE_MCP_ENV_FILE}" ]]; then
  BRAVE_MCP_ENV_FILE="${LEGACY_BRAVE_MCP_ENV_FILE}"
fi

if [[ -f "${BRAVE_MCP_ENV_FILE}" ]]; then
  # shellcheck disable=SC1090
  source "${BRAVE_MCP_ENV_FILE}"
fi

if [[ -n "${BRAVE_API_KEY:-}" && "${BRAVE_API_KEY}" != "YOUR_BRAVE_API_KEY" ]]; then
  BRAVE_MCP_ENV_FILE="${BRAVE_MCP_ENV_FILE}" "${ROOT_DIR}/scripts/start_brave_mcp_bridge.sh"
else
  echo "info: BRAVE_API_KEY is not configured, WebUI will start without Brave MCP"
fi

SERVER_ARGS=(
  -m "${MODEL_PATH}"
  --host "${HOST}"
  --port "${PORT}"
  --jinja
  --ctx-size "${CTX_SIZE}"
  --batch-size "${BATCH_SIZE}"
  --ubatch-size "${UBATCH_SIZE}"
  --parallel "${PARALLEL}"
  --n-gpu-layers "${NGL}"
  --reasoning auto
  --reasoning-format none
  --temp 1.0
  --top-p 0.95
  --top-k 40
  --webui-config-file "${WEBUI_CONFIG_FILE}"
  --no-warmup
)

if [[ "${WEBUI_MCP_PROXY}" == "1" ]]; then
  SERVER_ARGS+=(--webui-mcp-proxy)
fi

if [[ -n "${MINIMAX27_EXTRA_ARGS:-}" ]]; then
  # shellcheck disable=SC2206
  EXTRA_ARGS=( ${MINIMAX27_EXTRA_ARGS} )
  SERVER_ARGS+=("${EXTRA_ARGS[@]}")
fi

echo "info: starting MiniMax-M2.7 WebUI at http://${HOST}:${PORT}"
exec env \
  XDG_CACHE_HOME="${XDG_CACHE_DIR}" \
  "${SERVER_BIN}" \
  "${SERVER_ARGS[@]}"
