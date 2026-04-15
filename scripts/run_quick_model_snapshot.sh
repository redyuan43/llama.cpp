#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_ROOT="${QUICK_EVAL_OUT:-${ROOT_DIR}/outputs/standard-eval/snapshot/$(date +%Y%m%d-%H%M%S)}"
SERVER_URL="${QUICK_EVAL_SERVER_URL:-http://127.0.0.1:8095/v1}"
MODEL_NAME="${QUICK_EVAL_MODEL_NAME:-gpt-oss-120b}"
TOKENIZER_NAME="${QUICK_EVAL_TOKENIZER:-openai/gpt-oss-120b}"

GSM8K_SAMPLES="${QUICK_GSM8K_SAMPLES:-25}"
WINOGRANDE_SAMPLES="${QUICK_WINOGRANDE_SAMPLES:-25}"
HELLASWAG_SAMPLES="${QUICK_HELLASWAG_SAMPLES:-25}"
MMLU_SAMPLES_PER_SUBJECT="${QUICK_MMLU_SAMPLES_PER_SUBJECT:-2}"
LIGHTEVAL_SAMPLES="${QUICK_LIGHTEVAL_SAMPLES:-20}"
LIGHTEVAL_TASKS="${QUICK_LIGHTEVAL_TASKS:-ifeval,mmlu_pro}"
PLAN_ONLY="${QUICK_EVAL_PLAN_ONLY:-0}"

cd "${ROOT_DIR}"
mkdir -p "${OUT_ROOT}"

cat > "${OUT_ROOT}/plan.md" <<PLAN
# Quick Model Snapshot Plan

- server_url: ${SERVER_URL}
- model_name: ${MODEL_NAME}
- tokenizer: ${TOKENIZER_NAME}
- opencompass:
  - gsm8k samples: ${GSM8K_SAMPLES}
  - winogrande samples: ${WINOGRANDE_SAMPLES}
  - hellaswag samples: ${HELLASWAG_SAMPLES}
  - mmlu per-subject samples: ${MMLU_SAMPLES_PER_SUBJECT}
- lighteval:
  - tasks: ${LIGHTEVAL_TASKS}
  - max_samples: ${LIGHTEVAL_SAMPLES}

Notes:
- This is a speed-oriented snapshot, not an official full benchmark.
- MMLU uses low-depth, high-breadth sampling: every subject gets a very small test_range.
- Recommended for quick quality checks before committing to a full run.
PLAN

if [[ "${PLAN_ONLY}" == "1" ]]; then
  echo "PLAN_ONLY ${OUT_ROOT}"
  exit 0
fi

run_opencompass_slice() {
  local dataset="$1"
  local samples="$2"
  local out_dir="${OUT_ROOT}/opencompass/${dataset}"

  OPENCOMPASS_SERVER_URL="${SERVER_URL}" \
  OPENCOMPASS_MODEL_NAME="${MODEL_NAME}" \
  OPENCOMPASS_TOKENIZER="${TOKENIZER_NAME}" \
  OPENCOMPASS_DATASETS="${dataset}" \
  OPENCOMPASS_TEST_RANGE="[:${samples}]" \
  OPENCOMPASS_EVAL_OUT="${out_dir}" \
    bash scripts/run_opencompass_local_api_eval.sh
}

run_opencompass_slice "gsm8k" "${GSM8K_SAMPLES}"
run_opencompass_slice "winogrande" "${WINOGRANDE_SAMPLES}"
run_opencompass_slice "hellaswag" "${HELLASWAG_SAMPLES}"
run_opencompass_slice "mmlu" "${MMLU_SAMPLES_PER_SUBJECT}"

LIGHTEVAL_SERVER_URL="${SERVER_URL}" \
LIGHTEVAL_MODEL_NAME="${MODEL_NAME}" \
LIGHTEVAL_TASKS="${LIGHTEVAL_TASKS}" \
LIGHTEVAL_MAX_SAMPLES="${LIGHTEVAL_SAMPLES}" \
LIGHTEVAL_EVAL_OUT="${OUT_ROOT}/lighteval" \
  bash scripts/run_lighteval_local_api_eval.sh

mkdir -p "${OUT_ROOT}/opencompass/predictions"
find "${OUT_ROOT}/opencompass" -path '*/predictions/*/*.json' -type f -exec cp {} "${OUT_ROOT}/opencompass/predictions/" \;

python3 scripts/summarize_quick_model_snapshot.py "${OUT_ROOT}"

echo "DONE ${OUT_ROOT}"
