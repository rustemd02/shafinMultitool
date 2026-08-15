#!/usr/bin/env bash
set -e

IOS_MIN_OS_VERSION=16.4
BUILD_SHARED_LIBS=OFF
COMMON_C_FLAGS="-Wno-macro-redefined -Wno-shorten-64-to-32 -Wno-unused-command-line-argument"
COMMON_CXX_FLAGS="-Wno-macro-redefined -Wno-shorten-64-to-32 -Wno-unused-command-line-argument"

COMMON_CMAKE_ARGS=(
    -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_REQUIRED=NO
    -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGN_IDENTITY=""
    -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED=NO
    -DBUILD_SHARED_LIBS=${BUILD_SHARED_LIBS}
    -DLLAMA_BUILD_EXAMPLES=OFF
    -DLLAMA_BUILD_TOOLS=OFF
    -DLLAMA_BUILD_TESTS=OFF
    -DLLAMA_BUILD_SERVER=OFF
    -DGGML_METAL_EMBED_LIBRARY=ON
    -DGGML_BLAS_DEFAULT=ON
    -DGGML_METAL=ON
    -DGGML_METAL_USE_BF16=ON
    -DGGML_NATIVE=OFF
    -DGGML_OPENMP=OFF
)

echo "=== Cleaning previous builds ==="
rm -rf build-ios-sim build-ios-device build-apple

echo "=== Building for iOS simulator (arm64 + x86_64) ==="
cmake -B build-ios-sim -G Xcode \
    "${COMMON_CMAKE_ARGS[@]}" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=${IOS_MIN_OS_VERSION} \
    -DIOS=ON \
    -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_OSX_SYSROOT=iphonesimulator \
    -DCMAKE_OSX_ARCHITECTURES="arm64;x86_64" \
    -DCMAKE_XCODE_ATTRIBUTE_SUPPORTED_PLATFORMS=iphonesimulator \
    -DCMAKE_C_FLAGS="${COMMON_C_FLAGS}" \
    -DCMAKE_CXX_FLAGS="${COMMON_CXX_FLAGS}" \
    -DLLAMA_OPENSSL=OFF \
    -S .
cmake --build build-ios-sim --config Release -- -quiet

echo "=== Building for iOS device (arm64) ==="
cmake -B build-ios-device -G Xcode \
    "${COMMON_CMAKE_ARGS[@]}" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=${IOS_MIN_OS_VERSION} \
    -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_OSX_SYSROOT=iphoneos \
    -DCMAKE_OSX_ARCHITECTURES="arm64" \
    -DCMAKE_XCODE_ATTRIBUTE_SUPPORTED_PLATFORMS=iphoneos \
    -DCMAKE_C_FLAGS="${COMMON_C_FLAGS}" \
    -DCMAKE_CXX_FLAGS="${COMMON_CXX_FLAGS}" \
    -DLLAMA_OPENSSL=OFF \
    -S .
cmake --build build-ios-device --config Release -- -quiet

echo "=== Setting up framework structures ==="

setup_framework() {
    local build_dir=$1
    mkdir -p ${build_dir}/framework/llama.framework/Headers
    mkdir -p ${build_dir}/framework/llama.framework/Modules

    cp include/llama.h             ${build_dir}/framework/llama.framework/Headers/
    cp ggml/include/ggml.h         ${build_dir}/framework/llama.framework/Headers/
    cp ggml/include/ggml-opt.h     ${build_dir}/framework/llama.framework/Headers/
    cp ggml/include/ggml-alloc.h   ${build_dir}/framework/llama.framework/Headers/
    cp ggml/include/ggml-backend.h ${build_dir}/framework/llama.framework/Headers/
    cp ggml/include/ggml-metal.h   ${build_dir}/framework/llama.framework/Headers/
    cp ggml/include/ggml-cpu.h     ${build_dir}/framework/llama.framework/Headers/
    cp ggml/include/ggml-blas.h    ${build_dir}/framework/llama.framework/Headers/
    cp ggml/include/gguf.h         ${build_dir}/framework/llama.framework/Headers/

    cat > ${build_dir}/framework/llama.framework/Modules/module.modulemap << 'EOF'
framework module llama {
    header "llama.h"
    header "ggml.h"
    header "ggml-alloc.h"
    header "ggml-backend.h"
    header "ggml-metal.h"
    header "ggml-cpu.h"
    header "ggml-blas.h"
    header "gguf.h"

    link "c++"
    link framework "Accelerate"
    link framework "Metal"
    link framework "Foundation"

    export *
}
EOF

    cat > ${build_dir}/framework/llama.framework/Info.plist << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>llama</string>
    <key>CFBundleIdentifier</key>
    <string>org.ggml.llama</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundlePackageType</key>
    <string>FMWK</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>MinimumOSVersion</key>
    <string>${IOS_MIN_OS_VERSION}</string>
</dict>
</plist>
PLIST
}

setup_framework "build-ios-sim"
setup_framework "build-ios-device"

echo "=== Combining static libraries ==="

combine_libs() {
    local build_dir=$1
    local release_dir=$2
    local sdk=$3
    local archs=$4
    local is_sim=$5
    local base_dir=$(pwd)

    local temp_dir="${build_dir}/temp"
    mkdir -p "${temp_dir}"

    local libs=(
        "${base_dir}/${build_dir}/src/${release_dir}/libllama.a"
        "${base_dir}/${build_dir}/ggml/src/${release_dir}/libggml.a"
        "${base_dir}/${build_dir}/ggml/src/${release_dir}/libggml-base.a"
        "${base_dir}/${build_dir}/ggml/src/${release_dir}/libggml-cpu.a"
        "${base_dir}/${build_dir}/ggml/src/ggml-metal/${release_dir}/libggml-metal.a"
        "${base_dir}/${build_dir}/ggml/src/ggml-blas/${release_dir}/libggml-blas.a"
    )

    xcrun libtool -static -o "${temp_dir}/combined.a" "${libs[@]}" 2>/dev/null

    local arch_flags=""
    for arch in $archs; do
        arch_flags+=" -arch $arch"
    done

    local min_flag=""
    if [ "$is_sim" == "true" ]; then
        min_flag="-mios-simulator-version-min=${IOS_MIN_OS_VERSION}"
    else
        min_flag="-mios-version-min=${IOS_MIN_OS_VERSION}"
    fi

    echo "Creating dynamic library for ${build_dir}..."
    xcrun -sdk $sdk clang++ -dynamiclib \
        -isysroot $(xcrun --sdk $sdk --show-sdk-path) \
        $arch_flags \
        $min_flag \
        -Wl,-force_load,"${temp_dir}/combined.a" \
        -framework Foundation -framework Metal -framework Accelerate \
        -install_name "@rpath/llama.framework/llama" \
        -o "${base_dir}/${build_dir}/framework/llama.framework/llama"

    if [ "$is_sim" == "false" ]; then
        if xcrun -f vtool &>/dev/null; then
            xcrun vtool -set-build-version ios ${IOS_MIN_OS_VERSION} ${IOS_MIN_OS_VERSION} -replace \
                -output "${base_dir}/${build_dir}/framework/llama.framework/llama" \
                "${base_dir}/${build_dir}/framework/llama.framework/llama"
        fi
    fi

    rm -rf "${temp_dir}"
}

combine_libs "build-ios-sim" "Release-iphonesimulator" "iphonesimulator" "arm64 x86_64" "true"
combine_libs "build-ios-device" "Release-iphoneos" "iphoneos" "arm64" "false"

echo "=== Creating XCFramework ==="
xcrun xcodebuild -create-xcframework \
    -framework $(pwd)/build-ios-sim/framework/llama.framework \
    -framework $(pwd)/build-ios-device/framework/llama.framework \
    -output $(pwd)/build-apple/llama.xcframework

echo "=== Done! ==="
echo "XCFramework is at: $(pwd)/build-apple/llama.xcframework"
ls -la build-apple/llama.xcframework/
