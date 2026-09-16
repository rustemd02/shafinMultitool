# Label Drift Report

Report: `m4-001-fullruntime-174-drift-r1-label-drift`

Candidate: `m4-001-fullruntime-174-drift-r1`

## Inputs

- Labels: `shafinMultitool/Resources/DeviceBenchmark/camera_device_benchmark_pack_v1/camera_full_labels.jsonl` (sha256 `c1dba72a21551b70cc8edc4bbe9f3484c95776b24b84e8fe5d659f3a4cb0eefc`, 174 records)
- Outputs: `docs/cameraanalysis/eval/camera-baseline-v0/drift-174/m4-001-fullruntime-174-drift-r1.jsonl` (sha256 `34074f33f491c89bffd40bca2e39d518bbbfcbafeefabd4953f1a5fd5700df4d`, 348 rows)
- Images root: `shafinMultitool/Resources/DeviceBenchmark/camera_device_benchmark_pack_v1/images`

## Label/image sha256 bindings

- Verified: 139
- Unverified: 35

Unverified bindings mean the label sha256 does not match the image bytes that were replayed. Metrics restricted to verified bindings are reported separately so the drift numbers can be read on byte-bound records only.

## Full label set

- Records: 174
- pass_rate: 0.37931
- expected_action_hit_rate: 0.465517
- forbidden_action_violation_rate: 0.114943
- good_frame_preservation_rate: 0.518519
- confidence_band_accuracy: 0.66092
- failure_counts: `{"confidence_band_mismatch": 59, "forbidden_action_violation": 20, "good_frame_overcorrection": 39, "missing_expected_action": 93, "missing_future_action": 14, "missing_positive_confirmation": 42, "semantic_overreach_on_technical_failure": 2}`

- strict_drift_rate (set inequality or forbidden hit): 0.712644 (124/174)
- disposition counts: `{"correct": 94, "keep": 48, "silence": 32}`
- by quality label: `{"bad": 79, "good": 81, "mixed": 14}`
- good_frame_overcorrection: 39 (rate 0.224138)
- false_keep_on_non_good: 9 (rate 0.051724)
- silence_on_non_good: 29 (rate 0.166667)

## Byte-verified subset


- Records: 139
- pass_rate: 0.388489
- expected_action_hit_rate: 0.482014
- forbidden_action_violation_rate: 0.093525
- good_frame_preservation_rate: 0.586957
- confidence_band_accuracy: 0.690647
- failure_counts: `{"confidence_band_mismatch": 43, "forbidden_action_violation": 13, "good_frame_overcorrection": 19, "missing_expected_action": 72, "missing_future_action": 14, "missing_positive_confirmation": 21, "semantic_overreach_on_technical_failure": 2}`

- strict_drift_rate (set inequality or forbidden hit): 0.741007 (103/139)
- disposition counts: `{"correct": 74, "keep": 34, "silence": 31}`
- by quality label: `{"bad": 79, "good": 46, "mixed": 14}`
- good_frame_overcorrection: 19 (rate 0.136691)
- false_keep_on_non_good: 9 (rate 0.064748)
- silence_on_non_good: 29 (rate 0.208633)

## Drifted records

Rows whose exported action set differs from the label expectation or hits a forbidden action. Silent rows are shown only when the label expected an action.

| record | quality | disposition | expected | candidate | flags |
| --- | --- | --- | --- | --- | --- |
| ca_img_001 | good | correct | `keep_current_setup` | `change_camera_angle, move_object_back` | expected_miss, good_overcorrection |
| ca_img_002 | mixed | correct | `shift_frame_right, simplify_background` | `change_camera_angle, remove_background_hotspot, simplify_background` | — |
| ca_img_006 | mixed | correct | `add_front_fill_light` | `move_object_right` | expected_miss |
| ca_img_007 | mixed | correct | `add_front_fill_light` | `move_object_right` | expected_miss |
| ca_img_008 | good | correct | `keep_current_setup` | `move_object_right, step_closer` | expected_miss, forbidden:step_closer, good_overcorrection |
| ca_img_009 | good | correct | `keep_current_setup` | `move_object_right` | expected_miss, good_overcorrection |
| ca_img_011 | good | correct | `keep_current_setup` | `add_front_fill_light, change_camera_angle, rotate_subject_toward_light, step_closer` | expected_miss, good_overcorrection |
| ca_img_012 | good | correct | `keep_current_setup` | `move_object_right` | expected_miss, good_overcorrection |
| ca_img_013 | mixed | correct | `shift_frame_right, simplify_background` | `shift_frame_right, step_back` | — |
| ca_img_014 | mixed | correct | `simplify_background, wait_for_background_clearance` | `move_object_right` | expected_miss |
| ca_img_017 | good | correct | `keep_current_setup` | `change_camera_angle, move_object_back, move_object_right, simplify_background` | expected_miss, forbidden:simplify_background, good_overcorrection |
| ca_img_019 | good | correct | `keep_current_setup` | `shift_frame_left, step_back` | expected_miss, good_overcorrection |
| ca_img_020 | good | correct | `keep_current_setup` | `change_camera_angle, remove_background_hotspot, simplify_background` | expected_miss, forbidden:simplify_background, good_overcorrection |
| ca_img_021 | good | correct | `keep_current_setup` | `move_object_right` | expected_miss, good_overcorrection |
| ca_img_022 | mixed | correct | `add_front_fill_light` | `change_camera_angle, move_object_back` | expected_miss |
| ca_img_028 | good | correct | `keep_current_setup` | `move_object_right` | expected_miss, good_overcorrection |
| ca_img_031 | good | correct | `keep_current_setup` | `move_object_left` | expected_miss, good_overcorrection |
| ca_img_033 | mixed | correct | `simplify_background` | `change_camera_angle, move_object_back, move_object_right, simplify_background` | — |
| ca_img_034 | good | correct | `keep_current_setup` | `shift_frame_down, shift_frame_up` | expected_miss, good_overcorrection |
| ca_img_035 | mixed | correct | `add_background_light, add_front_fill_light` | `move_object_right` | expected_miss |
| ca_img_036 | good | correct | `keep_current_setup` | `move_object_right` | expected_miss, good_overcorrection |
| ca_img_037 | good | correct | `keep_current_setup` | `change_camera_angle, move_object_back, move_object_right, simplify_background` | expected_miss, good_overcorrection |
| ca_img_042 | good | correct | `keep_current_setup` | `move_object_left` | expected_miss, good_overcorrection |
| ca_img_043 | good | correct | `keep_current_setup` | `move_object_left` | expected_miss, good_overcorrection |
| ca_img_044 | good | silence | `keep_current_setup` | `—` | expected_miss |
| ca_img_045 | good | silence | `keep_current_setup` | `—` | expected_miss |
| ca_img_050 | good | correct | `keep_current_setup` | `move_object_right` | expected_miss, good_overcorrection |
| ca_img_051 | good | correct | `keep_current_setup` | `move_object_right` | expected_miss, good_overcorrection |
| ca_img_057 | good | correct | `keep_current_setup` | `move_object_right` | expected_miss, good_overcorrection |
| ca_img_058 | bad | correct | `—` | `change_camera_angle, remove_background_hotspot, simplify_background, wait_for_background_clearance` | — |
| ca_img_059 | bad | correct | `—` | `move_object_right` | — |
| ca_img_062 | bad | correct | `—` | `change_camera_angle, remove_background_hotspot, simplify_background` | — |
| ca_img_064 | bad | correct | `remove_background_hotspot` | `change_camera_angle, remove_background_hotspot, simplify_background` | — |
| ca_img_065 | bad | correct | `change_camera_angle` | `change_camera_angle, remove_background_hotspot, simplify_background` | — |
| ca_img_067 | bad | correct | `simplify_background` | `change_camera_angle, remove_background_hotspot, simplify_background` | — |
| ca_img_069 | bad | correct | `remove_background_hotspot` | `change_camera_angle, remove_background_hotspot, simplify_background` | — |
| ca_img_070 | bad | correct | `—` | `shift_frame_right, step_back` | — |
| ca_img_071 | bad | correct | `—` | `simplify_background` | — |
| ca_img_072 | bad | correct | `change_camera_angle` | `change_camera_angle, remove_background_hotspot, simplify_background` | — |
| ca_img_073 | bad | correct | `remove_background_hotspot` | `change_camera_angle, remove_background_hotspot, simplify_background` | — |
| ca_img_074 | bad | correct | `level_horizon` | `change_camera_angle, remove_background_hotspot, simplify_background` | expected_miss |
| ca_img_075 | bad | correct | `change_camera_angle` | `change_camera_angle, remove_background_hotspot, simplify_background` | — |
| ca_img_076 | bad | correct | `wait_for_background_clearance` | `change_camera_angle, remove_background_hotspot, simplify_background` | expected_miss |
| ca_img_077 | bad | keep | `simplify_background` | `keep_current_setup` | expected_miss, forbidden:keep_current_setup, false_keep |
| ca_img_078 | bad | correct | `—` | `change_camera_angle, move_object_back` | — |
| ca_img_080 | bad | correct | `remove_background_hotspot, step_closer` | `change_camera_angle, remove_background_hotspot, simplify_background, wait_for_background_clearance` | — |
| ca_img_081 | bad | correct | `—` | `move_object_left` | — |
| ca_img_082 | bad | silence | `simplify_background` | `—` | expected_miss |
| ca_img_083 | bad | correct | `add_front_fill_light` | `move_object_right` | expected_miss |
| ca_img_084 | bad | correct | `wait_for_background_clearance` | `change_camera_angle, remove_background_hotspot, simplify_background` | expected_miss |
| ca_img_085 | bad | correct | `simplify_background, step_closer` | `change_camera_angle, move_object_back` | expected_miss |
| ca_img_087 | bad | correct | `remove_background_hotspot` | `change_camera_angle, remove_background_hotspot, simplify_background` | — |
| ca_img_088 | bad | silence | `change_camera_angle` | `—` | expected_miss |
| ca_img_089 | bad | silence | `remove_background_hotspot` | `—` | expected_miss |
| ca_img_090 | bad | correct | `—` | `move_object_right` | — |
| ca_img_091 | bad | correct | `remove_background_hotspot` | `change_camera_angle, remove_background_hotspot, simplify_background` | — |
| ca_img_092 | bad | correct | `step_back` | `change_camera_angle, remove_background_hotspot, simplify_background` | expected_miss |
| ca_img_093 | bad | silence | `add_front_fill_light, step_closer` | `—` | expected_miss |
| ca_img_095 | mixed | silence | `step_back` | `—` | expected_miss |
| ca_img_096 | mixed | silence | `step_closer` | `—` | expected_miss |
| ca_img_097 | bad | keep | `simplify_background, wait_for_background_clearance` | `keep_current_setup` | expected_miss, forbidden:keep_current_setup, false_keep |
| ca_img_098 | bad | correct | `simplify_background` | `change_camera_angle, remove_background_hotspot, simplify_background` | — |
| ca_img_099 | bad | correct | `remove_background_hotspot, simplify_background` | `change_camera_angle, remove_background_hotspot, simplify_background` | — |
| ca_img_100 | bad | correct | `—` | `move_object_left` | — |
| ca_img_101 | mixed | correct | `add_front_fill_light` | `move_object_right` | expected_miss |
| ca_img_102 | bad | correct | `remove_background_hotspot` | `change_camera_angle, remove_background_hotspot, simplify_background` | — |
| ca_img_103 | bad | correct | `—` | `shift_frame_down, shift_frame_up` | — |
| ca_img_104 | bad | correct | `simplify_background, wait_for_background_clearance` | `move_object_left` | expected_miss |
| ca_img_105 | bad | correct | `—` | `move_object_left` | — |
| ca_img_106 | bad | correct | `remove_background_hotspot` | `change_camera_angle, remove_background_hotspot, simplify_background` | — |
| ca_img_107 | bad | correct | `simplify_background, wait_for_background_clearance` | `move_object_right` | expected_miss |
| ca_img_108 | good | correct | `keep_current_setup` | `move_object_right` | expected_miss, good_overcorrection |
| ca_img_109 | good | correct | `keep_current_setup` | `move_object_left` | expected_miss, good_overcorrection |
| ca_img_111 | good | correct | `keep_current_setup` | `move_object_left` | expected_miss, good_overcorrection |
| ca_img_117 | good | correct | `keep_current_setup` | `move_object_left` | expected_miss, good_overcorrection |
| ca_img_122 | good | correct | `keep_current_setup` | `move_object_right` | expected_miss, good_overcorrection |
| ca_img_123 | good | correct | `keep_current_setup` | `change_camera_angle, remove_background_hotspot, simplify_background` | expected_miss, forbidden:change_camera_angle,remove_background_hotspot,simplify_background, good_overcorrection |
| ca_img_128 | good | correct | `keep_current_setup` | `add_front_fill_light, change_camera_angle, rotate_subject_toward_light, step_closer` | expected_miss, forbidden:add_front_fill_light,change_camera_angle,step_closer, good_overcorrection |
| ca_img_130 | good | correct | `keep_current_setup` | `change_camera_angle, remove_background_hotspot, simplify_background` | expected_miss, forbidden:change_camera_angle,remove_background_hotspot,simplify_background, good_overcorrection |
| ca_img_131 | good | correct | `keep_current_setup` | `move_object_right` | expected_miss, good_overcorrection |
| ca_img_134 | good | correct | `keep_current_setup` | `move_object_right` | expected_miss, good_overcorrection |
| ca_img_135 | good | correct | `keep_current_setup` | `move_object_left` | expected_miss, good_overcorrection |
| ca_img_137 | good | correct | `keep_current_setup` | `move_object_left` | expected_miss, good_overcorrection |
| ca_img_138 | good | correct | `keep_current_setup` | `change_camera_angle, move_object_back, move_object_right, simplify_background` | expected_miss, forbidden:change_camera_angle,simplify_background, good_overcorrection |
| ca_img_145 | good | correct | `keep_current_setup` | `change_camera_angle, remove_background_hotspot, simplify_background` | expected_miss, forbidden:change_camera_angle,remove_background_hotspot,simplify_background, good_overcorrection |
| ca_img_146 | good | correct | `keep_current_setup` | `move_object_right` | expected_miss, good_overcorrection |
| ca_img_147 | good | correct | `keep_current_setup` | `change_camera_angle, remove_background_hotspot, simplify_background` | expected_miss, forbidden:change_camera_angle,remove_background_hotspot,simplify_background, good_overcorrection |
| ca_img_148 | good | correct | `keep_current_setup` | `move_object_left` | expected_miss, good_overcorrection |
| ca_img_150 | good | silence | `keep_current_setup` | `—` | expected_miss |
| ca_img_154 | good | correct | `keep_current_setup` | `move_object_right` | expected_miss, good_overcorrection |
| ca_img_155 | good | correct | `keep_current_setup` | `move_object_right` | expected_miss, good_overcorrection |
| ca_img_156 | good | correct | `keep_current_setup` | `change_camera_angle, move_object_back, move_object_left, simplify_background` | expected_miss, forbidden:change_camera_angle,simplify_background, good_overcorrection |
| ca_img_208 | bad | correct | `remove_distracting_object, simplify_background, step_closer` | `change_camera_angle, move_object_back` | expected_miss |
| ca_img_209 | bad | silence | `remove_distracting_object, shift_frame_left, step_back` | `—` | expected_miss |
| ca_img_210 | bad | correct | `add_front_fill_light, change_camera_angle, remove_background_hotspot` | `move_object_right` | expected_miss |
| ca_img_211 | bad | silence | `add_front_fill_light, rotate_subject_toward_light` | `—` | expected_miss |
| ca_img_212 | bad | keep | `simplify_background, step_closer` | `keep_current_setup` | expected_miss, forbidden:keep_current_setup, false_keep |
| ca_img_213 | bad | silence | `remove_distracting_object, shift_frame_right, step_back` | `—` | expected_miss |
| ca_img_214 | bad | correct | `remove_distracting_object, simplify_background, wait_for_background_clearance` | `change_camera_angle, move_object_back, simplify_background` | — |
| ca_img_215 | bad | correct | `shift_frame_down, step_back` | `move_object_right` | expected_miss |
| ca_img_216 | bad | keep | `remove_distracting_object, shift_frame_left, step_back` | `keep_current_setup` | expected_miss, forbidden:keep_current_setup, false_keep |
| ca_img_217 | bad | correct | `add_front_fill_light, change_camera_angle, remove_background_hotspot` | `move_object_right` | expected_miss |
| ca_img_218 | bad | silence | `add_front_fill_light, rotate_subject_toward_light` | `—` | expected_miss |
| ca_img_219 | bad | correct | `remove_distracting_object, simplify_background` | `shift_frame_down, shift_frame_up` | expected_miss |
| ca_img_220 | bad | keep | `shift_frame_down, step_closer` | `keep_current_setup` | expected_miss, forbidden:keep_current_setup, false_keep |
| ca_img_221 | bad | keep | `remove_distracting_object, shift_frame_left, wait_for_background_clearance` | `keep_current_setup` | expected_miss, forbidden:keep_current_setup, false_keep |
| ca_img_222 | bad | correct | `remove_distracting_object, simplify_background, step_back` | `move_object_left, rotate_subject_toward_light, simplify_background, step_closer` | forbidden:step_closer |
| ca_img_223 | bad | silence | `change_camera_angle, remove_background_hotspot` | `—` | expected_miss |
| ca_img_224 | bad | silence | `add_front_fill_light, rotate_subject_toward_light` | `—` | expected_miss |
| ca_img_225 | bad | correct | `shift_frame_right, step_back` | `change_camera_angle, remove_background_hotspot, simplify_background` | expected_miss |
| ca_img_226 | bad | correct | `remove_distracting_object, shift_frame_left, step_back` | `change_camera_angle, move_object_back, move_object_right, simplify_background` | expected_miss |
| ca_img_227 | bad | keep | `remove_distracting_object, simplify_background` | `keep_current_setup` | expected_miss, forbidden:keep_current_setup, false_keep |
| ca_img_228 | bad | silence | `step_closer` | `—` | expected_miss |
| ca_img_229 | bad | silence | `add_front_fill_light, change_camera_angle, remove_background_hotspot` | `—` | expected_miss |
| ca_img_230 | bad | keep | `shift_frame_down, step_back` | `keep_current_setup` | expected_miss, forbidden:keep_current_setup, false_keep |
| ca_img_231 | bad | correct | `remove_distracting_object, wait_for_background_clearance` | `change_camera_angle, remove_background_hotspot, simplify_background` | expected_miss |
| ca_img_232 | bad | silence | `remove_distracting_object, simplify_background` | `—` | expected_miss |
| ca_img_233 | bad | correct | `add_front_fill_light, rotate_subject_toward_light` | `move_object_left` | expected_miss |
| ca_img_234 | bad | silence | `change_camera_angle, remove_background_hotspot` | `—` | expected_miss |
| ca_img_235 | bad | silence | `shift_frame_right, step_back` | `—` | expected_miss |
| ca_img_236 | bad | correct | `step_closer` | `shift_frame_down, shift_frame_up` | expected_miss |
| ca_img_237 | bad | silence | `remove_distracting_object, simplify_background` | `—` | expected_miss |
| ca_img_238 | bad | keep | `add_front_fill_light, rotate_subject_toward_light` | `keep_current_setup` | expected_miss, forbidden:keep_current_setup, false_keep |
| ca_img_239 | bad | correct | `change_camera_angle, remove_background_hotspot` | `change_camera_angle, remove_background_hotspot, simplify_background` | — |
