# M0-007 size summary + provisional dispositions

Membership mechanism: Xcode 16+ PBXFileSystemSynchronizedRootGroup (automatic by folder).
App-target exceptions (NOT in app bundle): Info.plist, Resources/Circle.rcproject,
Resources/DeviceBenchmark, Resources/Fixtures, Resources/Models, Resources/Textures.

| Artifact | Size | Membership | Provisional disposition |
|---|---|---|---|
| Resources/Models/dataset_v9_event_sft_q4_k_m.gguf | 1,107,408,576 | EXCLUDED (app) | REMOVE_AFTER_VERIFIED_REPLACEMENT; never in Release |
| Resources/DeviceBenchmark/* | ~15.7 MB jsonl | EXCLUDED (app); Debug-only copy script | research/eval only |
| Resources/Fixtures/* (+146 jpg/20 bmp) | ~1.7 MB + camera frame | EXCLUDED (app) | test/fixture only |
| Resources/Textures/* | TBD | EXCLUDED (app) | verify texture loading path (bundle vs generated) |
| DETR .mlpackage | 337 KB model | in Models/CoreML (NOT under excluded Resources/Models) → bundled | REMOVE_AFTER_VERIFIED_REPLACEMENT |
| NIMA .mlpackage | 82 KB model | bundled (same) | REMOVE_AFTER_VERIFIED_REPLACEMENT |
| llama.xcframework | Frameworks/ | linked+embedded (10 pbxproj refs) | REMOVE_AFTER_VERIFIED_REPLACEMENT (Scene only) |
| Fonts (5 ttf + 5 OFL) | ~1 MB | bundled (Resources/Fonts not excluded) | KEEP; hash-gate in M8 |
| Circle.usdz 60 KB / Person.usdz 413 KB | bundled (Resources/ root) | KEEP pending rights evidence (M12) |
| Localizable.xcstrings 160 KB / InfoPlist.xcstrings 2 KB | bundled | KEEP |
| PrivacyInfo.xcprivacy 816 B | bundled (root) | KEEP; content audit in M12 |
| SnapKit 5.7.1 (CocoaPods) | linked | KEEP pending license disposition |
| Assets.xcassets background.png 1.9 MB | bundled | verify motif-budget compliance (M8) |

Total inventoried: 227 items / 1,166,852,040 bytes (dominated by excluded GGUF).
