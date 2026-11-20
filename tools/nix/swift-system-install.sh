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

# A build tree can carry the module twice: one copy sits beside the objects,
# the other is an intermediates copy without them, and `find` returns whichever
# comes first. Choose the copy whose neighbouring directories hold every target
# object, and fall back to the first one only when no copy qualifies.
module_candidates=()
# macOS ships bash 3.2, which has no mapfile.
while IFS= read -r candidate_module; do
  module_candidates+=("$candidate_module")
done < <(find "$BUILD_ROOT" -name SystemPackage.swiftmodule -print)
if [ "${#module_candidates[@]}" -eq 0 ]; then
  echo "swift-system: SystemPackage.swiftmodule was not built under $BUILD_ROOT" >&2
  find "$BUILD_ROOT" -maxdepth 5 -name '*.swiftmodule' -print >&2
  exit 1
fi

module=""
for candidate_module in "${module_candidates[@]}"; do
  candidate_module_dir="$(dirname "$candidate_module")"
  candidate_module_config="$(dirname "$candidate_module_dir")"
  for candidate_dir in "$candidate_module_dir" "$candidate_module_config"; do
    candidate_complete=1
    for candidate_target in "${targets[@]}"; do
      [ -f "$candidate_dir/$candidate_target.o" ] || candidate_complete=0
    done
    if [ "$candidate_complete" -eq 1 ]; then
      module="$candidate_module"
      break 2
    fi
  done
done
if [ -z "$module" ]; then
  module="${module_candidates[0]}"
  echo "swift-system: no module copy sits beside every target object; using $module" >&2
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
products_dir=""
collect_objects() {
  local dir="$1"
  local collected=()
  local target
  for target in "${targets[@]}"; do
    if [ -f "$dir/$target.o" ]; then
      collected+=("$dir/$target.o")
    else
      return 1
    fi
  done
  swiftbuild_objects=("${collected[@]}")
  products_dir="$dir"
  return 0
}

# First the directories that should sit beside the module, then every other
# directory of the build tree with Products directories ahead of the rest: a
# tree can carry the module in an intermediates directory while the objects
# live in Products/Debug.
for dir in "$module_dir" "$config_dir"; do
  collect_objects "$dir" && break
done
if [ "${#swiftbuild_objects[@]}" -ne "${#targets[@]}" ]; then
  candidate_dirs=()
  while IFS= read -r candidate_dir; do
    candidate_dirs+=("$candidate_dir")
  done < <(
    find "$BUILD_ROOT" -type d -print \
      | awk '{ print (index($0, "/Products/") ? "0 " : "1 ") $0 }' \
      | LC_ALL=C sort \
      | cut -d' ' -f2-
  )
  for dir in "${candidate_dirs[@]}"; do
    [ "$dir" = "$module_dir" ] && continue
    [ "$dir" = "$config_dir" ] && continue
    collect_objects "$dir" && break
  done
fi
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
