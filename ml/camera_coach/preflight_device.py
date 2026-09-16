#!/usr/bin/env python3
"""GPU-first preflight for Camera Coach training runs.

Rationale (2026-09-13): a Stage-2 run launched with ``--device mps`` fell back
to single-core CPU and took ~2 hours for 5 epochs of 5,584 examples. The same
work on a Colab T4 takes minutes. Training must therefore verify the actual
accelerator BEFORE the run starts and refuse to start on CPU unless the caller
explicitly overrides it for a bounded smoke test.

Usage (call it from the Colab notebook / CI before a real run)::

    python3 ml/camera_coach/preflight_device.py                 # require CUDA
    python3 ml/camera_coach/preflight_device.py --allow-cpu     # bounded smoke only

Exit codes: 0 = accelerator available (or override), 1 = refuse to train.
"""

from __future__ import annotations

import argparse
import platform
import sys


def _probe() -> dict:
    info: dict = {"python": sys.version.split()[0], "platform": platform.platform()}
    try:
        import torch
    except Exception as exc:  # pragma: no cover - dependency missing
        return {**info, "torch": None, "error": f"torch import failed: {exc}"}

    info["torch"] = torch.__version__
    info["cuda_available"] = bool(torch.cuda.is_available())
    info["cuda_device_count"] = torch.cuda.device_count() if info["cuda_available"] else 0
    if info["cuda_available"]:
        info["cuda_device_name"] = torch.cuda.get_device_name(0)
        props = torch.cuda.get_device_properties(0)
        info["cuda_total_memory_gb"] = round(props.total_memory / (1024**3), 2)
        info["cuda_capability"] = f"{props.major}.{props.minor}"
    try:
        info["mps_available"] = bool(torch.backends.mps.is_available())
    except Exception:
        info["mps_available"] = False
    return info


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--allow-cpu",
        action="store_true",
        help="permit a CPU run; use only for a bounded smoke test, never a real fit",
    )
    args = parser.parse_args(argv)

    info = _probe()
    for key, value in info.items():
        print(f"{key}: {value}")

    if info.get("torch") is None:
        print("REFUSE: torch is unavailable", file=sys.stderr)
        return 1

    if info["cuda_available"]:
        print("OK: CUDA accelerator present — safe to train.")
        return 0

    hint = (
        "No CUDA device. On Colab switch Runtime -> Change runtime type -> T4 GPU, "
        "then re-run; on the Mac, MPS is NOT a substitute (operators fall back to "
        "single-core CPU and the run is ~an order of magnitude slower)."
    )
    if args.allow_cpu:
        print(f"WARNING: running on CPU by explicit override. {hint}")
        return 0
    print(f"REFUSE: {hint}", file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
