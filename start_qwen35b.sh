#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

MODEL_PATH="${QWEN35_35B_MODEL_PATH:-${HOME}/.lmstudio/models/lmstudio-community/Qwen3.5-35B-A3B-GGUF/Qwen3.5-35B-A3B-Q4_K_M.gguf}"
MMPROJ_PATH="${QWEN35_35B_MMPROJ_PATH:-${HOME}/.lmstudio/models/lmstudio-community/Qwen3.5-35B-A3B-GGUF/mmproj-Qwen3.5-35B-A3B-BF16.gguf}"
SERVER_BIN="${LLAMA_SERVER:-${ROOT_DIR}/build/bin/llama-server}"
HOST="${QWEN35_35B_HOST:-127.0.0.1}"
PORT="${QWEN35_35B_PORT:-8090}"
CTX_SIZE="${QWEN35_35B_CTX_SIZE:-131072}"
BATCH_SIZE="${QWEN35_35B_BATCH_SIZE:-1024}"
UBATCH_SIZE="${QWEN35_35B_UBATCH_SIZE:-1024}"
IMAGE_MIN_TOKENS="${QWEN35_35B_IMAGE_MIN_TOKENS:-560}"
IMAGE_MAX_TOKENS="${QWEN35_35B_IMAGE_MAX_TOKENS:-1120}"
PARALLEL="${QWEN35_35B_PARALLEL:-1}"
NGL="${QWEN35_35B_NGL:-99}"
FLASH_ATTN="${QWEN35_35B_FLASH_ATTN:-1}"
MEDIA_PATH="${QWEN35_35B_MEDIA_PATH:-${ROOT_DIR}}"
XDG_CACHE_DIR="${QWEN35_35B_XDG_CACHE_HOME:-/tmp/llama-cache-test}"
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

if [[ ! -f "${MMPROJ_PATH}" ]]; then
  echo "ERROR: mmproj file not found: ${MMPROJ_PATH}" >&2
  exit 1
fi

if [[ ! -d "${MEDIA_PATH}" ]]; then
  echo "ERROR: media path not found: ${MEDIA_PATH}" >&2
  exit 1
fi

if [[ "${IMAGE_MIN_TOKENS}" -lt 0 || "${IMAGE_MAX_TOKENS}" -lt 0 || "${IMAGE_MAX_TOKENS}" -lt "${IMAGE_MIN_TOKENS}" ]]; then
  echo "ERROR: invalid image token settings: min=${IMAGE_MIN_TOKENS}, max=${IMAGE_MAX_TOKENS}" >&2
  exit 1
fi

if [[ "${UBATCH_SIZE}" -lt "${IMAGE_MAX_TOKENS}" ]]; then
  echo "adjusting ubatch-size for vision: ${UBATCH_SIZE} -> ${IMAGE_MAX_TOKENS}"
  UBATCH_SIZE="${IMAGE_MAX_TOKENS}"
fi

if [[ "${BATCH_SIZE}" -lt "${UBATCH_SIZE}" ]]; then
  echo "adjusting batch-size for vision: ${BATCH_SIZE} -> ${UBATCH_SIZE}"
  BATCH_SIZE="${UBATCH_SIZE}"
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
  --mmproj "${MMPROJ_PATH}"
  --image-min-tokens "${IMAGE_MIN_TOKENS}"
  --image-max-tokens "${IMAGE_MAX_TOKENS}"
  --media-path "${MEDIA_PATH}"
  --host "${HOST}"
  --port "${PORT}"
  --jinja
  --ctx-size "${CTX_SIZE}"
  --batch-size "${BATCH_SIZE}"
  --ubatch-size "${UBATCH_SIZE}"
  --parallel "${PARALLEL}"
  --n-gpu-layers "${NGL}"
  -fa "${FLASH_ATTN}"
  --reasoning auto
  --reasoning-format none
  --temp 1.0
  --top-k 20
  --top-p 0.95
  --min-p 0.0
  --repeat-penalty 1.0
  --presence-penalty 1.5
  --webui-config-file "${WEBUI_CONFIG_FILE}"
  --no-warmup
)

if [[ "${WEBUI_MCP_PROXY}" == "1" ]]; then
  SERVER_ARGS+=(--webui-mcp-proxy)
fi

if [[ -n "${QWEN35_35B_EXTRA_ARGS:-}" ]]; then
  # shellcheck disable=SC2206
  EXTRA_ARGS=( ${QWEN35_35B_EXTRA_ARGS} )
  SERVER_ARGS+=("${EXTRA_ARGS[@]}")
fi

echo "info: starting Qwen3.5-35B WebUI at http://${HOST}:${PORT}"
exec env \
  XDG_CACHE_HOME="${XDG_CACHE_DIR}" \
  "${SERVER_BIN}" \
  "${SERVER_ARGS[@]}"
