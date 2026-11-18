#!/usr/bin/env bash
# Install the SystemPackage module that "swift build --target SystemPackage"
# produced into OUT, for both SwiftPM build systems.
#
# Environment:
#   OUT                    install prefix (the derivation's $out)
#   BUILD_ROOT             the --build-path passed to swift build
#   SWIFTC                 the swiftc of the build toolchain
#   LIBRARY_SUFFIX         dylib on Darwin, so on Linux
#   TOOLCHAIN_STAMP        toolchain identity the derivation was evaluated with
#   TOOLCHAIN_VERSION_FILE output of "swift --version" recorded by buildPhase
#
# Run from the unpacked swift-system source root.
#
# The native build system keeps one <Target>.build directory per target under
# <build>/<config>, with a single SystemPackage.swiftmodule file under
# <build>/<config>/Modules. swiftbuild, the default from Swift 6.4, writes
# every product to <build>/out/Products/<Config> and keeps the module there as
# a directory with one file per architecture. This script accepts both.
#
# A wrong layout used to reach swiftc as an empty argument list (nixpkgs
# stdenv sets nullglob, so an unmatched pattern expands to nothing), and the
# build stopped with "no input files" from swiftc while the real cause, a
# product path the install phase did not know, stayed hidden. The object files
# are collected into an array here, the script checks that both targets
# contributed, and a miss reports the paths it looked at.
set -euo pipefail

: "${OUT:?OUT is required}"
: "${BUILD_ROOT:?BUILD_ROOT is required}"
: "${SWIFTC:?SWIFTC is required}"
: "${LIBRARY_SUFFIX:?LIBRARY_SUFFIX is required}"
TOOLCHAIN_STAMP="${TOOLCHAIN_STAMP:-host-unstamped}"
TOOLCHAIN_VERSION_FILE="${TOOLCHAIN_VERSION_FILE:-}"

# Keep the stdenv setting explicit: the collection below relies on an
# unmatched pattern expanding to no match, and each lookup inspects the
# resulting array before it links.
shopt -s nullglob

targets=(SystemPackage CSystem)

# The Darwin stamp is the host version line and part of the store path, so a
# value that does not match the toolchain that ran here would label an
# artifact built by a different Xcode. A stamp starting with "linux-" names
# the pinned store toolchain instead, which is already a build input.
verify_stamp=1
case "$TOOLCHAIN_STAMP" in
  host-unstamped | linux-*) verify_stamp=0 ;;
esac
if [ "$verify_stamp" -eq 1 ] && [ -n "$TOOLCHAIN_VERSION_FILE" ] && [ -f "$TOOLCHAIN_VERSION_FILE" ]; then
  observed="$(head -n 1 "$TOOLCHAIN_VERSION_FILE")"
  if [ "$observed" != "$TOOLCHAIN_STAMP" ]; then
    echo "swift-system: the evaluated toolchain is not the toolchain that ran the build" >&2
    echo "  evaluated: $TOOLCHAIN_STAMP" >&2
    echo "  observed:  $observed" >&2
    exit 1
  fi
fi

if [ ! -d Sources/CSystem/include ]; then
  echo "swift-system: Sources/CSystem/include is missing from $PWD" >&2
  exit 1
fi

mkdir -p "$OUT"
cp -R Sources/CSystem/include/. "$OUT/"

module="$(find "$BUILD_ROOT" -name SystemPackage.swiftmodule -print -quit)"
if [ -z "$module" ]; then
  echo "swift-system: SystemPackage.swiftmodule was not built under $BUILD_ROOT" >&2
  find "$BUILD_ROOT" -maxdepth 5 -name '*.swiftmodule' -print >&2
  exit 1
fi

if [ -d "$module" ]; then
  cp -R "$module" "$OUT/SystemPackage.swiftmodule"
else
  cp "$module" "$OUT/SystemPackage.swiftmodule"
fi

# The swiftbuild products sit next to the module, or one directory above it
# when the module is under Modules. The native objects sit in per-target
# build directories under the configuration directory.
module_dir="$(dirname "$module")"
config_dir="$(dirname "$module_dir")"
native_dir="$config_dir"

swiftbuild_objects=()
for dir in "$module_dir" "$config_dir"; do
  candidate=()
  complete=1
  for target in "${targets[@]}"; do
    if [ -f "$dir/$target.o" ]; then
      candidate+=("$dir/$target.o")
    else
      complete=0
    fi
  done
  if [ "$complete" -eq 1 ]; then
    swiftbuild_objects=("${candidate[@]}")
    products_dir="$dir"
    break
  fi
done

native_objects=()
native_complete=1
for target in "${targets[@]}"; do
  target_objects=("$native_dir/$target".build/*.o)
  if [ "${#target_objects[@]}" -eq 0 ]; then
    native_complete=0
  else
    native_objects+=("${target_objects[@]}")
  fi
done

object_files=()
layout=""
if [ "${#swiftbuild_objects[@]}" -eq "${#targets[@]}" ]; then
  layout="swiftbuild"
  object_files=("${swiftbuild_objects[@]}")
elif [ "$native_complete" -eq 1 ] && [ "${#native_objects[@]}" -gt 0 ]; then
  layout="native"
  object_files=("${native_objects[@]}")
fi

if [ -z "$layout" ]; then
  {
    echo "swift-system: no object files for SystemPackage and CSystem"
    echo "  swift module: $module"
    echo "  swiftbuild layout: $module_dir/{SystemPackage,CSystem}.o and $config_dir/{SystemPackage,CSystem}.o"
    echo "  native layout: $native_dir/{SystemPackage,CSystem}.build/*.o"
    echo "  swiftc: $SWIFTC"
    echo "  build tree:"
    find "$BUILD_ROOT" -maxdepth 4 -print | LC_ALL=C sort | sed 's/^/    /'
  } >&2
  exit 1
fi

echo "swift-system: build system $layout, ${#object_files[@]} object files"
for object in "${object_files[@]}"; do
  echo "swift-system: $object"
done

"$SWIFTC" -emit-library "${object_files[@]}" -o "$OUT/libSystemPackage.$LIBRARY_SUFFIX"

{
  echo "stamp=$TOOLCHAIN_STAMP"
  if [ -n "$TOOLCHAIN_VERSION_FILE" ] && [ -f "$TOOLCHAIN_VERSION_FILE" ]; then
    cat "$TOOLCHAIN_VERSION_FILE"
  fi
  echo "layout=$layout"
} > "$OUT/swift-toolchain.txt"
