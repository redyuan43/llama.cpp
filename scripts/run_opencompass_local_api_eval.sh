#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENV_DIR="${OPENCOMPASS_EVAL_VENV:-${ROOT_DIR}/.venv-opencompass-eval}"
OPENCOMPASS_DIR="${OPENCOMPASS_DIR:-${ROOT_DIR}/third_party/opencompass}"
OPENCOMPASS_BIN="${OPENCOMPASS_BIN:-${VENV_DIR}/bin/opencompass}"

SERVER_URL="${OPENCOMPASS_SERVER_URL:-http://127.0.0.1:8095/v1}"
HEALTH_URL="${OPENCOMPASS_HEALTH_URL:-${SERVER_URL%/v1}/health}"
API_KEY="${OPENCOMPASS_API_KEY:-EMPTY}"
MODEL_NAME="${OPENCOMPASS_MODEL_NAME:-gpt-oss-120b}"
TOKENIZER_NAME="${OPENCOMPASS_TOKENIZER:-openai/gpt-oss-120b}"

SUITE="${OPENCOMPASS_SUITE:-core}"
DATASETS="${OPENCOMPASS_DATASETS:-}"
OUT_ROOT="${OPENCOMPASS_EVAL_OUT:-${ROOT_DIR}/outputs/standard-eval/opencompass/$(date +%Y%m%d-%H%M%S)}"
MAX_SEQ_LEN="${OPENCOMPASS_MAX_SEQ_LEN:-131072}"
MAX_OUT_LEN="${OPENCOMPASS_MAX_OUT_LEN:-1024}"
QUERY_PER_SECOND="${OPENCOMPASS_QUERY_PER_SECOND:-1}"
MAX_WORKERS="${OPENCOMPASS_MAX_WORKERS:-64}"
TEMPERATURE="${OPENCOMPASS_TEMPERATURE:-0}"
RETRY="${OPENCOMPASS_RETRY:-3}"
RUN_MODE="${OPENCOMPASS_RUN_MODE:-all}"
RUNNER_MAX_WORKERS="${OPENCOMPASS_RUNNER_MAX_WORKERS:-1}"
PLAN_ONLY="${OPENCOMPASS_PLAN_ONLY:-0}"
DEBUG_MODE="${OPENCOMPASS_DEBUG:-0}"
TEST_RANGE="${OPENCOMPASS_TEST_RANGE:-}"
SYSTEM_ROLE_MODE="${OPENCOMPASS_SYSTEM_ROLE_MODE:-inline}"
DISABLE_THINKING="${OPENCOMPASS_DISABLE_THINKING:-0}"

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

resolve_suite() {
  case "${SUITE}" in
    core)
      printf '%s' "hellaswag,winogrande,mmlu,gsm8k"
      ;;
    full)
      printf '%s' "hellaswag,winogrande,mmlu,gsm8k,humaneval"
      ;;
    reasoning)
      printf '%s' "mmlu,gsm8k,ifeval,mmlu_pro"
      ;;
    *)
      echo "ERROR: unsupported OPENCOMPASS_SUITE=${SUITE}" >&2
      exit 1
      ;;
  esac
}

if [[ -z "${DATASETS}" ]]; then
  DATASETS="$(resolve_suite)"
fi

cd "${ROOT_DIR}"
mkdir -p "${OUT_ROOT}"

cat > "${OUT_ROOT}/plan.md" <<PLAN
# OpenCompass Local API Eval Plan

- server_url: ${SERVER_URL}
- model_name: ${MODEL_NAME}
- tokenizer: ${TOKENIZER_NAME}
- suite: ${SUITE}
- datasets: ${DATASETS}
- output: ${OUT_ROOT}

Notes:
- OpenCompass is the standard entry for multi-choice and mixed benchmark runs.
- Some datasets rely on OpenCompass dataset packs or ModelScope auto-download.
- If a dataset is missing locally, try:
  export DATASET_SOURCE=ModelScope
PLAN

if [[ "${PLAN_ONLY}" == "1" ]]; then
  echo "PLAN_ONLY ${OUT_ROOT}"
  exit 0
fi

[[ -d "${VENV_DIR}" ]] || { echo "ERROR: venv not found: ${VENV_DIR}" >&2; exit 1; }
[[ -d "${OPENCOMPASS_DIR}" ]] || { echo "ERROR: opencompass repo not found: ${OPENCOMPASS_DIR}" >&2; exit 1; }
[[ -x "${OPENCOMPASS_BIN}" ]] || { echo "ERROR: opencompass executable not found: ${OPENCOMPASS_BIN}" >&2; exit 1; }

curl -fsS "${HEALTH_URL}" >/dev/null

export OPENCOMPASS_DIR
export OUT_ROOT
export DATASETS
export SERVER_URL
export API_KEY
export MODEL_NAME
export TOKENIZER_NAME
export MAX_SEQ_LEN
export MAX_OUT_LEN
export QUERY_PER_SECOND
export MAX_WORKERS
export TEMPERATURE
export RETRY
export TEST_RANGE
export RUN_MODE
export RUNNER_MAX_WORKERS
export DEBUG_MODE
export SYSTEM_ROLE_MODE
export DISABLE_THINKING

# shellcheck disable=SC1091
source "${VENV_DIR}/bin/activate"

ALL_PROXY_NORM="$(normalize_proxy "${ALL_PROXY:-${all_proxy:-}}")"
HTTPS_PROXY_NORM="$(normalize_proxy "${HTTPS_PROXY:-${https_proxy:-${ALL_PROXY_NORM}}}")"
HTTP_PROXY_NORM="$(normalize_proxy "${HTTP_PROXY:-${http_proxy:-${ALL_PROXY_NORM}}}")"

ALL_PROXY="${ALL_PROXY_NORM}" \
all_proxy="${ALL_PROXY_NORM}" \
HTTPS_PROXY="${HTTPS_PROXY_NORM}" \
https_proxy="${HTTPS_PROXY_NORM}" \
HTTP_PROXY="${HTTP_PROXY_NORM}" \
http_proxy="${HTTP_PROXY_NORM}" \
python - <<'PY'
import os
import os.path as osp
from copy import deepcopy
from datetime import datetime
from types import SimpleNamespace

from mmengine.config import Config

from opencompass.cli.main import _run_eval_tasks
from opencompass.registry import PARTITIONERS, RUNNERS, build_from_cfg
from opencompass.summarizers import DefaultSummarizer
from opencompass.utils.run import fill_eval_cfg, fill_infer_cfg

root = os.environ["OPENCOMPASS_DIR"]
dataset_map = {
    "gsm8k": (
        osp.join(root, "opencompass/configs/datasets/gsm8k/gsm8k_gen.py"),
        "gsm8k_datasets",
    ),
    "gpqa": (
        osp.join(root, "opencompass/configs/datasets/gpqa/gpqa_gen.py"),
        "gpqa_datasets",
    ),
    "hellaswag": (
        osp.join(root, "opencompass/configs/datasets/hellaswag/hellaswag_gen.py"),
        "hellaswag_datasets",
    ),
    "humaneval": (
        osp.join(root, "opencompass/configs/datasets/humaneval/humaneval_gen.py"),
        "humaneval_datasets",
    ),
    "ifeval": (
        osp.join(root, "opencompass/configs/datasets/IFEval/IFEval_gen.py"),
        "ifeval_datasets",
    ),
    "mmlu": (
        osp.join(root, "opencompass/configs/datasets/mmlu/mmlu_gen.py"),
        "mmlu_datasets",
    ),
    "mmlu_pro": (
        osp.join(root, "opencompass/configs/datasets/mmlu_pro/mmlu_pro_gen.py"),
        "mmlu_pro_datasets",
    ),
    "winogrande": (
        osp.join(root, "opencompass/configs/datasets/winogrande/winogrande_gen.py"),
        "winogrande_datasets",
    ),
}

selected = [item.strip() for item in os.environ["DATASETS"].split(",") if item.strip()]
unknown = [item for item in selected if item not in dataset_map]
if unknown:
    raise SystemExit(f"Unsupported OpenCompass datasets: {', '.join(unknown)}")

datasets = []
test_range = os.environ.get("TEST_RANGE", "").strip()
for name in selected:
    cfg = Config.fromfile(dataset_map[name][0])
    dataset_cfgs = deepcopy(cfg[dataset_map[name][1]])
    if test_range:
        for dataset in dataset_cfgs:
            reader_cfg = dict(dataset.get("reader_cfg", {}))
            reader_cfg["test_range"] = test_range
            dataset["reader_cfg"] = reader_cfg
        if name == "winogrande":
            round_cfg = dataset["infer_cfg"]["prompt_template"]["template"]["round"][0]
            round_cfg["prompt"] = (
                round_cfg["prompt"]
                + "\nPlease explain briefly if needed, but the last line of your response must be exactly "
                  "'ANSWER: A' or 'ANSWER: B'."
            )
            dataset["eval_cfg"]["pred_postprocessor"] = dict(
                type="opencompass.utils.text_postprocessors.first_option_postprocess",
                options="AB",
                cushion=False,
            )
        elif name == "hellaswag":
            for key in ("ice_template", "prompt_template"):
                round_cfg = dataset["infer_cfg"][key]["template"]["round"]
                round_cfg[0]["prompt"] = (
                    round_cfg[0]["prompt"]
                    + "\nPlease explain briefly if needed, but the last line of your response must be exactly "
                      "'ANSWER: A', 'ANSWER: B', 'ANSWER: C', or 'ANSWER: D'."
                )
                round_cfg[1]["prompt"] = "ANSWER: {label}\n"
            dataset["eval_cfg"]["pred_postprocessor"] = dict(
                type="opencompass.utils.text_postprocessors.first_option_postprocess",
                options="ABCD",
                cushion=False,
            )
    datasets.extend(dataset_cfgs)

system_role_mode = os.environ.get("SYSTEM_ROLE_MODE", "inline").strip().lower()
if system_role_mode == "reserved":
    api_meta_template = dict(
        round=[
            dict(role="HUMAN", api_role="HUMAN"),
            dict(role="BOT", api_role="BOT", generate=True),
        ],
        reserved_roles=[dict(role="SYSTEM", api_role="SYSTEM")],
    )
else:
    api_meta_template = dict(
        round=[
            dict(role="SYSTEM", api_role="SYSTEM"),
            dict(role="HUMAN", api_role="HUMAN"),
            dict(role="BOT", api_role="BOT", generate=True),
        ],
    )

models = [
    dict(
        abbr=os.environ["MODEL_NAME"],
        type="opencompass.models.OpenAISDK",
        key=os.environ["API_KEY"],
        openai_api_base=os.environ["SERVER_URL"],
        path=os.environ["MODEL_NAME"],
        tokenizer_path=os.environ["TOKENIZER_NAME"],
        rpm_verbose=True,
        meta_template=api_meta_template,
        query_per_second=int(os.environ["QUERY_PER_SECOND"]),
        batch_size=1,
        max_out_len=int(os.environ["MAX_OUT_LEN"]),
        max_seq_len=int(os.environ["MAX_SEQ_LEN"]),
        temperature=float(os.environ["TEMPERATURE"]),
        max_workers=int(os.environ["MAX_WORKERS"]),
        retry=int(os.environ["RETRY"]),
        pred_postprocessor=dict(
            type="opencompass.utils.text_postprocessors.extract_non_reasoning_content"
        ),
    )
]

if os.environ.get("DISABLE_THINKING", "0") == "1":
    models[0]["extra_body"] = {
        "chat_template_kwargs": {
            "enable_thinking": False,
        }
    }

cfg = Config(
    dict(
        models=models,
        datasets=datasets,
        work_dir=os.environ["OUT_ROOT"],
        lark_bot_url=None,
        summarizer=dict(type=DefaultSummarizer),
    ),
    format_python_code=False,
)

args = SimpleNamespace(
    max_num_workers=int(os.environ["RUNNER_MAX_WORKERS"]),
    max_workers_per_gpu=1,
    debug=os.environ.get("DEBUG_MODE", "0") == "1",
    slurm=False,
    dlc=False,
    partition=None,
    quotatype=None,
    qos=None,
    retry=int(os.environ["RETRY"]),
    lark=False,
)

mode = os.environ["RUN_MODE"]

if mode in ["all", "infer"]:
    fill_infer_cfg(cfg, args)
    cfg.infer.partitioner["out_dir"] = osp.join(cfg["work_dir"], "predictions")
    infer_tasks = PARTITIONERS.build(cfg.infer.partitioner)(cfg)
    infer_runner = RUNNERS.build(cfg.infer.runner)
    infer_runner(infer_tasks)

if mode in ["all", "eval"]:
    fill_eval_cfg(cfg, args)
    cfg.eval.runner.task.dump_details = True
    cfg.eval.partitioner["out_dir"] = osp.join(cfg["work_dir"], "results")
    eval_tasks = PARTITIONERS.build(cfg.eval.partitioner)(cfg)
    eval_runner = RUNNERS.build(cfg.eval.runner)
    _run_eval_tasks(eval_runner, eval_tasks)

if mode in ["all", "eval", "viz"]:
    summarizer_cfg = cfg.get("summarizer", {}) or {}
    if summarizer_cfg.get("type") is None:
        summarizer_cfg["type"] = DefaultSummarizer
    summarizer_cfg["config"] = cfg
    summarizer = build_from_cfg(summarizer_cfg)
    summarizer.summarize(time_str=datetime.now().strftime("%Y%m%d_%H%M%S"))
PY

echo "DONE ${OUT_ROOT}"
