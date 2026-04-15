#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENV_DIR="${LIGHTEVAL_EVAL_VENV:-${ROOT_DIR}/.venv-lighteval-eval}"
LIGHTEVAL_BIN="${LIGHTEVAL_BIN:-${VENV_DIR}/bin/lighteval}"

SERVER_URL="${LIGHTEVAL_SERVER_URL:-http://127.0.0.1:8095/v1}"
HEALTH_URL="${LIGHTEVAL_HEALTH_URL:-${SERVER_URL%/v1}/health}"
API_KEY="${LIGHTEVAL_API_KEY:-EMPTY}"
MODEL_NAME="${LIGHTEVAL_MODEL_NAME:-gpt-oss-120b}"
TASKS="${LIGHTEVAL_TASKS:-ifeval,mmlu_pro}"
OUT_ROOT="${LIGHTEVAL_EVAL_OUT:-${ROOT_DIR}/outputs/standard-eval/lighteval/$(date +%Y%m%d-%H%M%S)}"

CONCURRENT_REQUESTS="${LIGHTEVAL_CONCURRENT_REQUESTS:-8}"
MAX_MODEL_LENGTH="${LIGHTEVAL_MAX_MODEL_LENGTH:-131072}"
MAX_NEW_TOKENS="${LIGHTEVAL_MAX_NEW_TOKENS:-1024}"
TEMPERATURE="${LIGHTEVAL_TEMPERATURE:-0.0}"
TIMEOUT="${LIGHTEVAL_TIMEOUT:-1800}"
MAX_SAMPLES="${LIGHTEVAL_MAX_SAMPLES:-}"
PLAN_ONLY="${LIGHTEVAL_PLAN_ONLY:-0}"
CHAT_TEMPLATE_KWARGS_JSON="${LIGHTEVAL_CHAT_TEMPLATE_KWARGS_JSON:-}"

normalize_proxy() {
  local raw="${1:-}"
  raw="${raw%/}"
  if [[ -z "${raw}" ]]; then
    printf '%s' ""
    return 0
  fi
  if [[ "${raw}" == socks://* ]]; then
    printf 'socks5://%s' "${raw#socks://}"
    return 0
  fi
  printf '%s' "${raw}"
}

cd "${ROOT_DIR}"
mkdir -p "${OUT_ROOT}"

cat > "${OUT_ROOT}/plan.md" <<PLAN
# LightEval Local API Eval Plan

- server_url: ${SERVER_URL}
- model_name: ${MODEL_NAME}
- tasks: ${TASKS}
- output: ${OUT_ROOT}

Notes:
- LightEval + LiteLLM is the lightweight standard path for generative endpoint tasks.
- It does not implement loglikelihood for LiteLLM endpoints, so use OpenCompass for HellaSwag or WinoGrande.
PLAN

if [[ "${PLAN_ONLY}" == "1" ]]; then
  echo "PLAN_ONLY ${OUT_ROOT}"
  exit 0
fi

[[ -d "${VENV_DIR}" ]] || { echo "ERROR: venv not found: ${VENV_DIR}" >&2; exit 1; }
[[ -x "${LIGHTEVAL_BIN}" ]] || { echo "ERROR: lighteval executable not found: ${LIGHTEVAL_BIN}" >&2; exit 1; }

curl -fsS "${HEALTH_URL}" >/dev/null

CONFIG_PATH="${OUT_ROOT}/lighteval_litellm.yaml"
cat > "${CONFIG_PATH}" <<YAML
model_parameters:
  provider: "openai"
  model_name: "openai/${MODEL_NAME}"
  base_url: "${SERVER_URL}"
  api_key: "${API_KEY}"
  concurrent_requests: ${CONCURRENT_REQUESTS}
  max_model_length: ${MAX_MODEL_LENGTH}
  timeout: ${TIMEOUT}
  generation_parameters:
    temperature: ${TEMPERATURE}
    max_new_tokens: ${MAX_NEW_TOKENS}
YAML

if [[ -n "${CHAT_TEMPLATE_KWARGS_JSON}" ]]; then
  cat >> "${CONFIG_PATH}" <<YAML
    extra_body:
      chat_template_kwargs: ${CHAT_TEMPLATE_KWARGS_JSON}
YAML
fi

# shellcheck disable=SC1091
source "${VENV_DIR}/bin/activate"

ALL_PROXY_NORM="$(normalize_proxy "${ALL_PROXY:-${all_proxy:-}}")"
HTTPS_PROXY_NORM="$(normalize_proxy "${HTTPS_PROXY:-${https_proxy:-${ALL_PROXY_NORM}}}")"
HTTP_PROXY_NORM="$(normalize_proxy "${HTTP_PROXY:-${http_proxy:-${ALL_PROXY_NORM}}}")"

cmd=(
  "${LIGHTEVAL_BIN}"
  endpoint litellm
  "${CONFIG_PATH}"
  "${TASKS}"
  --output-dir "${OUT_ROOT}"
  --save-details
  --no-public-run
)

if [[ -n "${MAX_SAMPLES}" ]]; then
  cmd+=(--max-samples "${MAX_SAMPLES}")
fi

ALL_PROXY="${ALL_PROXY_NORM}" \
all_proxy="${ALL_PROXY_NORM}" \
HTTPS_PROXY="${HTTPS_PROXY_NORM}" \
https_proxy="${HTTPS_PROXY_NORM}" \
HTTP_PROXY="${HTTP_PROXY_NORM}" \
http_proxy="${HTTP_PROXY_NORM}" \
  "${cmd[@]}"

echo "DONE ${OUT_ROOT}"
