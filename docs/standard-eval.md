# Standard Evaluation Entrypoints

这一页只保留“标准评测项目接入”喵，不再推荐自定义拼任务脚本。

当前仓库提供两条入口：

- `OpenCompass`
  - 适合：`HellaSwag`、`WinoGrande`、`MMLU`、`GSM8K`、`HumanEval`
  - 优点：官方大套件、现成数据集配置、适合做更接近榜单口径的跑法
- `LightEval`
  - 适合：`IFEval`、`MMLU-Pro`、`GPQA` 这类生成式 endpoint 任务
  - 优点：轻量、任务覆盖广、细粒度结果保存方便

## 1. OpenCompass

### 安装环境

```bash
bash scripts/setup_opencompass_eval_env.sh
```

默认会：

- 创建 `/.venv-opencompass-eval`
- 克隆 `third_party/opencompass`
- 安装 `opencompass[api]`
- 额外补 `rdkit / socksio`，避免 `MolecularIQ` 导入和 `socks5h` 代理报错

### 运行本地 `llama-server`

```bash
OPENCOMPASS_SERVER_URL="http://127.0.0.1:8095/v1" \
OPENCOMPASS_MODEL_NAME="gpt-oss-120b" \
OPENCOMPASS_TOKENIZER="openai/gpt-oss-120b" \
bash scripts/run_opencompass_local_api_eval.sh
```

默认 `suite=core`，会跑：

- `hellaswag`
- `winogrande`
- `mmlu`
- `gsm8k`

常用变体：

```bash
OPENCOMPASS_SUITE="full" bash scripts/run_opencompass_local_api_eval.sh
OPENCOMPASS_DATASETS="hellaswag,winogrande,mmlu,gsm8k,humaneval" bash scripts/run_opencompass_local_api_eval.sh
OPENCOMPASS_DATASETS="hellaswag" OPENCOMPASS_TEST_RANGE="[:2]" bash scripts/run_opencompass_local_api_eval.sh
OPENCOMPASS_PLAN_ONLY=1 bash scripts/run_opencompass_local_api_eval.sh
```

### 数据集说明

OpenCompass 某些数据集依赖它自己的数据包或 ModelScope 自动下载。
如果首次运行提示缺数据，优先试：

```bash
export DATASET_SOURCE=ModelScope
```

如果仍缺，再按 OpenCompass 官方文档准备数据集喵。

## 2. LightEval

### 安装环境

```bash
bash scripts/setup_lighteval_eval_env.sh
```

默认会：

- 创建 `/.venv-lighteval-eval`
- 默认从 PyPI 安装官方 `lighteval[litellm]`
- 默认钉住 `inspect-ai / huggingface_hub / datasets / fsspec` 这一组版本，避免 `pip` 长时间回溯
- 额外补 `langdetect / tiktoken / immutabledict`

如果要改成源码安装，再显式指定：

```bash
LIGHTEVAL_INSTALL_MODE=source bash scripts/setup_lighteval_eval_env.sh
```

### 运行本地 OpenAI 兼容 API 评测

```bash
LIGHTEVAL_SERVER_URL="http://127.0.0.1:8095/v1" \
LIGHTEVAL_MODEL_NAME="gpt-oss-120b" \
bash scripts/run_lighteval_local_api_eval.sh
```

默认会跑：

- `ifeval`
- `mmlu_pro`

常用变体：

```bash
LIGHTEVAL_TASKS="ifeval,mmlu_pro" bash scripts/run_lighteval_local_api_eval.sh
LIGHTEVAL_TASKS="ifeval,mmlu_pro,gpqa:diamond" bash scripts/run_lighteval_local_api_eval.sh
LIGHTEVAL_MAX_SAMPLES=20 bash scripts/run_lighteval_local_api_eval.sh
LIGHTEVAL_PLAN_ONLY=1 bash scripts/run_lighteval_local_api_eval.sh
```

`GPQA` 在当前官方任务定义里依赖 Hugging Face gated 数据集 `Idavidrein/gpqa`。
如果账号没有拿到访问权限，整次 LightEval 会直接失败，所以默认入口不再把它放进必跑集合；需要时再显式追加喵。

### 能力边界

`LightEval` 这条入口当前走的是 `LiteLLM` endpoint 模式。
这条模式适合生成式任务，但**不实现** `loglikelihood`。

所以：

- `IFEval / MMLU-Pro / GPQA`：优先用 `LightEval`
- `HellaSwag / WinoGrande`：优先用 `OpenCompass`

## 3. 推荐顺序

如果主人现在要测本地 `llama.cpp` 模型质量，月见喵建议这样跑：

1. 先跑 `OpenCompass core`
   - 看基础常识、多选、推理和数学
2. 再跑 `LightEval`
   - 补 `IFEval / MMLU-Pro`
   - 如果已经拿到 Hugging Face 权限，再额外补 `GPQA`
3. 如果是代码模型或要对齐官方更完整口径
   - 再单独补 `HumanEval`

## 4. 抽样简化版

如果主人只是想先快速判断模型综合实力，不想一口气跑完整套，可以直接用：

```bash
bash scripts/run_quick_model_snapshot.sh
```

默认是一个“速度优先”的快照口径：

- `gsm8k`：抽样 `25`
- `winogrande`：抽样 `25`
- `hellaswag`：抽样 `25`
- `mmlu`：每个学科抽样 `2`
- `LightEval`：`ifeval,mmlu_pro`，每项最多 `20`

这个快照的意义是：

- 用很小样本先看数学、常识、多选知识、指令跟随的大致轮廓
- `mmlu` 走“低深度、广覆盖”，比只抽 1 个学科更适合快速判断综合实力
- 结果会自动汇总成一页 Markdown，适合做阶段性判断

常用调整方式：

```bash
QUICK_MMLU_SAMPLES_PER_SUBJECT=3 \
QUICK_LIGHTEVAL_SAMPLES=30 \
bash scripts/run_quick_model_snapshot.sh
```

输出目录示例：

- `outputs/standard-eval/snapshot/<timestamp>/summary/snapshot_summary.md`

## 5. 输出目录

默认输出：

- `outputs/standard-eval/opencompass/<timestamp>/`
- `outputs/standard-eval/lighteval/<timestamp>/`

这些目录已经加入 `.gitignore`，不会污染主分支喵。
