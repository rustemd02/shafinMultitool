from __future__ import annotations

from dataclasses import dataclass, field


STRICT_SFT_TIERS = {"tier_a_human_gold", "tier_b_deterministic_canonical"}


@dataclass(frozen=True)
class TrainingPhaseConfig:
    phase: str
    task_type: str
    pool_ratios: dict[str, float] = field(default_factory=dict)
    pool_multipliers: dict[str, float] = field(default_factory=dict)
    max_l_sample_ratio: float = 1.0
    max_l_token_ratio: float = 1.0
    max_full_sequence_tokens: int | None = None
    max_reviewed_merge_hard_ratio_by_samples: float | None = None
    max_reviewed_merge_hard_ratio_by_tokens: float | None = None
    max_reviewed_merge_total_ratio_by_samples: float | None = None
    phase3_eval_interval_steps: int | None = None
    phase3_positive_bucket_improvement_pp: float | None = None
    phase4_min_preference_train: int | None = None
    phase4_min_preference_val: int | None = None
    phase4_min_preference_test: int | None = None
    phase4_min_preference_win_rate_gain_pp: float | None = None


def default_phase_config(phase: str) -> TrainingPhaseConfig:
    normalized = phase.strip().lower()
    if normalized in {"phase1", "phase1_core", "phase1_core_bootstrap"}:
        return TrainingPhaseConfig(
            phase="phase1_core_bootstrap",
            task_type="sft",
            pool_ratios={"core_anchor": 1.0},
            pool_multipliers={"core_anchor": 1.0},
            max_l_sample_ratio=0.0,
            max_l_token_ratio=0.0,
            max_full_sequence_tokens=420,
        )
    if normalized in {"phase2", "phase2_mix", "phase2_mixed_sft"}:
        return TrainingPhaseConfig(
            phase="phase2_mixed_sft",
            task_type="sft",
            pool_ratios={
                "core_anchor": 0.70,
                "hard_synthetic": 0.25,
                "real_corrected_strict": 0.05,
            },
            pool_multipliers={
                "core_anchor": 1.0,
                "hard_synthetic": 1.6,
                "real_corrected_strict": 1.5,
            },
            max_l_sample_ratio=0.15,
            max_l_token_ratio=0.15,
            max_full_sequence_tokens=560,
        )
    if normalized in {"phase3", "phase3_hard", "phase3_hard_consolidation"}:
        return TrainingPhaseConfig(
            phase="phase3_hard_consolidation",
            task_type="sft",
            pool_ratios={
                "core_anchor": 0.45,
                "hard_synthetic": 0.45,
                "real_corrected_strict": 0.08,
                "reviewed_merge_hard": 0.02,
            },
            pool_multipliers={
                "core_anchor": 1.0,
                "hard_synthetic": 2.0,
                "real_corrected_strict": 1.5,
                "reviewed_merge_hard": 1.0,
            },
            max_l_sample_ratio=0.15,
            max_l_token_ratio=0.15,
            max_reviewed_merge_hard_ratio_by_samples=0.05,
            max_reviewed_merge_hard_ratio_by_tokens=0.05,
            max_reviewed_merge_total_ratio_by_samples=0.02,
            phase3_eval_interval_steps=1000,
            phase3_positive_bucket_improvement_pp=0.3,
        )
    if normalized in {"phase4", "phase4_preference"}:
        return TrainingPhaseConfig(
            phase="phase4_preference",
            task_type="preference",
            pool_ratios={"preference": 1.0},
            pool_multipliers={"preference": 1.0},
            phase4_min_preference_train=1000,
            phase4_min_preference_val=100,
            phase4_min_preference_test=100,
            phase4_min_preference_win_rate_gain_pp=3.0,
        )
    raise ValueError(f"unsupported phase={phase!r}")

