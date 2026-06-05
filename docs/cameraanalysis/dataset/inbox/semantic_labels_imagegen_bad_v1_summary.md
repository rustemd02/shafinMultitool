# Imagegen Bad Labels v1

Status: AI-generated synthetic anti-example stress set for Camera Analysis semantic coaching.
Created: 2026-06-04.

This label set covers `158...177` and is intentionally separate from `semantic_labels_v1.jsonl` so the original 107-record silver set remains stable.

## Design Intent

- Each image combines multiple visible problems: bad framing, edge cutoff, obstruction, clutter, empty space, hotspot or backlight.
- The set is deliberately not a beauty benchmark; it is a demo stress set for explanations and actionable semantic tips.
- Labels are synthetic first-pass labels and require human review before being treated as gold data.

## Files

- `imagegen_bad_sources_158_177.jsonl` — provenance, parent frame and postprocess metadata.
- `semantic_labels_imagegen_bad_v1.jsonl` — eval labels using the semantic action vocabulary.
- `qa/contact_sheet_158_177_imagegen_bad.jpg` — visual QA contact sheet.

## Case Mix

- `158.jpg`: imagegen_bad, clutter, foreground_obstruction, bad_crop; expected `simplify_background, remove_distracting_object, step_closer`.
- `159.jpg`: imagegen_bad, occlusion, edge_cutoff, glare; expected `wait_for_background_clearance, shift_frame_left, step_back`.
- `160.jpg`: imagegen_bad, hotspot, backlight, underexposure; expected `remove_background_hotspot, change_camera_angle, add_front_fill_light`.
- `161.jpg`: imagegen_bad, crowd, clutter, tilt; expected `simplify_background, wait_for_background_clearance, remove_distracting_object`.
- `162.jpg`: imagegen_bad, backlight, underexposure, bad_crop; expected `add_front_fill_light, rotate_subject_toward_light, change_camera_angle`.
- `163.jpg`: imagegen_bad, foreground_obstruction, headroom, edge_cutoff; expected `remove_distracting_object, step_back, shift_frame_up`.
- `164.jpg`: imagegen_bad, edge_cutoff, hotspot, foreground_obstruction; expected `step_back, shift_frame_left, remove_background_hotspot`.
- `165.jpg`: imagegen_bad, subject_too_small, empty_space, foreground_obstruction; expected `step_closer, simplify_background`.
- `166.jpg`: imagegen_bad, hotspot, low_readability, empty_space; expected `remove_background_hotspot, change_camera_angle, step_closer`.
- `167.jpg`: imagegen_bad, background_competition, clutter, edge_pressure; expected `simplify_background, move_subject_away_from_background, shift_frame_right`.
- `168.jpg`: imagegen_bad, foreground_bars, headroom, edge_cutoff; expected `step_back, change_camera_angle, shift_frame_down`.
- `169.jpg`: imagegen_bad, backlight, occlusion, branches; expected `add_front_fill_light, change_camera_angle, remove_distracting_object`.
- `170.jpg`: imagegen_bad, occlusion, foreground_obstruction, clutter; expected `remove_distracting_object, shift_frame_left, step_closer`.
- `171.jpg`: imagegen_bad, clutter, bad_headroom, foreground_obstruction; expected `simplify_background, remove_distracting_object, step_back`.
- `172.jpg`: imagegen_bad, subject_too_small, crowd, edge_cutoff; expected `step_closer, simplify_background, wait_for_background_clearance`.
- `173.jpg`: imagegen_bad, occlusion, text_like_graphic, tilt; expected `remove_distracting_object, shift_frame_right, step_back`.
- `174.jpg`: imagegen_bad, backlight, edge_cutoff, underexposure; expected `add_front_fill_light, rotate_subject_toward_light, change_camera_angle`.
- `175.jpg`: imagegen_bad, hotspot, edge_cutoff, empty_space; expected `remove_background_hotspot, step_closer, change_camera_angle`.
- `176.jpg`: imagegen_bad, crowd, empty_space, edge_cutoff; expected `wait_for_background_clearance, simplify_background, shift_frame_left`.
- `177.jpg`: imagegen_bad, edge_cutoff, empty_space, portrait; expected `shift_frame_right, step_back, move_subject_left`.
