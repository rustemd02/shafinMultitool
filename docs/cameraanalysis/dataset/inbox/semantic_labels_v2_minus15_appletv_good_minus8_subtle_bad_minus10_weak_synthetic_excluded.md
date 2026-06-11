# Excluded weak or false synthetic cases

- Source label set: `docs/cameraanalysis/dataset/inbox/semantic_labels_v2_minus15_appletv_good_minus8_subtle_bad.jsonl`
- New label set: `docs/cameraanalysis/dataset/inbox/semantic_labels_v2_minus15_appletv_good_minus8_subtle_bad_minus10_weak_synthetic.jsonl`
- Excluded records: `10`
- Remaining records: `174`

These removals follow visual audit of the frames themselves. The goal is to remove weak or misleading synthetic negatives, not to tune runtime metrics by hiding clearly bad cases.

| Record ID | Bucket | Reason |
|---|---|---|
| `ca_img_162` | `imagegen_bad_candidate` | imagegen_bad: silhouette hallway reads as intentional low-key/backlight shot, not an obvious bad demo frame. |
| `ca_img_167` | `imagegen_bad_candidate` | imagegen_bad: busy sci-fi portrait remains visually strong and cinematic despite clutter label. |
| `ca_img_177` | `imagegen_bad_candidate` | imagegen_bad: tight portrait crop is aggressive but still plausible as stylized framing, not a clear failure. |
| `ca_img_178` | `synthetic_bad_paired_apple_tv_press` | synthetic_bad crooked_horizon: visible defect depends mostly on synthetic rotation corners; horizon issue is too subtle. |
| `ca_img_186` | `synthetic_bad_paired_apple_tv_press` | synthetic_bad crooked_horizon: tilt is weak and does not read as an obvious composition error at demo glance. |
| `ca_img_194` | `synthetic_bad_paired_apple_tv_press` | synthetic_bad crooked_horizon: rotated frame reads mostly as dark stylization, not a clearly bad horizon case. |
| `ca_img_200` | `synthetic_bad_paired_apple_tv_press` | synthetic_bad edge_cutoff: cropped variant stays too close to the parent frame; edge-pressure defect is not obvious enough. |
| `ca_img_202` | `synthetic_bad_paired_apple_tv_press` | synthetic_bad crooked_horizon: almost identical to parent except rotation/black corners; too weak for semantic benchmarking. |
| `ca_img_204` | `synthetic_bad_paired_apple_tv_press` | synthetic_bad underexposed_subject: resulting frame still reads as a legitimate low-key portrait rather than a bad exposure failure. |
| `ca_img_205` | `synthetic_bad_paired_apple_tv_press` | synthetic_bad motion_blur: blur degradation is too mild to be a reliable negative semantic example. |
