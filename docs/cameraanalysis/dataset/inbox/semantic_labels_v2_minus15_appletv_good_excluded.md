Excluded from the `v2_minus15_appletv_good` benchmark variant:

- `ca_img_110`
- `ca_img_113`
- `ca_img_114`
- `ca_img_115`
- `ca_img_118`
- `ca_img_120`
- `ca_img_124`
- `ca_img_126`
- `ca_img_129`
- `ca_img_139`
- `ca_img_140`
- `ca_img_149`
- `ca_img_152`
- `ca_img_153`
- `ca_img_157`

Rationale:

- all 15 records come from `official_promo_cinematic_preservation`
- all 15 are labeled `good` with expected semantic action `keep_current_setup`
- current runtime mostly fails them through confidence/positive-confirmation disagreement rather than through a stable, human-obvious corrective action that should clearly replace the label
- this file documents a benchmark-variant exclusion only; raw image assets remain in the dataset
