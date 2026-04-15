#!/usr/bin/env python3
import csv
import json
import re
import sys
from pathlib import Path


def extract_choice(text: str | None) -> str | None:
    if not text:
        return None
    matches = re.findall(r"ANSWER:\s*([ABCD])\b", text, flags=re.I)
    if matches:
        return matches[-1].upper()
    matches = re.findall(r"\b([ABCD])\b", text[-32:])
    if matches:
        return matches[-1].upper()
    return None


def extract_num(text: str | None) -> str | None:
    if not text:
        return None
    patterns = [
        r"####\s*([-+]?\d+(?:[\d,]*)(?:\.\d+)?)",
        r"\*\*Answer:?\*\*[^0-9+-]*([-+]?\d+(?:[\d,]*)(?:\.\d+)?)",
        r"[Tt]he answer is[^0-9+-]*([-+]?\d+(?:[\d,]*)(?:\.\d+)?)",
        r"ANSWER:\s*([-+]?\d+(?:[\d,]*)(?:\.\d+)?)",
    ]
    for pattern in patterns:
        matches = re.findall(pattern, text)
        if matches:
            return matches[-1].replace(",", "")
    matches = re.findall(r"[-+]?\d+(?:\.\d+)?", text)
    return matches[-1].replace(",", "") if matches else None


def parse_opencompass_predictions(pred_dir: Path) -> list[dict]:
    rows: list[dict] = []
    if not pred_dir.exists():
        return rows

    gsm8k = pred_dir / "gsm8k.json"
    if gsm8k.exists():
        obj = json.loads(gsm8k.read_text())
        total = len(obj)
        correct = 0
        for item in obj.values():
            pred = extract_num(item.get("prediction", ""))
            gold = extract_num(item.get("gold", ""))
            correct += pred == gold
        rows.append(
            dict(
                area="math",
                benchmark="gsm8k",
                samples=total,
                score=correct / total if total else None,
                note="final-number exact match",
            )
        )

    wino = pred_dir / "winogrande.json"
    if wino.exists():
        obj = json.loads(wino.read_text())
        total = len(obj)
        correct = 0
        for item in obj.values():
            pred = extract_choice(item.get("prediction", ""))
            gold = str(item.get("gold", "")).strip().upper()[:1]
            correct += pred == gold
        rows.append(
            dict(
                area="commonsense",
                benchmark="winogrande",
                samples=total,
                score=correct / total if total else None,
                note="choice accuracy",
            )
        )

    hella = pred_dir / "hellaswag.json"
    if hella.exists():
        obj = json.loads(hella.read_text())
        total = len(obj)
        correct = 0
        for item in obj.values():
            pred = extract_choice(item.get("prediction", ""))
            gold = str(item.get("gold", "")).strip().upper()[:1]
            correct += pred == gold
        rows.append(
            dict(
                area="commonsense",
                benchmark="hellaswag",
                samples=total,
                score=correct / total if total else None,
                note="choice accuracy",
            )
        )

    mmlu_files = sorted(pred_dir.glob("lukaemon_mmlu_*.json"))
    if mmlu_files:
        weighted_correct = 0
        weighted_total = 0
        for path in mmlu_files:
            obj = json.loads(path.read_text())
            total = len(obj)
            correct = 0
            for item in obj.values():
                pred = extract_choice(item.get("prediction", ""))
                gold = str(item.get("gold", "")).strip().upper()[:1]
                correct += pred == gold
            weighted_correct += correct
            weighted_total += total
        rows.append(
            dict(
                area="knowledge",
                benchmark="mmlu_micro",
                samples=weighted_total,
                score=weighted_correct / weighted_total if weighted_total else None,
                note=f"{len(mmlu_files)} subjects weighted",
            )
        )

    return rows


def parse_lighteval_results(results_root: Path) -> list[dict]:
    files = sorted(results_root.glob("**/results_*.json"))
    if not files:
        return []

    obj = json.loads(files[-1].read_text())
    results = obj.get("results", {})
    rows: list[dict] = []

    if "ifeval|0" in results:
        metrics = results["ifeval|0"]
        strict = metrics.get("prompt_level_strict_acc")
        loose = metrics.get("prompt_level_loose_acc")
        if strict is not None:
            rows.append(
                dict(
                    area="instruction_following",
                    benchmark="ifeval_strict",
                    samples=obj.get("config_general", {}).get("max_samples"),
                    score=float(strict),
                    note="prompt_level_strict_acc",
                )
            )
        if loose is not None:
            rows.append(
                dict(
                    area="instruction_following",
                    benchmark="ifeval_loose",
                    samples=obj.get("config_general", {}).get("max_samples"),
                    score=float(loose),
                    note="prompt_level_loose_acc",
                )
            )

    if "mmlu_pro|0" in results:
        metrics = results["mmlu_pro|0"]
        metric_names = [
            key
            for key in metrics
            if not key.endswith("_stderr") and isinstance(metrics[key], (int, float))
        ]
        if metric_names:
            key = metric_names[0]
            rows.append(
                dict(
                    area="expert_knowledge",
                    benchmark="mmlu_pro",
                    samples=obj.get("config_general", {}).get("max_samples"),
                    score=float(metrics[key]),
                    note=key,
                )
            )

    return rows


def write_summary(out_root: Path, rows: list[dict]) -> None:
    summary_dir = out_root / "summary"
    summary_dir.mkdir(parents=True, exist_ok=True)

    csv_path = summary_dir / "snapshot_scores.csv"
    with csv_path.open("w", newline="") as f:
        writer = csv.DictWriter(
            f, fieldnames=["area", "benchmark", "samples", "score", "note"]
        )
        writer.writeheader()
        for row in rows:
            writer.writerow(row)

    available_scores = [row["score"] for row in rows if row.get("score") is not None]
    overall = sum(available_scores) / len(available_scores) if available_scores else None

    md_path = summary_dir / "snapshot_summary.md"
    with md_path.open("w") as f:
        f.write("# Quick Model Snapshot\n\n")
        if overall is None:
            f.write("No completed benchmark results were found.\n")
            return
        f.write(f"- overall_snapshot_score: {overall * 100:.2f}\n")
        f.write(f"- completed_benchmarks: {len(available_scores)}\n\n")
        f.write("| area | benchmark | samples | score | note |\n")
        f.write("| --- | --- | ---: | ---: | --- |\n")
        for row in rows:
            score = "-" if row["score"] is None else f"{row['score'] * 100:.2f}"
            samples = "-" if row["samples"] is None else str(row["samples"])
            f.write(
                f"| {row['area']} | {row['benchmark']} | {samples} | {score} | {row['note']} |\n"
            )


def main() -> int:
    if len(sys.argv) != 2:
        print(f"usage: {Path(sys.argv[0]).name} <snapshot-output-dir>", file=sys.stderr)
        return 1

    out_root = Path(sys.argv[1]).resolve()
    rows = []
    rows.extend(parse_opencompass_predictions(out_root / "opencompass" / "predictions"))
    rows.extend(parse_lighteval_results(out_root / "lighteval"))
    write_summary(out_root, rows)
    print(out_root / "summary" / "snapshot_summary.md")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
