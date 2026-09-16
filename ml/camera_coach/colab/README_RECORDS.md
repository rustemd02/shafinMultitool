# Camera Coach v2 records Colab lane (M02)

This lane packages the **existing** v2 trainer CLI for Google Colab. The notebook is orchestration only; it calls
`python3 -m ml.camera_coach.train --config <runtime config> --run-dir <run dir>` and contains no training, loss,
loader or resume logic. Nothing is uploaded to any external service by the packaging steps, and no Google consent
or OAuth flow is attempted (the Drive-mount failure is a known structural defect and is deliberately not retried).

## Owner steps (only these)

1. **Build the two archives on the workstation** (no network, no external upload):

   ```bash
   # Code bundle: the v2 CLI closure, preflight, config template and this notebook.
   python3 tools/dataset/package_camera_colab.py build \
     --profile records \
     --output /tmp/SET_OS_Camera_Coach_Records.zip

   # Data bundle: the typed records, with a manifest carrying hash, size, splits,
   # record schema id/version and the admission/rights status.
   python3 tools/dataset/package_camera_colab.py --pack-records-data \
     --records ml/camera_coach/configs/production_records_smoke.jsonl \
     --admission non_admitted_research \
     --output /tmp/SET_OS_Camera_Coach_Records_DATA.zip
   ```

   Both commands print the whole-archive `sha256` and the run mode. For the current corpus the mode is
   `non_admitted_research`: this is a dry run, not a fit of admitted data.

2. **Open `ml/camera_coach/colab/SET_OS_Camera_Coach_Records.ipynb` in Colab** and select a GPU runtime
   (`Runtime -> Change runtime type -> T4 GPU`) for a real device proof.

3. **Authorize/paste once** into the single parameter block at the top:
   `RUN_ID`, the two archive paths, `EXPECTED_CODE_BUNDLE_SHA256`, `EXPECTED_DATA_BUNDLE_SHA256`,
   `EXECUTION_PROFILE`, `REQUIRE_CUDA`, `ALLOW_CPU_SMOKE`, `RESUME`, `RUNTIME_ROOT`, `DURABLE_DIR`.
   No manual search for an encoder, checkpoint or data folder is required.

4. **Run all.** Colab will ask the browser for the two `.zip` files once (a plain file picker, not Drive OAuth).

5. **Read the output.** The notebook ends by downloading `result-manifest.json` and printing the run id, status,
   actual device, peak VRAM, selected seed and resume lineage. It never claims a fit that did not run.

## What the preflight blocks

`ml/camera_coach/preflight_records_run.py` runs before any fit and exits non-zero (which stops the notebook) when:

- either whole-archive trust anchor is missing or does not match the caller-supplied `sha256`;
- an archive has path traversal, absolute, backslash, duplicate, symlink or non-regular members, or exceeds a
  per-member/total/member-count ceiling;
- an embedded manifest hash, size or allowlist disagrees with the extracted bytes;
- a typed record is malformed, a `locked_test` record appears in a fit bundle, or `train`/`validation` splits are
  missing;
- admission/rights are inconsistent (a rights hash on research data, or `declared_admitted` without one);
- `EXECUTION_PROFILE=full_fit` while the corpus is `non_admitted_research` (Packet A pending, 0 admitted records);
- the runtime config changes anything beyond `device`, `output_root`, `resume_from` and the runtime versions;
- the data hash, v2 model manifest hash or loss hash does not match the runtime config;
- disk, RAM or VRAM is below the estimate for the declared candidate, seeds and epochs;
- `REQUIRE_CUDA` is set but `torch.cuda.is_available()` is false, or the real optimizer step runs on CPU without
  `ALLOW_CPU_SMOKE`. The probe proves the model parameters, batch inputs, loss and gradients actually live on the
  declared device; "GPU selected" alone is never accepted.

The `--code-root` path is used when the notebook already trust-anchored and extracted the code bundle; preflight
re-validates the archive policy and every extracted byte anyway.

## Resume and disconnect

Checkpoints, metrics, config and the receipt are written atomically into the runtime run directory and then published
atomically to `DURABLE_DIR/runs/<RUN_ID>`. Re-running Run all with the same `RUN_ID`:

- resumes the same run when the durable checkpoint's `resume_semantic_sha256` (code/config/data/device) matches;
- otherwise preflight refuses; start a **new** run id with an explicit warm-start from the durable best checkpoint.

`DURABLE_DIR` defaults to `/content/...`, which is **not** persistent across a Colab VM reset. Point it at an
already-mounted persistent path if you want disconnect recovery; the notebook will not mount Drive itself. Without a
persistent mount, a disconnected run is re-run from the last durable checkpoint only if that directory survived.

## Receipts that must not be overwritten

The existing Stage-1 (`SET_OS_EVA_STAGE1.ipynb`) and Stage-2 (`SET_OS_Camera_Coach_Stage2.ipynb`) notebooks and their
receipts are unchanged and are not re-run by this lane.
