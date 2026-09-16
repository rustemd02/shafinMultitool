# Label Drift Report

Report: `m4-001-fullruntime-174-drift-r1-technical-override-label-drift`

Candidate: `m4-001-fullruntime-174-drift-r1-technical-override`

## Inputs

- Labels: `shafinMultitool/Resources/DeviceBenchmark/camera_device_benchmark_pack_v1/camera_full_labels.jsonl` (sha256 `c1dba72a21551b70cc8edc4bbe9f3484c95776b24b84e8fe5d659f3a4cb0eefc`, 174 records)
- Outputs: `docs/cameraanalysis/eval/camera-baseline-v0/drift-174-technical-override/m4-001-fullruntime-174-drift-r1-technical-override.jsonl` (sha256 `8c0f936f773ca307d9211f524f77e904f5d4344087eb048baf708fa128684582`, 348 rows)
- Images root: `shafinMultitool/Resources/DeviceBenchmark/camera_device_benchmark_pack_v1/images`

## Label/image sha256 bindings

- Verified: 139
- Unverified: 35

Unverified bindings mean the label sha256 does not match the image bytes that were replayed. Metrics restricted to verified bindings are reported separately so the drift numbers can be read on byte-bound records only.

## Full label set

- Records: 174
- pass_rate: 0.534483
- expected_action_hit_rate: 0.689655
- forbidden_action_violation_rate: 0.137931
- good_frame_preservation_rate: 0.839506
- confidence_band_accuracy: 0.724138
- failure_counts: `{"confidence_band_mismatch": 48, "forbidden_action_violation": 24, "good_frame_overcorrection": 13, "missing_expected_action": 54, "missing_future_action": 8, "missing_positive_confirmation": 16, "semantic_overreach_on_technical_failure": 2}`

- strict_drift_rate (set inequality or forbidden hit): 0.54023 (94/174)
- disposition counts: `{"correct": 62, "keep": 84, "silence": 28}`
- by quality label: `{"bad": 79, "good": 81, "mixed": 14}`
- good_frame_overcorrection: 13 (rate 0.074713)
- false_keep_on_non_good: 22 (rate 0.126437)
- silence_on_non_good: 25 (rate 0.143678)

## Byte-verified subset


- Records: 139
- pass_rate: 0.489209
- expected_action_hit_rate: 0.661871
- forbidden_action_violation_rate: 0.129496
- good_frame_preservation_rate: 0.847826
- confidence_band_accuracy: 0.705036
- failure_counts: `{"confidence_band_mismatch": 41, "forbidden_action_violation": 18, "good_frame_overcorrection": 7, "missing_expected_action": 47, "missing_future_action": 8, "missing_positive_confirmation": 9, "semantic_overreach_on_technical_failure": 2}`

- strict_drift_rate (set inequality or forbidden hit): 0.625899 (87/139)
- disposition counts: `{"correct": 56, "keep": 56, "silence": 27}`
- by quality label: `{"bad": 79, "good": 46, "mixed": 14}`
- good_frame_overcorrection: 7 (rate 0.05036)
- false_keep_on_non_good: 22 (rate 0.158273)
- silence_on_non_good: 25 (rate 0.179856)

## Drifted records

Rows whose exported action set differs from the label expectation or hits a forbidden action. Silent rows are shown only when the label expected an action.

| record | quality | disposition | expected | candidate | flags |
| --- | --- | --- | --- | --- | --- |
| ca_img_001 | good | correct | `keep_current_setup` | `change_camera_angle, move_object_back` | expected_miss, good_overcorrection |
| ca_img_002 | mixed | correct | `shift_frame_right, simplify_background` | `change_camera_angle, remove_background_hotspot, simplify_background` | — |
| ca_img_007 | mixed | correct | `add_front_fill_light` | `add_front_fill_light, keep_current_setup` | false_keep |
| ca_img_011 | good | correct | `keep_current_setup` | `add_front_fill_light, change_camera_angle, rotate_subject_toward_light, step_closer` | expected_miss, good_overcorrection |
| ca_img_013 | mixed | correct | `shift_frame_right, simplify_background` | `shift_frame_right, step_back` | — |
| ca_img_014 | mixed | keep | `simplify_background, wait_for_background_clearance` | `keep_current_setup` | expected_miss, false_keep |
| ca_img_019 | good | correct | `keep_current_setup` | `shift_frame_left, step_back` | expected_miss, good_overcorrection |
| ca_img_020 | good | correct | `keep_current_setup` | `change_camera_angle, remove_background_hotspot, simplify_background` | expected_miss, forbidden:simplify_background, good_overcorrection |
| ca_img_022 | mixed | correct | `add_front_fill_light` | `change_camera_angle, move_object_back` | expected_miss |
| ca_img_034 | good | correct | `keep_current_setup` | `shift_frame_down, shift_frame_up` | expected_miss, good_overcorrection |
| ca_img_035 | mixed | correct | `add_background_light, add_front_fill_light` | `add_front_fill_light, keep_current_setup` | false_keep |
| ca_img_036 | good | correct | `keep_current_setup` | `add_front_fill_light, keep_current_setup` | forbidden:add_front_fill_light, good_overcorrection |
| ca_img_044 | good | silence | `keep_current_setup` | `—` | expected_miss |
| ca_img_045 | good | silence | `keep_current_setup` | `—` | expected_miss |
| ca_img_050 | good | correct | `keep_current_setup` | `keep_current_setup, simplify_background` | good_overcorrection |
| ca_img_058 | bad | correct | `—` | `change_camera_angle, remove_background_hotspot, simplify_background, wait_for_background_clearance` | — |
| ca_img_059 | bad | keep | `—` | `keep_current_setup` | false_keep |
| ca_img_061 | bad | correct | `—` | `simplify_background` | — |
| ca_img_062 | bad | correct | `—` | `change_camera_angle, remove_background_hotspot, simplify_background` | — |
| ca_img_064 | bad | correct | `remove_background_hotspot` | `change_camera_angle, remove_background_hotspot, simplify_background, wait_for_background_clearance` | — |
| ca_img_065 | bad | correct | `change_camera_angle` | `change_camera_angle, remove_background_hotspot, simplify_background` | — |
| ca_img_067 | bad | keep | `simplify_background` | `keep_current_setup` | expected_miss, false_keep |
| ca_img_069 | bad | correct | `remove_background_hotspot` | `change_camera_angle, remove_background_hotspot, simplify_background, wait_for_background_clearance` | — |
| ca_img_070 | bad | correct | `—` | `shift_frame_right, step_back` | — |
| ca_img_071 | bad | correct | `—` | `simplify_background` | — |
| ca_img_072 | bad | correct | `change_camera_angle` | `change_camera_angle, remove_background_hotspot, simplify_background` | — |
| ca_img_073 | bad | correct | `remove_background_hotspot` | `change_camera_angle, remove_background_hotspot, simplify_background` | — |
| ca_img_074 | bad | keep | `level_horizon` | `keep_current_setup` | expected_miss, forbidden:keep_current_setup, false_keep |
| ca_img_075 | bad | correct | `change_camera_angle` | `change_camera_angle, remove_distracting_object, simplify_background, wait_for_background_clearance` | — |
| ca_img_076 | bad | correct | `wait_for_background_clearance` | `change_camera_angle, remove_background_hotspot, simplify_background, wait_for_background_clearance` | — |
| ca_img_077 | bad | keep | `simplify_background` | `keep_current_setup` | expected_miss, forbidden:keep_current_setup, false_keep |
| ca_img_078 | bad | correct | `—` | `change_camera_angle, move_object_back` | — |
| ca_img_080 | bad | correct | `remove_background_hotspot, step_closer` | `change_camera_angle, remove_background_hotspot, simplify_background, wait_for_background_clearance` | — |
| ca_img_081 | bad | keep | `—` | `keep_current_setup` | false_keep |
| ca_img_084 | bad | correct | `wait_for_background_clearance` | `change_camera_angle, remove_background_hotspot, simplify_background, wait_for_background_clearance` | — |
| ca_img_085 | bad | correct | `simplify_background, step_closer` | `change_camera_angle, move_object_back` | expected_miss |
| ca_img_087 | bad | correct | `remove_background_hotspot` | `change_camera_angle, remove_background_hotspot, simplify_background, wait_for_background_clearance` | — |
| ca_img_088 | bad | correct | `change_camera_angle` | `change_camera_angle, remove_background_hotspot` | — |
| ca_img_089 | bad | correct | `remove_background_hotspot` | `remove_distracting_object, shift_frame_left, wait_for_background_clearance` | expected_miss |
| ca_img_090 | bad | keep | `—` | `keep_current_setup` | forbidden:keep_current_setup, false_keep |
| ca_img_091 | bad | correct | `remove_background_hotspot` | `change_camera_angle, remove_background_hotspot, simplify_background` | — |
| ca_img_092 | bad | correct | `step_back` | `change_camera_angle, remove_background_hotspot, simplify_background` | expected_miss |
| ca_img_093 | bad | correct | `add_front_fill_light, step_closer` | `simplify_background` | expected_miss |
| ca_img_095 | mixed | silence | `step_back` | `—` | expected_miss |
| ca_img_096 | mixed | silence | `step_closer` | `—` | expected_miss |
| ca_img_097 | bad | keep | `simplify_background, wait_for_background_clearance` | `keep_current_setup` | expected_miss, forbidden:keep_current_setup, false_keep |
| ca_img_098 | bad | correct | `simplify_background` | `change_camera_angle, remove_background_hotspot, simplify_background, wait_for_background_clearance` | — |
| ca_img_099 | bad | correct | `remove_background_hotspot, simplify_background` | `change_camera_angle, remove_background_hotspot, simplify_background` | — |
| ca_img_100 | bad | correct | `—` | `simplify_background` | — |
| ca_img_101 | mixed | correct | `add_front_fill_light` | `add_front_fill_light, rotate_subject_toward_light` | — |
| ca_img_102 | bad | correct | `remove_background_hotspot` | `change_camera_angle, remove_background_hotspot, simplify_background, wait_for_background_clearance` | — |
| ca_img_103 | bad | correct | `—` | `shift_frame_down, shift_frame_up` | — |
| ca_img_104 | bad | keep | `simplify_background, wait_for_background_clearance` | `keep_current_setup` | expected_miss, forbidden:keep_current_setup, false_keep |
| ca_img_106 | bad | correct | `remove_background_hotspot` | `change_camera_angle, remove_background_hotspot, simplify_background` | — |
| ca_img_107 | bad | correct | `simplify_background, wait_for_background_clearance` | `keep_current_setup, simplify_background` | forbidden:keep_current_setup, false_keep |
| ca_img_123 | good | correct | `keep_current_setup` | `change_camera_angle, remove_background_hotspot, simplify_background` | expected_miss, forbidden:change_camera_angle,remove_background_hotspot,simplify_background, good_overcorrection |
| ca_img_128 | good | correct | `keep_current_setup` | `add_front_fill_light, change_camera_angle, rotate_subject_toward_light, step_closer` | expected_miss, forbidden:add_front_fill_light,change_camera_angle,step_closer, good_overcorrection |
| ca_img_130 | good | correct | `keep_current_setup` | `change_camera_angle, remove_background_hotspot, simplify_background` | expected_miss, forbidden:change_camera_angle,remove_background_hotspot,simplify_background, good_overcorrection |
| ca_img_138 | good | correct | `keep_current_setup` | `simplify_background` | expected_miss, forbidden:simplify_background, good_overcorrection |
| ca_img_145 | good | correct | `keep_current_setup` | `change_camera_angle, remove_background_hotspot, simplify_background, wait_for_background_clearance` | expected_miss, forbidden:change_camera_angle,remove_background_hotspot,simplify_background,wait_for_background_clearance, good_overcorrection |
| ca_img_150 | good | silence | `keep_current_setup` | `—` | expected_miss |
| ca_img_156 | good | correct | `keep_current_setup` | `simplify_background` | expected_miss, forbidden:simplify_background, good_overcorrection |
| ca_img_208 | bad | correct | `remove_distracting_object, simplify_background, step_closer` | `change_camera_angle, move_object_back` | expected_miss |
| ca_img_209 | bad | silence | `remove_distracting_object, shift_frame_left, step_back` | `—` | expected_miss |
| ca_img_210 | bad | keep | `add_front_fill_light, change_camera_angle, remove_background_hotspot` | `keep_current_setup` | expected_miss, forbidden:keep_current_setup, false_keep |
| ca_img_211 | bad | silence | `add_front_fill_light, rotate_subject_toward_light` | `—` | expected_miss |
| ca_img_212 | bad | keep | `simplify_background, step_closer` | `keep_current_setup` | expected_miss, forbidden:keep_current_setup, false_keep |
| ca_img_213 | bad | silence | `remove_distracting_object, shift_frame_right, step_back` | `—` | expected_miss |
| ca_img_214 | bad | correct | `remove_distracting_object, simplify_background, wait_for_background_clearance` | `change_camera_angle, move_object_back, simplify_background` | — |
| ca_img_215 | bad | correct | `shift_frame_down, step_back` | `remove_distracting_object, shift_frame_right, step_back` | — |
| ca_img_216 | bad | keep | `remove_distracting_object, shift_frame_left, step_back` | `keep_current_setup` | expected_miss, forbidden:keep_current_setup, false_keep |
| ca_img_217 | bad | silence | `add_front_fill_light, change_camera_angle, remove_background_hotspot` | `—` | expected_miss |
| ca_img_218 | bad | silence | `add_front_fill_light, rotate_subject_toward_light` | `—` | expected_miss |
| ca_img_219 | bad | correct | `remove_distracting_object, simplify_background` | `shift_frame_down, shift_frame_up` | expected_miss |
| ca_img_220 | bad | keep | `shift_frame_down, step_closer` | `keep_current_setup` | expected_miss, forbidden:keep_current_setup, false_keep |
| ca_img_221 | bad | keep | `remove_distracting_object, shift_frame_left, wait_for_background_clearance` | `keep_current_setup` | expected_miss, forbidden:keep_current_setup, false_keep |
| ca_img_222 | bad | correct | `remove_distracting_object, simplify_background, step_back` | `add_front_fill_light, rotate_subject_toward_light, simplify_background` | — |
| ca_img_223 | bad | correct | `change_camera_angle, remove_background_hotspot` | `add_front_fill_light, change_camera_angle, remove_background_hotspot` | — |
| ca_img_224 | bad | silence | `add_front_fill_light, rotate_subject_toward_light` | `—` | expected_miss |
| ca_img_225 | bad | correct | `shift_frame_right, step_back` | `change_camera_angle, remove_background_hotspot, simplify_background` | expected_miss |
| ca_img_226 | bad | correct | `remove_distracting_object, shift_frame_left, step_back` | `simplify_background` | expected_miss |
| ca_img_227 | bad | keep | `remove_distracting_object, simplify_background` | `keep_current_setup` | expected_miss, forbidden:keep_current_setup, false_keep |
| ca_img_228 | bad | silence | `step_closer` | `—` | expected_miss |
| ca_img_229 | bad | silence | `add_front_fill_light, change_camera_angle, remove_background_hotspot` | `—` | expected_miss |
| ca_img_230 | bad | keep | `shift_frame_down, step_back` | `keep_current_setup` | expected_miss, forbidden:keep_current_setup, false_keep |
| ca_img_231 | bad | keep | `remove_distracting_object, wait_for_background_clearance` | `keep_current_setup` | expected_miss, forbidden:keep_current_setup, false_keep |
| ca_img_232 | bad | silence | `remove_distracting_object, simplify_background` | `—` | expected_miss |
| ca_img_233 | bad | keep | `add_front_fill_light, rotate_subject_toward_light` | `keep_current_setup` | expected_miss, forbidden:keep_current_setup, false_keep |
| ca_img_234 | bad | silence | `change_camera_angle, remove_background_hotspot` | `—` | expected_miss |
| ca_img_235 | bad | silence | `shift_frame_right, step_back` | `—` | expected_miss |
| ca_img_236 | bad | correct | `step_closer` | `shift_frame_down, shift_frame_up` | expected_miss |
| ca_img_237 | bad | silence | `remove_distracting_object, simplify_background` | `—` | expected_miss |
| ca_img_238 | bad | keep | `add_front_fill_light, rotate_subject_toward_light` | `keep_current_setup` | expected_miss, forbidden:keep_current_setup, false_keep |
| ca_img_239 | bad | correct | `change_camera_angle, remove_background_hotspot` | `change_camera_angle, remove_background_hotspot, simplify_background` | — |
