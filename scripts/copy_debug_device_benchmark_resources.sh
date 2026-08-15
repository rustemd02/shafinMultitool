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

rm -rf "$DESTINATION_DIR"

if [ "${CONFIGURATION:-}" != "Debug" ]; then
    exit 0
fi

if [ ! -d "$SOURCE_DIR" ]; then
    echo "error: benchmark resource source is missing: $SOURCE_DIR" >&2
    exit 1
fi

mkdir -p "$DESTINATION_DIR"
cp -R "$SOURCE_DIR/." "$DESTINATION_DIR/"
: > "$MARKER_PATH"
