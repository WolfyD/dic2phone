#!/bin/bash
# Builds the vendored whisper.cpp (shared with the Android app) into ios/Vendor/WhisperCpp.xcframework:
# one static framework for iPhones and one for the simulator (Apple silicon and Intel Macs).
set -euo pipefail

repo=$(cd "$(dirname "$0")/../.." && pwd)
source_dir="$repo/app/src/main/cpp/whisper.cpp"
output="$repo/ios/Vendor/WhisperCpp.xcframework"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

deployment_target=18.0
# Same CPU baseline as Android: every iPhone that runs iOS 18 has half-precision SIMD.
arm_baseline=armv8.2-a+fp16
headers=(include/whisper.h ggml/include/ggml.h ggml/include/ggml-cpu.h ggml/include/ggml-backend.h ggml/include/ggml-alloc.h)

build_library() {
    local name=$1 sysroot=$2 arch=$3
    local build="$work/build-$name"
    local arch_options=()
    if [ "$arch" = arm64 ]; then
        arch_options=(-DGGML_CPU_ARM_ARCH="$arm_baseline")
    fi
    cmake -S "$source_dir" -B "$build" -G "Unix Makefiles" \
        -DCMAKE_SYSTEM_NAME=iOS \
        -DCMAKE_OSX_SYSROOT="$sysroot" \
        -DCMAKE_OSX_ARCHITECTURES="$arch" \
        -DCMAKE_OSX_DEPLOYMENT_TARGET="$deployment_target" \
        -DCMAKE_BUILD_TYPE=Release \
        -DBUILD_SHARED_LIBS=OFF \
        -DWHISPER_BUILD_TESTS=OFF -DWHISPER_BUILD_EXAMPLES=OFF -DWHISPER_BUILD_SERVER=OFF \
        -DWHISPER_ALL_WARNINGS=OFF -DGGML_ALL_WARNINGS=OFF \
        -DGGML_NATIVE=OFF -DGGML_OPENMP=OFF -DGGML_CCACHE=OFF \
        -DGGML_METAL=OFF -DGGML_BLAS=ON \
        "${arch_options[@]}"
    cmake --build "$build" --target whisper -j "$(sysctl -n hw.ncpu)"
    find "$build" -name '*.a' -print0 | xargs -0 libtool -static -o "$work/$name.a"
}

make_framework() {
    local name=$1
    shift
    local framework="$work/$name/WhisperCpp.framework"
    mkdir -p "$framework/Headers" "$framework/Modules"
    lipo -create "$@" -output "$framework/WhisperCpp"
    for header in "${headers[@]}"; do
        cp "$source_dir/$header" "$framework/Headers/"
    done
    cat > "$framework/Modules/module.modulemap" <<'MODULEMAP'
framework module WhisperCpp {
    umbrella header "whisper.h"
    export *
}
MODULEMAP
    cat > "$framework/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>WhisperCpp</string>
    <key>CFBundleIdentifier</key><string>com.dic2phone.whispercpp</string>
    <key>CFBundleName</key><string>WhisperCpp</string>
    <key>CFBundlePackageType</key><string>FMWK</string>
    <key>CFBundleShortVersionString</key><string>1.9.5</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>MinimumOSVersion</key><string>$deployment_target</string>
</dict>
</plist>
PLIST
}

build_library iphoneos iphoneos arm64
build_library simulator-arm64 iphonesimulator arm64
build_library simulator-x86_64 iphonesimulator x86_64

make_framework iphoneos "$work/iphoneos.a"
make_framework simulator "$work/simulator-arm64.a" "$work/simulator-x86_64.a"

rm -rf "$output"
xcodebuild -create-xcframework \
    -framework "$work/iphoneos/WhisperCpp.framework" \
    -framework "$work/simulator/WhisperCpp.framework" \
    -output "$output"
