# Regenerated bad buckets v1

Created: 2026-06-05

Base label set: `semantic_labels_v2_minus15_appletv_good_minus8_subtle_bad_minus10_weak_synthetic.jsonl`
New label set: `semantic_labels_v2_minus15_appletv_good_minus8_subtle_bad_minus10_weak_synthetic_regen_bad_v1.jsonl`

## Replacement Summary

- Removed old `imagegen_bad_candidate`: 15 records
- Removed old `synthetic_bad_paired_apple_tv_press`: 17 records
- Added regenerated `imagegen_bad_candidate`: 15 records (`ca_img_208...ca_img_222`)
- Added regenerated `synthetic_bad_paired_apple_tv_press`: 17 records (`ca_img_223...ca_img_239`)
- Total record count preserved: 174 -> 174

## Rationale

The previous bad buckets mixed obvious defects with stylized cinematic frames and subtle synthetic artifacts. This replacement set keeps only visually explicit anti-examples: hard foreground obstruction, severe crop/edge cutoff, strong hotspot/backlight, strong underexposure, tiny subject, and heavy clutter.

## QA Contact Sheets

- `qa/regen_bad_v1_imagegen_contact_sheet.jpg`
- `qa/regen_bad_v1_synthetic_contact_sheet.jpg`

## Replaced Old Records

- `ca_img_158` `158.jpg` bucket=`imagegen_bad_candidate` expected=['simplify_background', 'remove_distracting_object', 'step_closer']
- `ca_img_159` `159.jpg` bucket=`imagegen_bad_candidate` expected=['wait_for_background_clearance', 'shift_frame_left', 'step_back']
- `ca_img_160` `160.jpg` bucket=`imagegen_bad_candidate` expected=['remove_background_hotspot', 'change_camera_angle', 'add_front_fill_light']
- `ca_img_161` `161.jpg` bucket=`imagegen_bad_candidate` expected=['simplify_background', 'wait_for_background_clearance', 'remove_distracting_object']
- `ca_img_163` `163.jpg` bucket=`imagegen_bad_candidate` expected=['remove_distracting_object', 'step_back', 'shift_frame_up']
- `ca_img_164` `164.jpg` bucket=`imagegen_bad_candidate` expected=['step_back', 'shift_frame_left', 'remove_background_hotspot']
- `ca_img_165` `165.jpg` bucket=`imagegen_bad_candidate` expected=['step_closer', 'simplify_background']
- `ca_img_166` `166.jpg` bucket=`imagegen_bad_candidate` expected=['remove_background_hotspot', 'change_camera_angle', 'step_closer']
- `ca_img_168` `168.jpg` bucket=`imagegen_bad_candidate` expected=['step_back', 'change_camera_angle', 'shift_frame_down']
- `ca_img_169` `169.jpg` bucket=`imagegen_bad_candidate` expected=['add_front_fill_light', 'change_camera_angle', 'remove_distracting_object']
- `ca_img_170` `170.jpg` bucket=`imagegen_bad_candidate` expected=['remove_distracting_object', 'shift_frame_left', 'step_closer']
- `ca_img_173` `173.jpg` bucket=`imagegen_bad_candidate` expected=['remove_distracting_object', 'shift_frame_right', 'step_back']
- `ca_img_174` `174.jpg` bucket=`imagegen_bad_candidate` expected=['add_front_fill_light', 'rotate_subject_toward_light', 'change_camera_angle']
- `ca_img_175` `175.jpg` bucket=`imagegen_bad_candidate` expected=['remove_background_hotspot', 'step_closer', 'change_camera_angle']
- `ca_img_176` `176.jpg` bucket=`imagegen_bad_candidate` expected=['wait_for_background_clearance', 'simplify_background', 'shift_frame_left']
- `ca_img_179` `179.jpg` bucket=`synthetic_bad_paired_apple_tv_press` expected=['remove_background_hotspot', 'change_camera_angle']
- `ca_img_180` `180.jpg` bucket=`synthetic_bad_paired_apple_tv_press` expected=['add_front_fill_light', 'rotate_subject_toward_light']
- `ca_img_182` `182.jpg` bucket=`synthetic_bad_paired_apple_tv_press` expected=['step_closer']
- `ca_img_183` `183.jpg` bucket=`synthetic_bad_paired_apple_tv_press` expected=['simplify_background', 'remove_distracting_object']
- `ca_img_184` `184.jpg` bucket=`synthetic_bad_paired_apple_tv_press` expected=['step_back', 'shift_frame_right']
- `ca_img_187` `187.jpg` bucket=`synthetic_bad_paired_apple_tv_press` expected=['remove_background_hotspot', 'change_camera_angle']
- `ca_img_188` `188.jpg` bucket=`synthetic_bad_paired_apple_tv_press` expected=['add_front_fill_light', 'rotate_subject_toward_light']
- `ca_img_189` `189.jpg` bucket=`synthetic_bad_paired_apple_tv_press` expected=[]
- `ca_img_190` `190.jpg` bucket=`synthetic_bad_paired_apple_tv_press` expected=['step_closer']
- `ca_img_191` `191.jpg` bucket=`synthetic_bad_paired_apple_tv_press` expected=['simplify_background', 'remove_distracting_object']
- `ca_img_192` `192.jpg` bucket=`synthetic_bad_paired_apple_tv_press` expected=['step_back', 'shift_frame_right']
- `ca_img_195` `195.jpg` bucket=`synthetic_bad_paired_apple_tv_press` expected=['remove_background_hotspot', 'change_camera_angle']
- `ca_img_196` `196.jpg` bucket=`synthetic_bad_paired_apple_tv_press` expected=['add_front_fill_light', 'rotate_subject_toward_light']
- `ca_img_197` `197.jpg` bucket=`synthetic_bad_paired_apple_tv_press` expected=[]
- `ca_img_198` `198.jpg` bucket=`synthetic_bad_paired_apple_tv_press` expected=['step_closer']
- `ca_img_199` `199.jpg` bucket=`synthetic_bad_paired_apple_tv_press` expected=['simplify_background', 'remove_distracting_object']
- `ca_img_207` `207.jpg` bucket=`synthetic_bad_paired_apple_tv_press` expected=['simplify_background', 'remove_distracting_object']
