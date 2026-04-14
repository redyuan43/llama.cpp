#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENV_DIR="${LIGHTEVAL_EVAL_VENV:-${ROOT_DIR}/.venv-lighteval-eval}"
LIGHTEVAL_DIR="${LIGHTEVAL_DIR:-${ROOT_DIR}/third_party/lighteval}"
LIGHTEVAL_INSTALL_MODE="${LIGHTEVAL_INSTALL_MODE:-pypi}"
LIGHTEVAL_PACKAGE_SPEC="${LIGHTEVAL_PACKAGE_SPEC:-lighteval[litellm]}"
LIGHTEVAL_PIN_INSPECT_AI="${LIGHTEVAL_PIN_INSPECT_AI:-0.3.140}"
LIGHTEVAL_PIN_HF_HUB="${LIGHTEVAL_PIN_HF_HUB:-0.30.2}"
LIGHTEVAL_PIN_DATASETS="${LIGHTEVAL_PIN_DATASETS:-4.8.4}"
LIGHTEVAL_PIN_FSSPEC="${LIGHTEVAL_PIN_FSSPEC:-2025.9.0}"
LIGHTEVAL_PIN_OPENAI="${LIGHTEVAL_PIN_OPENAI:-2.30.0}"
LIGHTEVAL_PIN_LITELLM="${LIGHTEVAL_PIN_LITELLM:-1.83.7}"
LIGHTEVAL_PIN_DISKCACHE="${LIGHTEVAL_PIN_DISKCACHE:-5.6.3}"
PYTHON_BIN="${LIGHTEVAL_PYTHON_BIN:-python3}"

cd "${ROOT_DIR}"

if [[ ! -d "${VENV_DIR}" ]]; then
  "${PYTHON_BIN}" -m venv "${VENV_DIR}"
fi

# shellcheck disable=SC1091
source "${VENV_DIR}/bin/activate"

python -m pip install --upgrade pip setuptools wheel

case "${LIGHTEVAL_INSTALL_MODE}" in
  pypi)
    python -m pip install --prefer-binary \
      "inspect-ai==${LIGHTEVAL_PIN_INSPECT_AI}" \
      "huggingface_hub[hf_xet]==${LIGHTEVAL_PIN_HF_HUB}" \
      "datasets==${LIGHTEVAL_PIN_DATASETS}" \
      "fsspec==${LIGHTEVAL_PIN_FSSPEC}" \
      "openai==${LIGHTEVAL_PIN_OPENAI}" \
      "litellm[caching]==${LIGHTEVAL_PIN_LITELLM}" \
      "diskcache==${LIGHTEVAL_PIN_DISKCACHE}"
    python -m pip install --prefer-binary "${LIGHTEVAL_PACKAGE_SPEC}"
    python -m pip install --prefer-binary langdetect tiktoken immutabledict socksio
    ;;
  source)
    if [[ ! -d "${LIGHTEVAL_DIR}/.git" ]]; then
      git clone --depth 1 https://github.com/huggingface/lighteval "${LIGHTEVAL_DIR}"
    fi
    python -m pip install --prefer-binary \
      "inspect-ai==${LIGHTEVAL_PIN_INSPECT_AI}" \
      "huggingface_hub[hf_xet]==${LIGHTEVAL_PIN_HF_HUB}" \
      "datasets==${LIGHTEVAL_PIN_DATASETS}" \
      "fsspec==${LIGHTEVAL_PIN_FSSPEC}" \
      "openai==${LIGHTEVAL_PIN_OPENAI}" \
      "litellm[caching]==${LIGHTEVAL_PIN_LITELLM}" \
      "diskcache==${LIGHTEVAL_PIN_DISKCACHE}"
    python -m pip install --prefer-binary -e "${LIGHTEVAL_DIR}[litellm]"
    python -m pip install --prefer-binary langdetect tiktoken immutabledict socksio
    ;;
  *)
    echo "Unsupported LIGHTEVAL_INSTALL_MODE: ${LIGHTEVAL_INSTALL_MODE}" >&2
    exit 1
    ;;
esac

python - <<'PY'
import importlib

mods = ["lighteval", "litellm", "immutabledict"]
for name in mods:
    importlib.import_module(name)
print("LightEval endpoint environment is ready")
PY
