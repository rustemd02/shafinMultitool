#!/bin/sh
set -eu

if [ -z "${SRCROOT:-}" ]; then
    echo "error: SRCROOT must be non-empty" >&2
    exit 1
fi
if [ -z "${TARGET_BUILD_DIR:-}" ]; then
    echo "error: TARGET_BUILD_DIR must be non-empty" >&2
    exit 1
fi
if [ -z "${UNLOCALIZED_RESOURCES_FOLDER_PATH:-}" ]; then
    echo "error: UNLOCALIZED_RESOURCES_FOLDER_PATH must be non-empty" >&2
    exit 1
fi

SOURCE_DIR="${SRCROOT}/shafinMultitool/Resources/DeviceBenchmark"
DESTINATION_DIR="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/DeviceBenchmark"
MARKER_PATH="${DESTINATION_DIR}/.debug-resource-copy-marker"
FIXTURE_SOURCE="${SRCROOT}/shafinMultitool/Resources/Fixtures/SETCameraFrame.png"
FIXTURE_DESTINATION="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/SETCameraFrame.png"
SCENARIOS_SOURCE="${SRCROOT}/docs/cameraanalysis/demo/semantic_demo_scenarios.json"
SCENARIOS_DESTINATION="${DESTINATION_DIR}/camera_device_benchmark_pack_v1/semantic_demo_scenarios.json"

if [ -z "$DESTINATION_DIR" ]; then
    echo "error: benchmark resource destination must be non-empty" >&2
    exit 1
fi
case "$DESTINATION_DIR" in
    "${TARGET_BUILD_DIR}/"*)
        ;;
    *)
        echo "error: refusing destination outside TARGET_BUILD_DIR: $DESTINATION_DIR" >&2
        exit 1
        ;;
esac
case "$FIXTURE_DESTINATION" in
    "${TARGET_BUILD_DIR}/"*)
        ;;
    *)
        echo "error: refusing fixture destination outside TARGET_BUILD_DIR: $FIXTURE_DESTINATION" >&2
        exit 1
        ;;
esac

rm -rf "$DESTINATION_DIR"
rm -f "$FIXTURE_DESTINATION"

if [ "${CONFIGURATION:-}" != "Debug" ]; then
    exit 0
fi

if [ ! -d "$SOURCE_DIR" ]; then
    echo "error: benchmark resource source is missing: $SOURCE_DIR" >&2
    exit 1
fi
if [ ! -f "$FIXTURE_SOURCE" ]; then
    echo "error: camera fixture source is missing: $FIXTURE_SOURCE" >&2
    exit 1
fi
if [ ! -f "$SCENARIOS_SOURCE" ]; then
    echo "error: semantic demo scenarios source is missing: $SCENARIOS_SOURCE" >&2
    exit 1
fi

mkdir -p "$DESTINATION_DIR"
cp -R "$SOURCE_DIR/." "$DESTINATION_DIR/"
cp "$SCENARIOS_SOURCE" "$SCENARIOS_DESTINATION"
: > "$MARKER_PATH"
cp "$FIXTURE_SOURCE" "$FIXTURE_DESTINATION"
