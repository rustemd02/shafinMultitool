#!/bin/bash

set -euo pipefail
IFS=$'\n\t'

SCRIPT_PATH="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/$(basename -- "${BASH_SOURCE[0]}")"
TEMP_ROOT=""

APP_ROOT=""
SOURCE_MANIFEST=""
REPO_ROOT=""
PRIVACY_VALIDATOR=""
COMPONENT_STATUS_VALIDATOR=""
COMPONENT_STATUS_RECORD=""

DETR_MODEL_ROOT="DETRResnet50SemanticSegmentationF16P8.mlmodelc"
NIMA_MODEL_ROOT="aesthetic_nima_mobilenet_fp16.mlmodelc"
KNOWN_BLOCKER_COUNT=""
ASSETUTIL_BIN=""

usage() {
    cat <<'EOF'
Usage:
  scripts/validate_release_bundle.sh \
    --repo-root /absolute/repository/root \
    --source-manifest /absolute/repository/root/shafinMultitool/PrivacyInfo.xcprivacy \
    --app /absolute/path/to/shafinMultitool.app

Validation-only mode inspects the supplied app without changing it. The app,
source manifest, and repository root must be explicit absolute paths.
EOF
}

fail() {
    printf 'FAIL: stage=bundle-validation reason=%s\n' "$*" >&2
    exit 1
}

cleanup() {
    if [ -n "${TEMP_ROOT:-}" ] && [ -d "$TEMP_ROOT" ]; then
        rm -rf "$TEMP_ROOT"
    fi
}

trap cleanup EXIT HUP INT TERM

require_absolute_path() {
    local label="$1"
    local value="$2"

    if [ -z "$value" ]; then
        fail "$label path is empty"
    fi
    case "$value" in
        /*)
            ;;
        *)
            fail "$label path must be absolute: $value"
            ;;
    esac
    case "$value" in
        */../*|../*|*/..|..)
            fail "$label path must not contain parent traversal: $value"
            ;;
    esac
}

require_directory() {
    local label="$1"
    local path="$2"

    if [ ! -d "$path" ] || [ -L "$path" ]; then
        fail "$label directory is missing or is a symlink: $path"
    fi
}

require_file() {
    local label="$1"
    local path="$2"

    if [ ! -f "$path" ] || [ -L "$path" ]; then
        fail "$label file is missing or is a symlink: $path"
    fi
}

require_nonempty_plist_value() {
    local key="$1"
    local value

    if ! value="$(plutil -extract "$key" raw -o - -- "$APP_ROOT/Info.plist" 2>/dev/null)"; then
        fail "$key is empty or missing in built Info.plist"
    fi
    if [ -z "${value//[[:space:]]/}" ]; then
        fail "$key is empty or missing in built Info.plist"
    fi
    printf 'PASS bundle metadata: %s=%s\n' "$key" "$value"
}

validate_app_metadata() {
    local scene_class
    local font_xml="$TEMP_ROOT/uiappfonts.xml"
    local font
    local font_count=0
    local locale
    local asset_info="$TEMP_ROOT/assets.car.json"

    printf 'STAGE 5: bundle metadata, fonts, localizations, and app icon\n'
    require_nonempty_plist_value CFBundleIdentifier
    require_nonempty_plist_value CFBundleShortVersionString
    require_nonempty_plist_value CFBundleVersion
    require_nonempty_plist_value CFBundleDisplayName

    if ! scene_class="$(plutil -extract 'UIApplicationSceneManifest.UISceneConfigurations.UIWindowSceneSessionRoleApplication.0.UISceneClassName' raw -o - -- "$APP_ROOT/Info.plist" 2>/dev/null)"; then
        fail "UISceneClassName must be UIWindowScene (missing)"
    fi
    if [ "$scene_class" != "UIWindowScene" ]; then
        fail "UISceneClassName must be UIWindowScene (found '$scene_class')"
    fi
    printf 'PASS bundle metadata: UISceneClassName=UIWindowScene\n'

    if ! plutil -extract UIAppFonts xml1 -o "$font_xml" -- "$APP_ROOT/Info.plist" 2>/dev/null; then
        fail "UIAppFonts is empty or missing in built Info.plist"
    fi
    while IFS= read -r font; do
        [ -n "$font" ] || continue
        font_count=$((font_count + 1))
        case "$font" in
            */*|..|../*|*/../*)
                fail "declared UIAppFonts entry is not an app-root filename: $font"
                ;;
        esac
        require_file "declared UIAppFonts entry '$font'" "$APP_ROOT/$font"
    done < <(sed -n 's/^[[:space:]]*<string>\(.*\)<\/string>[[:space:]]*$/\1/p' "$font_xml")
    if [ "$font_count" -eq 0 ]; then
        fail "UIAppFonts is empty or missing in built Info.plist"
    fi
    printf 'PASS UIAppFonts: %s declared root font file(s) present\n' "$font_count"

    for locale in en ru; do
        require_file "${locale}.lproj/InfoPlist.strings" "$APP_ROOT/${locale}.lproj/InfoPlist.strings"
        require_file "${locale}.lproj/Localizable.strings" "$APP_ROOT/${locale}.lproj/Localizable.strings"
    done
    printf 'PASS localized resources: en/ru InfoPlist.strings and Localizable.strings present\n'

    if [ -n "${ASSETUTIL_BIN_OVERRIDE:-}" ]; then
        ASSETUTIL_BIN="$ASSETUTIL_BIN_OVERRIDE"
    else
        ASSETUTIL_BIN="$(xcrun --find assetutil 2>/dev/null || true)"
    fi
    if [ -z "$ASSETUTIL_BIN" ] || [ ! -x "$ASSETUTIL_BIN" ]; then
        fail "assetutil is unavailable; cannot inspect Assets.car for AppIcon"
    fi
    if ! "$ASSETUTIL_BIN" --info "$APP_ROOT/Assets.car" > "$asset_info" 2> "$TEMP_ROOT/assetutil.stderr"; then
        fail "assetutil could not inspect Assets.car"
    fi
    if ! grep -Eq '"Name"[[:space:]]*:[[:space:]]*"AppIcon"([,}]|$)' "$asset_info"; then
        fail "Assets.car does not contain asset Name AppIcon"
    fi
    printf 'PASS asset catalog: Assets.car contains asset Name AppIcon\n'
}

is_allowed_model_path() {
    local relative_path="$1"

    case "$relative_path" in
        "$DETR_MODEL_ROOT"|"$DETR_MODEL_ROOT"/*|"$NIMA_MODEL_ROOT"|"$NIMA_MODEL_ROOT"/*)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

validate_framework_allowlist() {
    local framework_dir="$APP_ROOT/Frameworks"
    local inventory="$TEMP_ROOT/frameworks.list"
    local entry
    local relative_path
    local framework_count=0
    local snapkit_found=0
    local llama_found=0

    require_directory "Frameworks" "$framework_dir"
    if ! find "$framework_dir" -mindepth 1 -maxdepth 1 -print0 > "$inventory"; then
        fail "could not enumerate direct Frameworks entries"
    fi

    while IFS= read -r -d '' entry; do
        framework_count=$((framework_count + 1))
        relative_path="${entry#"$APP_ROOT/"}"
        case "$relative_path" in
            Frameworks/SnapKit.framework)
                require_directory "SnapKit framework" "$entry"
                snapkit_found=1
                ;;
            Frameworks/llama.framework)
                require_directory "llama framework" "$entry"
                llama_found=1
                ;;
            *)
                fail "unexpected framework entry '$relative_path' (framework allowlist is SnapKit.framework, llama.framework)"
                ;;
        esac
    done < "$inventory"

    if [ "$framework_count" -ne 2 ] || [ "$snapkit_found" -ne 1 ] || [ "$llama_found" -ne 1 ]; then
        fail "framework allowlist mismatch: expected exactly SnapKit.framework and llama.framework"
    fi

    require_file "SnapKit framework binary" "$framework_dir/SnapKit.framework/SnapKit"
    require_file "SnapKit nested privacy manifest" "$framework_dir/SnapKit.framework/SnapKit_Privacy.bundle/PrivacyInfo.xcprivacy"
    require_file "llama framework binary" "$framework_dir/llama.framework/llama"
    printf 'PASS framework allowlist: SnapKit.framework and llama.framework only\n'
}

validate_required_structure() {
    local executable_name
    local required_file
    local required_dir

    require_directory "Release app" "$APP_ROOT"
    case "$(basename -- "$APP_ROOT")" in
        shafinMultitool.app)
            ;;
        *)
            fail "supplied app must be named shafinMultitool.app: $APP_ROOT"
            ;;
    esac

    require_file "Info.plist" "$APP_ROOT/Info.plist"
    require_file "Assets.car" "$APP_ROOT/Assets.car"
    require_file "root PrivacyInfo.xcprivacy" "$APP_ROOT/PrivacyInfo.xcprivacy"
    require_file "Circle.usdz" "$APP_ROOT/Circle.usdz"
    require_file "Person.usdz" "$APP_ROOT/Person.usdz"
    require_directory "DETR compiled model root" "$APP_ROOT/$DETR_MODEL_ROOT"
    require_directory "NIMA compiled model root" "$APP_ROOT/$NIMA_MODEL_ROOT"

    if ! executable_name="$(plutil -extract CFBundleExecutable raw -o - -- "$APP_ROOT/Info.plist" 2>/dev/null)"; then
        fail "Info.plist does not expose CFBundleExecutable"
    fi
    case "$executable_name" in
        ""|*/*)
            fail "CFBundleExecutable is not a simple app-root filename: $executable_name"
            ;;
    esac
    require_file "app executable" "$APP_ROOT/$executable_name"
    if [ ! -x "$APP_ROOT/$executable_name" ]; then
        fail "app executable is not executable: $executable_name"
    fi

    for required_file in \
        "Frameworks/SnapKit.framework/SnapKit" \
        "Frameworks/SnapKit.framework/SnapKit_Privacy.bundle/PrivacyInfo.xcprivacy" \
        "Frameworks/llama.framework/llama"; do
        require_file "required bundle path $required_file" "$APP_ROOT/$required_file"
    done

    for required_dir in \
        "$DETR_MODEL_ROOT" \
        "$NIMA_MODEL_ROOT"; do
        require_directory "required bundle path $required_dir" "$APP_ROOT/$required_dir"
    done

    validate_framework_allowlist
    printf 'PASS required bundle structure: executable, Info.plist, Assets.car, privacy root, models, frameworks, Circle.usdz, Person.usdz\n'
}

validate_forbidden_and_family_paths() {
    local inventory="$TEMP_ROOT/app-paths.list"
    local entry
    local relative_path
    local lower_path

    if ! find "$APP_ROOT" -print0 > "$inventory"; then
        fail "could not enumerate app bundle paths"
    fi

    while IFS= read -r -d '' entry; do
        [ "$entry" = "$APP_ROOT" ] && continue
        case "$entry" in
            "$APP_ROOT"/*)
                relative_path="${entry#"$APP_ROOT/"}"
                ;;
            *)
                fail "bundle path escaped supplied app: $entry"
                ;;
        esac
        lower_path="$(printf '%s' "$relative_path" | tr '[:upper:]' '[:lower:]')"

        case "/$lower_path/" in
            */devicebenchmark/*)
                fail "forbidden DeviceBenchmark path component: $relative_path"
                ;;
        esac

        case "$lower_path" in
            *.gguf|*.gguf/*)
                fail "forbidden .gguf payload: $relative_path"
                ;;
            *.mlpackage|*.mlpackage/*|*.mlmodel|*.mlmodel/*)
                fail "forbidden raw Core ML source payload: $relative_path"
                ;;
            *.rcproject|*.rcproject/*)
                fail "forbidden .rcproject payload: $relative_path"
                ;;
            *debugresourceconfig.plist)
                fail "forbidden DebugResourceConfig.plist: $relative_path"
                ;;
            *arvideokit*)
                fail "forbidden ARVideoKit path: $relative_path"
                ;;
            *benchmark*)
                fail "forbidden benchmark payload path: $relative_path"
                ;;
        esac

        case "$lower_path" in
            *.mlmodelc|*.mlmodelc/*)
                if ! is_allowed_model_path "$relative_path"; then
                    fail "unknown compiled model root: $relative_path"
                fi
                ;;
            *.usdz)
                case "$relative_path" in
                    Circle.usdz|Person.usdz)
                        ;;
                    *)
                        fail "unknown USDZ media payload: $relative_path"
                        ;;
                esac
                ;;
        esac

        if ! is_allowed_model_path "$relative_path"; then
            case "$lower_path" in
                *model*|*weights*|*gguf*)
                    fail "unknown model-like payload: $relative_path"
                    ;;
            esac
        fi

        if ! is_allowed_model_path "$relative_path"; then
            case "$lower_path" in
                *.jsonl|*manifest*.json|*manifest*.plist|*.json)
                    fail "forbidden benchmark manifest or JSON payload: $relative_path"
                    ;;
                *.png|*.jpg|*.jpeg|*.heic|*.webp|*.gif|*.bmp|*.tif|*.tiff)
                    case "$relative_path" in
                        AppIcon60x60@2x.png|AppIcon76x76@2x~ipad.png)
                            ;;
                        *)
                            fail "forbidden benchmark image or unknown image payload: $relative_path"
                            ;;
                    esac
                    ;;
            esac
        fi

        if [ -f "$entry" ] && [ ! -L "$entry" ]; then
            if LC_ALL=C grep -a -F -i -q 'ARVideoKit' "$entry" 2>/dev/null; then
                fail "forbidden ARVideoKit binary or acknowledgement text: $relative_path"
            fi
        fi
    done < "$inventory"

    if find "$APP_ROOT" -type d -iname Models -print -quit | grep -q .; then
        fail "forbidden Models directory in bundle"
    fi

    printf 'PASS forbidden payload scan: no GGUF, DeviceBenchmark, Models, ARVideoKit, raw Core ML, benchmark data, or unknown model/media family\n'
}

validate_privacy() {
    local privacy_log="$TEMP_ROOT/privacy-validator.log"

    printf 'STAGE 6: privacy manifest validation\n'
    if ! "$PRIVACY_VALIDATOR" --source-manifest "$SOURCE_MANIFEST" --app "$APP_ROOT" > "$privacy_log" 2>&1; then
        cat "$privacy_log" >&2
        fail "privacy validator rejected source or built app; see $privacy_log"
    fi
    cat "$privacy_log"
    printf 'PASS privacy manifest validation delegated to validate_privacy_manifest.sh\n'
}

validate_acknowledgements() {
    local acknowledgement_markdown="$REPO_ROOT/Pods/Target Support Files/Pods-shafinMultitool/Pods-shafinMultitool-acknowledgements.markdown"
    local acknowledgement_plist="$REPO_ROOT/Pods/Target Support Files/Pods-shafinMultitool/Pods-shafinMultitool-acknowledgements.plist"

    printf 'STAGE 8: CocoaPods acknowledgements\n'
    require_file "app-target CocoaPods acknowledgement markdown" "$acknowledgement_markdown"
    require_file "app-target CocoaPods acknowledgement plist" "$acknowledgement_plist"
    if ! plutil -lint -- "$acknowledgement_plist" >/dev/null 2>&1; then
        fail "app-target CocoaPods acknowledgement plist does not plutil-lint"
    fi
    if ! grep -Fq 'SnapKit' "$acknowledgement_markdown" || ! grep -Fq 'SnapKit' "$acknowledgement_plist"; then
        fail "app-target CocoaPods acknowledgement source is missing SnapKit"
    fi
    if grep -F -i -q 'ARVideoKit' "$acknowledgement_markdown" || grep -F -i -q 'ARVideoKit' "$acknowledgement_plist"; then
        fail "app-target CocoaPods acknowledgement source contains forbidden ARVideoKit"
    fi

    if ! python3 "$COMPONENT_STATUS_VALIDATOR" --repo-root "$REPO_ROOT" --snapkit-only --app "$APP_ROOT"; then
        fail "SnapKit source provenance or exact bundled MIT copyright/license notice failed"
    fi
    printf 'ACK_BUILT_SURFACE: SnapKit-LICENSE.txt; exact upstream MIT notice verified\n'
    printf 'ACK_SOURCE: %s\n' "$acknowledgement_markdown"
    printf 'ACK_SCOPE: CocoaPods acknowledgement assertion covers SnapKit only; llama/CoreML/media provenance is not treated as CocoaPods coverage\n'
    printf 'PASS CocoaPods acknowledgements: exact SnapKit MIT notice bundled, ARVideoKit absent\n'
}

validate_component_status() {
    local status_log="$TEMP_ROOT/component-status.log"
    local validator_status

    printf 'STAGE 9: machine-readable component disposition\n'
    set +e
    python3 "$COMPONENT_STATUS_VALIDATOR" \
        --repo-root "$REPO_ROOT" \
        --record "$COMPONENT_STATUS_RECORD" \
        --app "$APP_ROOT" > "$status_log" 2>&1
    validator_status=$?
    set -e
    cat "$status_log"

    if [ "$(grep -Ec '^KNOWN_BLOCKER_COUNT=[0-9]+$' "$status_log" || true)" -ne 1 ]; then
        fail "component status validator failed without a stable KNOWN_BLOCKER_COUNT metric"
    fi
    KNOWN_BLOCKER_COUNT="$(sed -n 's/^KNOWN_BLOCKER_COUNT=\([0-9][0-9]*\)$/\1/p' "$status_log")"
    if [ "$(grep -Ec '^KNOWN_BLOCKER: ' "$status_log" || true)" -ne "$KNOWN_BLOCKER_COUNT" ]; then
        fail "component status validator blocker rows do not match KNOWN_BLOCKER_COUNT"
    fi
    if [ "$validator_status" -eq 0 ] && [ "$KNOWN_BLOCKER_COUNT" -ne 0 ]; then
        fail "component status validator exited zero with nonzero blocker count"
    fi
    if [ "$validator_status" -ne 0 ] && [ "$KNOWN_BLOCKER_COUNT" -eq 0 ]; then
        fail "component status validator failed without reporting a blocker"
    fi
    printf 'PASS component disposition schema: known_blockers=%s\n' "$KNOWN_BLOCKER_COUNT"
}

report_material_sizes() {
    local material_list="$TEMP_ROOT/material-contributors.tsv"
    local sorted_material_list="$TEMP_ROOT/material-contributors-sorted.tsv"
    local entry
    local relative_path
    local size_kib
    local total_app_kib
    local material_count=0

    printf 'STAGE 10: bundle size contributors\n'
    : > "$material_list"
    if ! find "$APP_ROOT" -type f -print0 > "$TEMP_ROOT/files.list"; then
        fail "could not enumerate files for material size report"
    fi
    while IFS= read -r -d '' entry; do
        size_kib="$(du -k "$entry" | awk 'NR == 1 { print $1 }')"
        if [ "$size_kib" -ge 1024 ]; then
            relative_path="${entry#"$APP_ROOT/"}"
            printf '%s\t%s\n' "$size_kib" "$relative_path" >> "$material_list"
        fi
    done < "$TEMP_ROOT/files.list"
    if ! LC_ALL=C sort -t $'\t' -k2,2 -k1,1n "$material_list" > "$sorted_material_list"; then
        fail "could not sort material size report"
    fi
    while IFS=$'\t' read -r size_kib relative_path; do
        [ -n "$relative_path" ] || continue
        material_count=$((material_count + 1))
        printf 'MATERIAL_CONTRIBUTOR: KiB=%s path=%s\n' "$size_kib" "$relative_path"
    done < "$sorted_material_list"

    total_app_kib="$(du -sk "$APP_ROOT" | awk 'NR == 1 { print $1 }')"
    printf 'TOTAL_APP_KIB=%s\n' "$total_app_kib"
    printf 'MATERIAL_CONTRIBUTOR_COUNT=%s\n' "$material_count"
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --repo-root)
            [ "$#" -ge 2 ] || fail "--repo-root requires a path"
            REPO_ROOT="$2"
            shift 2
            ;;
        --source-manifest)
            [ "$#" -ge 2 ] || fail "--source-manifest requires a path"
            SOURCE_MANIFEST="$2"
            shift 2
            ;;
        --app)
            [ "$#" -ge 2 ] || fail "--app requires a path"
            APP_ROOT="${2%/}"
            shift 2
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            usage >&2
            fail "unknown argument: $1"
            ;;
    esac
done

[ -n "$REPO_ROOT" ] || fail "--repo-root is required"
[ -n "$SOURCE_MANIFEST" ] || fail "--source-manifest is required"
[ -n "$APP_ROOT" ] || fail "--app is required"
require_absolute_path "repository root" "$REPO_ROOT"
require_absolute_path "source manifest" "$SOURCE_MANIFEST"
require_absolute_path "app" "$APP_ROOT"
require_directory "repository root" "$REPO_ROOT"
require_file "source PrivacyInfo.xcprivacy" "$SOURCE_MANIFEST"
require_directory "supplied app" "$APP_ROOT"

PRIVACY_VALIDATOR="$REPO_ROOT/scripts/validate_privacy_manifest.sh"
COMPONENT_STATUS_VALIDATOR="$REPO_ROOT/scripts/validate_release_component_status.py"
COMPONENT_STATUS_RECORD="$REPO_ROOT/docs/implementation/provenance/release-component-status.json"
require_file "privacy validator" "$PRIVACY_VALIDATOR"
if [ ! -x "$PRIVACY_VALIDATOR" ]; then
    fail "privacy validator is not executable: $PRIVACY_VALIDATOR"
fi
require_file "component status validator" "$COMPONENT_STATUS_VALIDATOR"
if [ ! -x "$COMPONENT_STATUS_VALIDATOR" ]; then
    fail "component status validator is not executable: $COMPONENT_STATUS_VALIDATOR"
fi
require_file "component status record" "$COMPONENT_STATUS_RECORD"

if ! TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/release-bundle-validator.XXXXXX")"; then
    fail "could not create validator temporary directory"
fi

validate_privacy
validate_required_structure
validate_app_metadata
validate_forbidden_and_family_paths
validate_acknowledgements
validate_component_status
report_material_sizes
printf 'MANIFEST_COUNT=2\n'

if [ "$KNOWN_BLOCKER_COUNT" -gt 0 ]; then
    fail "release blocked by $KNOWN_BLOCKER_COUNT known provenance blocker(s)"
fi

printf 'PASS RELEASE BUNDLE VALIDATION: app=%s manifest_count=2 total_app_kib=%s material_contributors=%s known_blockers=%s\n' \
    "$APP_ROOT" \
    "$(du -sk "$APP_ROOT" | awk 'NR == 1 { print $1 }')" \
    "$(wc -l < "$TEMP_ROOT/material-contributors-sorted.tsv" | tr -d '[:space:]')" \
    "$KNOWN_BLOCKER_COUNT"
