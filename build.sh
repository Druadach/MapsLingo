#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
version="$(tr -d '\r\n' < "$project_dir/VERSION")"
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    printf '%s\n' 'VERSION must contain a numeric major.minor.patch version.' >&2
    exit 1
fi

if [[ "$(uname -s)" == Darwin ]]; then
    compiler="${CLANG:-$(xcrun --sdk iphoneos --find clang)}"
    lipo_tool="${LIPO:-$(xcrun --find lipo)}"
    sdk_root="${SDKROOT:-$(xcrun --sdk iphoneos --show-sdk-path)}"
else
    toolchain_bin="${TOOLCHAIN_BIN:-$project_dir/.build-tools/toolchain-modern/linux/iphone/bin}"
    compiler="${CLANG:-$toolchain_bin/clang}"
    lipo_tool="${LIPO:-$toolchain_bin/lipo}"
    sdk_root="${SDKROOT:-$project_dir/.build-tools/sdk/iPhoneOS15.6.sdk}"
fi
if [[ ! -x "$compiler" || ! -x "$lipo_tool" || ! -d "$sdk_root" ]]; then
    printf '%s\n' 'Use macOS with Xcode, or set TOOLCHAIN_BIN and SDKROOT to your iOS cross-toolchain and SDK.' >&2
    exit 1
fi

mkdir -p "$project_dir/build/$version" "$project_dir/dist"
base_flags=(-isysroot "$sdk_root" -std=gnu11 -fblocks -fvisibility=hidden -O2 -Wall -Wextra -Werror
            "-DML_VERSION=\"$version\"" -I "$project_dir/src")
for architecture in arm64 arm64e; do
    build_dir="$project_dir/build/$version/$architecture"
    mkdir -p "$build_dir"
    "$compiler" -target "$architecture-apple-ios15.0" "${base_flags[@]}" -c \
        "$project_dir/src/MapsLingoPreferences.c" -o "$build_dir/preferences.o"
    "$compiler" -target "$architecture-apple-ios15.0" "${base_flags[@]}" -fobjc-arc -c \
        "$project_dir/src/MapsLingoUI.m" -o "$build_dir/picker.o"
    "$compiler" -target "$architecture-apple-ios15.0" "${base_flags[@]}" -c \
        "$project_dir/src/MapsLingoRestore.c" -o "$build_dir/restore.o"
    for variant in MapsLingo MapsLingoRestore; do
        artifact="$variant-$version"
        objects=("$build_dir/preferences.o")
        libraries=(-framework CoreFoundation)
        if [[ "$variant" == MapsLingo ]]; then
            objects+=("$build_dir/picker.o")
            libraries+=(-framework Foundation -framework UIKit -lobjc)
        else
            objects+=("$build_dir/restore.o")
        fi
        "$compiler" -target "$architecture-apple-ios15.0" -isysroot "$sdk_root" -dynamiclib \
            "${objects[@]}" "${libraries[@]}" \
            -Wl,-install_name,@rpath/"$artifact".dylib \
            -Wl,-dead_strip -Wl,-adhoc_codesign -Wl,-fatal_warnings -Wl,-no_fixup_chains \
            -Wl,-current_version,"$version" -Wl,-compatibility_version,0.1.0 \
            -o "$build_dir/$artifact.dylib"
    done
done

for variant in MapsLingo MapsLingoRestore; do
    artifact="$variant-$version.dylib"
    "$lipo_tool" -create \
        "$project_dir/build/$version/arm64/$artifact" \
        "$project_dir/build/$version/arm64e/$artifact" \
        -output "$project_dir/dist/$artifact"
    "$lipo_tool" -info "$project_dir/dist/$artifact"
done

{
    printf 'MapsLingo %s\n\n' "$version"
    "$compiler" --version | sed '/^InstalledDir:/d'
    printf '\nTargets: arm64 + arm64e; iOS 15.0 minimum\n'
    printf 'Flags: -O2 -Wall -Wextra -Werror -no_fixup_chains -adhoc_codesign\n'
    printf 'Picker: UIKit + Foundation + CoreFoundation + libobjc + libSystem\n'
    printf 'Picker registration: runtime-created callbacks; no static Objective-C classes or categories\n'
    printf 'Restore: CoreFoundation + libSystem\n'
    printf 'On-device validation of this build: not established by compilation.\n'
} > "$project_dir/dist/BUILD-INFO-$version.txt"
printf '\nNext: node scripts/verify.mjs && node scripts/package.mjs\n'
