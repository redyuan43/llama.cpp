#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENV_DIR="${OPENCOMPASS_EVAL_VENV:-${ROOT_DIR}/.venv-opencompass-eval}"
OPENCOMPASS_DIR="${OPENCOMPASS_DIR:-${ROOT_DIR}/third_party/opencompass}"
PYTHON_BIN="${OPENCOMPASS_PYTHON_BIN:-python3}"

cd "${ROOT_DIR}"

if [[ ! -d "${VENV_DIR}" ]]; then
  "${PYTHON_BIN}" -m venv "${VENV_DIR}"
fi

# shellcheck disable=SC1091
source "${VENV_DIR}/bin/activate"

python -m pip install --upgrade pip setuptools wheel

if [[ ! -d "${OPENCOMPASS_DIR}/.git" ]]; then
  git clone --depth 1 https://github.com/open-compass/opencompass "${OPENCOMPASS_DIR}"
fi

python -m pip install -e "${OPENCOMPASS_DIR}[api]"
python -m pip install --prefer-binary rdkit socksio

python - <<'PY'
import importlib

mods = ["opencompass", "mmengine", "openai"]
for name in mods:
    importlib.import_module(name)
print("OpenCompass API eval environment is ready")
PY
