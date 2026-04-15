#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OPENCOMPASS_PID="${1:-}"
LOG_PATH="${WATCHER_LOG_PATH:-${ROOT_DIR}/outputs/standard-eval/fullrun/logs/lighteval-tier2-autostart.log}"
LIGHTEVAL_TASKS="${LIGHTEVAL_TASKS:-ifeval,mmlu_pro}"
LIGHTEVAL_CONCURRENT_REQUESTS="${LIGHTEVAL_CONCURRENT_REQUESTS:-1}"
LIGHTEVAL_EVAL_OUT="${LIGHTEVAL_EVAL_OUT:-${ROOT_DIR}/outputs/standard-eval/fullrun/lighteval-tier2}"

if [[ -z "${OPENCOMPASS_PID}" ]]; then
    echo "usage: $0 <opencompass-pid>" >&2
    exit 1
fi

mkdir -p "$(dirname "${LOG_PATH}")"

log() {
    printf '[%(%F %T)T] %s\n' -1 "$*" >> "${LOG_PATH}"
}

log "watcher started for OpenCompass PID ${OPENCOMPASS_PID}"

while kill -0 "${OPENCOMPASS_PID}" 2>/dev/null; do
    sleep 60
done

log "OpenCompass PID ${OPENCOMPASS_PID} finished, starting LightEval"

cd "${ROOT_DIR}"
LIGHTEVAL_TASKS="${LIGHTEVAL_TASKS}" \
LIGHTEVAL_CONCURRENT_REQUESTS="${LIGHTEVAL_CONCURRENT_REQUESTS}" \
LIGHTEVAL_EVAL_OUT="${LIGHTEVAL_EVAL_OUT}" \
    bash scripts/run_lighteval_local_api_eval.sh >> "${LOG_PATH}" 2>&1

status=$?
log "LightEval exited with status ${status}"
exit "${status}"
