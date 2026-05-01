#!/usr/bin/env bash
set -euo pipefail

REPO="${REPO:-/Users/unterlantas/Documents/XCode/shafinMultitool}"
RUN_ROOT="${RUN_ROOT:-$REPO/docs/SGv7pipeline/runs/v8_0_seed42}"
PREP_ROOT="${PREP_ROOT:-$REPO/docs/SGv7pipeline/runs/sgv7_full_20260417/iter3_1_prep_seed42}"
EVAL_CASES="${EVAL_CASES:-$REPO/experiments/sc_benchmark/workspace/eval_bundle_v1/eval_cases.jsonl}"
CIR_JSONL="${CIR_JSONL:-$REPO/docs/SGv7pipeline/runs/sgv7_full_20260417/final/cir_merged.jsonl}"

mkdir -p "$RUN_ROOT/plan_sft"
mkdir -p "$RUN_ROOT/subtasks"
mkdir -p "$RUN_ROOT/plan_preference_iter2_vs_v7"
mkdir -p "$RUN_ROOT/plan_preference_iter2_vs_iter1"
mkdir -p "$RUN_ROOT/plan_preference"
mkdir -p "$RUN_ROOT/critic_rank_iter2_vs_v7"
mkdir -p "$RUN_ROOT/critic_rank_iter2_vs_iter1"
mkdir -p "$RUN_ROOT/critic_rank"
mkdir -p "$RUN_ROOT/sgv8_train_pack/plan_sft"
mkdir -p "$RUN_ROOT/sgv8_train_pack/plan_preference"
mkdir -p "$RUN_ROOT/sgv8_train_pack/subtasks"
mkdir -p "$RUN_ROOT/sgv8_train_pack/critic_rank"

python3 "$REPO/docs/SGv7pipeline/v8/01_build_v8_plan_dataset.py" \
  --cir-jsonl "$CIR_JSONL" \
  --output-dir "$RUN_ROOT/plan_sft" \
  --val-fraction 0.10 \
  --seed 42

python3 "$REPO/docs/SGv7pipeline/v8/03_build_v8_subtask_datasets.py" \
  --cir-jsonl "$CIR_JSONL" \
  --output-dir "$RUN_ROOT/subtasks" \
  --val-fraction 0.10 \
  --seed 42

python3 "$REPO/docs/SGv7pipeline/v8/04_build_v8_plan_preference_dataset.py" \
  --eval-cases-jsonl "$EVAL_CASES" \
  --candidate-predictions-jsonl "$PREP_ROOT/colab_prep_export_seed42/predictions_dualslice_seed42/dataset_v7_orpo_iter2_seed42.jsonl" \
  --baseline-predictions-jsonl "$PREP_ROOT/colab_prep_export_seed42/predictions_dualslice_seed42/dataset_v7_seed42.jsonl" \
  --candidate-case-results-jsonl "$PREP_ROOT/benchmark_results_seed42/reports/dataset_v7_orpo_iter2/seed_42/case_results.jsonl" \
  --baseline-case-results-jsonl "$PREP_ROOT/benchmark_results_seed42/reports/dataset_v7/seed_42/case_results.jsonl" \
  --candidate-model-id dataset_v7_orpo_iter2 \
  --baseline-model-id dataset_v7 \
  --paired-case-results-jsonl "$PREP_ROOT/benchmark_results_seed42/compares/dataset_v7_orpo_iter2_vs_dataset_v7/seed_42/paired_case_results.jsonl" \
  --output-dir "$RUN_ROOT/plan_preference_iter2_vs_v7" \
  --val-fraction 0.10 \
  --seed 42

python3 "$REPO/docs/SGv7pipeline/v8/04_build_v8_plan_preference_dataset.py" \
  --eval-cases-jsonl "$EVAL_CASES" \
  --candidate-predictions-jsonl "$PREP_ROOT/colab_prep_export_seed42/predictions_dualslice_seed42/dataset_v7_orpo_iter2_seed42.jsonl" \
  --baseline-predictions-jsonl "$PREP_ROOT/colab_prep_export_seed42/predictions_dualslice_seed42/dataset_v7_orpo_iter1_seed42.jsonl" \
  --candidate-case-results-jsonl "$PREP_ROOT/benchmark_results_seed42/reports/dataset_v7_orpo_iter2/seed_42/case_results.jsonl" \
  --baseline-case-results-jsonl "$PREP_ROOT/benchmark_results_seed42/reports/dataset_v7_orpo_iter1/seed_42/case_results.jsonl" \
  --candidate-model-id dataset_v7_orpo_iter2 \
  --baseline-model-id dataset_v7_orpo_iter1 \
  --paired-case-results-jsonl "$PREP_ROOT/benchmark_results_seed42/compares/dataset_v7_orpo_iter2_vs_dataset_v7_orpo_iter1/seed_42/paired_case_results.jsonl" \
  --output-dir "$RUN_ROOT/plan_preference_iter2_vs_iter1" \
  --val-fraction 0.10 \
  --seed 42

cat \
  "$RUN_ROOT/plan_preference_iter2_vs_v7/v8_plan_preference_train.jsonl" \
  "$RUN_ROOT/plan_preference_iter2_vs_iter1/v8_plan_preference_train.jsonl" \
  > "$RUN_ROOT/plan_preference/v8_plan_preference_train.jsonl"

cat \
  "$RUN_ROOT/plan_preference_iter2_vs_v7/v8_plan_preference_val.jsonl" \
  "$RUN_ROOT/plan_preference_iter2_vs_iter1/v8_plan_preference_val.jsonl" \
  > "$RUN_ROOT/plan_preference/v8_plan_preference_val.jsonl"

python3 "$REPO/docs/SGv7pipeline/v8/05_build_v8_critic_rank_dataset.py" \
  --eval-cases-jsonl "$EVAL_CASES" \
  --candidate-predictions-jsonl "$PREP_ROOT/colab_prep_export_seed42/predictions_dualslice_seed42/dataset_v7_orpo_iter2_seed42.jsonl" \
  --baseline-predictions-jsonl "$PREP_ROOT/colab_prep_export_seed42/predictions_dualslice_seed42/dataset_v7_seed42.jsonl" \
  --candidate-case-results-jsonl "$PREP_ROOT/benchmark_results_seed42/reports/dataset_v7_orpo_iter2/seed_42/case_results.jsonl" \
  --baseline-case-results-jsonl "$PREP_ROOT/benchmark_results_seed42/reports/dataset_v7/seed_42/case_results.jsonl" \
  --candidate-model-id dataset_v7_orpo_iter2 \
  --baseline-model-id dataset_v7 \
  --paired-case-results-jsonl "$PREP_ROOT/benchmark_results_seed42/compares/dataset_v7_orpo_iter2_vs_dataset_v7/seed_42/paired_case_results.jsonl" \
  --output-dir "$RUN_ROOT/critic_rank_iter2_vs_v7" \
  --val-fraction 0.10 \
  --seed 42

python3 "$REPO/docs/SGv7pipeline/v8/05_build_v8_critic_rank_dataset.py" \
  --eval-cases-jsonl "$EVAL_CASES" \
  --candidate-predictions-jsonl "$PREP_ROOT/colab_prep_export_seed42/predictions_dualslice_seed42/dataset_v7_orpo_iter2_seed42.jsonl" \
  --baseline-predictions-jsonl "$PREP_ROOT/colab_prep_export_seed42/predictions_dualslice_seed42/dataset_v7_orpo_iter1_seed42.jsonl" \
  --candidate-case-results-jsonl "$PREP_ROOT/benchmark_results_seed42/reports/dataset_v7_orpo_iter2/seed_42/case_results.jsonl" \
  --baseline-case-results-jsonl "$PREP_ROOT/benchmark_results_seed42/reports/dataset_v7_orpo_iter1/seed_42/case_results.jsonl" \
  --candidate-model-id dataset_v7_orpo_iter2 \
  --baseline-model-id dataset_v7_orpo_iter1 \
  --paired-case-results-jsonl "$PREP_ROOT/benchmark_results_seed42/compares/dataset_v7_orpo_iter2_vs_dataset_v7_orpo_iter1/seed_42/paired_case_results.jsonl" \
  --output-dir "$RUN_ROOT/critic_rank_iter2_vs_iter1" \
  --val-fraction 0.10 \
  --seed 42

cat \
  "$RUN_ROOT/critic_rank_iter2_vs_v7/v8_critic_rank_train.jsonl" \
  "$RUN_ROOT/critic_rank_iter2_vs_iter1/v8_critic_rank_train.jsonl" \
  > "$RUN_ROOT/critic_rank/v8_critic_rank_train.jsonl"

cat \
  "$RUN_ROOT/critic_rank_iter2_vs_v7/v8_critic_rank_val.jsonl" \
  "$RUN_ROOT/critic_rank_iter2_vs_iter1/v8_critic_rank_val.jsonl" \
  > "$RUN_ROOT/critic_rank/v8_critic_rank_val.jsonl"

cp "$RUN_ROOT/plan_sft/v8_plan_sft_train.jsonl" "$RUN_ROOT/sgv8_train_pack/plan_sft/"
cp "$RUN_ROOT/plan_sft/v8_plan_sft_val.jsonl" "$RUN_ROOT/sgv8_train_pack/plan_sft/"
cp "$RUN_ROOT/plan_preference/v8_plan_preference_train.jsonl" "$RUN_ROOT/sgv8_train_pack/plan_preference/"
cp "$RUN_ROOT/plan_preference/v8_plan_preference_val.jsonl" "$RUN_ROOT/sgv8_train_pack/plan_preference/"
cp -R "$RUN_ROOT/subtasks/." "$RUN_ROOT/sgv8_train_pack/subtasks/"
cp "$RUN_ROOT/critic_rank/v8_critic_rank_train.jsonl" "$RUN_ROOT/sgv8_train_pack/critic_rank/"
cp "$RUN_ROOT/critic_rank/v8_critic_rank_val.jsonl" "$RUN_ROOT/sgv8_train_pack/critic_rank/"

printf "\nBuilt V8 train pack at:\n%s\n" "$RUN_ROOT/sgv8_train_pack"
