#!/usr/bin/env bash
# Fixture test for tools/nix/swift-system-install.sh.
#
# Synthetic build trees carry object files compiled here by the local swiftc
# and C compiler: one tree in the swiftbuild layout (out/Products/Debug), one
# in the native layout (debug/<Target>.build), one holding a module and no
# objects, and one holding a single target. The installer must produce a
# shared library with defined symbols from the first two, and must stop with
# its own diagnostic, never swiftc's "no input files", on the others.
#
# Run inside the flake environment so swiftc matches the toolchain that builds
# the derivation:
#
#     nix develop -c bash -c 'bash tools/nix/test-swift-system-install.sh'
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
installer="$repo_root/tools/nix/swift-system-install.sh"
SWIFTC="${SWIFTC:-swiftc}"
cc_bin="${CC:-clang}"

case "$(uname -s)" in
  Darwin) library_suffix="dylib"; nm_flags=(-gU) ;;
  *) library_suffix="so"; nm_flags=(-D --defined-only) ;;
esac

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
fail=0

pass() { printf 'PASS %s\n' "$1"; }
failed() { printf 'FAIL %s\n' "$1" >&2; fail=1; }

artifacts="$work/artifacts"
mkdir -p "$artifacts"
printf 'public func swiftPackageProbe() -> Int32 { 7 }\n' > "$artifacts/SwiftProbe.swift"
printf 'int c_system_probe(void) { return 11; }\n' > "$artifacts/c_probe.c"
"$SWIFTC" -parse-as-library -emit-object -module-name SystemPackage \
  -o "$artifacts/SystemPackage.o" "$artifacts/SwiftProbe.swift"
"$SWIFTC" -parse-as-library -emit-module -module-name SystemPackage \
  -o "$artifacts/SystemPackage.swiftmodule" "$artifacts/SwiftProbe.swift"
"$cc_bin" -c "$artifacts/c_probe.c" -o "$artifacts/CSystem.o"

# Every fixture carries the CSystem include tree the installer copies.
make_source_root() {
  local root="$1"
  mkdir -p "$root/Sources/CSystem/include"
  printf '#pragma once\nint c_system_probe(void);\n' > "$root/Sources/CSystem/include/probe.h"
}

# The native layout: <build>/debug/Modules/<module file> and one build
# directory per target under <build>/debug.
native="$work/native"
make_source_root "$native/src"
mkdir -p "$native/build/debug/Modules" \
  "$native/build/debug/SystemPackage.build" \
  "$native/build/debug/CSystem.build"
cp "$artifacts/SystemPackage.swiftmodule" "$native/build/debug/Modules/SystemPackage.swiftmodule"
cp "$artifacts/SystemPackage.o" "$native/build/debug/SystemPackage.build/SystemPackage.o"
cp "$artifacts/CSystem.o" "$native/build/debug/CSystem.build/CSystem.o"

out_native="$work/out-native"
( cd "$native/src" && OUT="$out_native" BUILD_ROOT="$native/build" SWIFTC="$SWIFTC" \
  LIBRARY_SUFFIX="$library_suffix" bash "$installer" ) > "$work/native.log" 2>&1 \
  || failed "native layout: the installer exited non-zero"

if [ -f "$out_native/libSystemPackage.$library_suffix" ] \
  && [ -f "$out_native/SystemPackage.swiftmodule" ] \
  && grep -q '^layout=native$' "$out_native/swift-toolchain.txt"; then
  pass "native layout: library and swiftmodule installed"
else
  failed "native layout: expected a library, a module file and layout=native"
fi

native_symbols="$(nm "${nm_flags[@]}" "$out_native/libSystemPackage.$library_suffix" 2>/dev/null | wc -l)"
if [ "$native_symbols" -gt 0 ] && nm "${nm_flags[@]}" "$out_native/libSystemPackage.$library_suffix" 2>/dev/null | grep -q 'c_system_probe'; then
  pass "native layout: $native_symbols defined symbols"
else
  failed "native layout: expected defined symbols including c_system_probe"
fi

# The swiftbuild layout: out/Products/Debug holds both objects and the module
# as a directory with one file per architecture.
swiftbuild="$work/swiftbuild"
make_source_root "$swiftbuild/src"
mkdir -p "$swiftbuild/build/out/Products/Debug/SystemPackage.swiftmodule"
cp "$artifacts/SystemPackage.o" "$swiftbuild/build/out/Products/Debug/SystemPackage.o"
cp "$artifacts/CSystem.o" "$swiftbuild/build/out/Products/Debug/CSystem.o"
cp "$artifacts/SystemPackage.swiftmodule" \
  "$swiftbuild/build/out/Products/Debug/SystemPackage.swiftmodule/probe.swiftmodule"

out_swiftbuild="$work/out-swiftbuild"
( cd "$swiftbuild/src" && OUT="$out_swiftbuild" BUILD_ROOT="$swiftbuild/build" SWIFTC="$SWIFTC" \
  LIBRARY_SUFFIX="$library_suffix" bash "$installer" ) > "$work/swiftbuild.log" 2>&1 \
  || failed "swiftbuild layout: the installer exited non-zero"

if [ -f "$out_swiftbuild/libSystemPackage.$library_suffix" ] \
  && [ -d "$out_swiftbuild/SystemPackage.swiftmodule" ] \
  && grep -q '^layout=swiftbuild$' "$out_swiftbuild/swift-toolchain.txt"; then
  pass "swiftbuild layout: library and swiftmodule directory installed"
else
  failed "swiftbuild layout: expected a library, a module directory and layout=swiftbuild"
fi

swiftbuild_symbols="$(nm "${nm_flags[@]}" "$out_swiftbuild/libSystemPackage.$library_suffix" 2>/dev/null | wc -l)"
if [ "$swiftbuild_symbols" -gt 0 ] && nm "${nm_flags[@]}" "$out_swiftbuild/libSystemPackage.$library_suffix" 2>/dev/null | grep -q 'c_system_probe'; then
  pass "swiftbuild layout: $swiftbuild_symbols defined symbols"
else
  failed "swiftbuild layout: expected defined symbols including c_system_probe"
fi

# The module sits in an intermediates directory without objects while the
# objects sit in Products/Debug: \`find -print -quit\` returns the module copy
# and the object lookup that follows it finds nothing.
twocopies="$work/twocopies"
make_source_root "$twocopies/src"
mkdir -p "$twocopies/build/out/Intermediates.noindex/SystemPackage.build/Debug/SystemPackage.build/Modules/SystemPackage.swiftmodule"
mkdir -p "$twocopies/build/out/Products/Debug"
cp "$artifacts/SystemPackage.o" "$twocopies/build/out/Products/Debug/SystemPackage.o"
cp "$artifacts/CSystem.o" "$twocopies/build/out/Products/Debug/CSystem.o"
cp "$artifacts/SystemPackage.swiftmodule" \
  "$twocopies/build/out/Intermediates.noindex/SystemPackage.build/Debug/SystemPackage.build/Modules/SystemPackage.swiftmodule/probe.swiftmodule"

out_twocopies="$work/out-twocopies"
( cd "$twocopies/src" && OUT="$out_twocopies" BUILD_ROOT="$twocopies/build" SWIFTC="$SWIFTC" \
  LIBRARY_SUFFIX="$library_suffix" bash "$installer" ) > "$work/twocopies.log" 2>&1 \
  || failed "intermediates module with products objects: the installer exited non-zero"

if [ -f "$out_twocopies/libSystemPackage.$library_suffix" ] \
  && [ -d "$out_twocopies/SystemPackage.swiftmodule" ] \
  && grep -q '^layout=swiftbuild$' "$out_twocopies/swift-toolchain.txt"; then
  pass "intermediates module with products objects: found the objects in Products/Debug"
else
  failed "intermediates module with products objects: the installer did not find the objects"
fi
# One installer run that must fail with the installer's diagnostic and never
# with swiftc's empty argument list.
expect_installer_error() {
  local name="$1" out="$2" build="$3" src="$4"
  local log="$work/$name.log"
  if ( cd "$src" && OUT="$out" BUILD_ROOT="$build" SWIFTC="$SWIFTC" \
    LIBRARY_SUFFIX="$library_suffix" bash "$installer" ) > "$log" 2>&1; then
    failed "$name: the installer exited 0"
    return
  fi
  if grep -q 'no input files' "$log"; then
    failed "$name: swiftc reported no input files"
    return
  fi
  if grep -q 'no object files for SystemPackage and CSystem' "$log"; then
    pass "$name: installer diagnostic before any swiftc error"
  else
    failed "$name: expected the object collection diagnostic"
  fi
}

# A module with no objects, the state Swift 6.4 produced on Xcode 27 while the
# install phase still assumed the native layout.
empty="$work/empty"
make_source_root "$empty/src"
mkdir -p "$empty/build/out/Products/Debug/SystemPackage.swiftmodule"
cp "$artifacts/SystemPackage.swiftmodule" \
  "$empty/build/out/Products/Debug/SystemPackage.swiftmodule/probe.swiftmodule"
expect_installer_error "no objects" "$work/out-empty" "$empty/build" "$empty/src"

# A layout with one target missing must fail before it links a library with
# unresolved symbols.
partial="$work/partial"
make_source_root "$partial/src"
mkdir -p "$partial/build/out/Products/Debug/SystemPackage.swiftmodule"
cp "$artifacts/SystemPackage.o" "$partial/build/out/Products/Debug/SystemPackage.o"
cp "$artifacts/SystemPackage.swiftmodule" \
  "$partial/build/out/Products/Debug/SystemPackage.swiftmodule/probe.swiftmodule"
expect_installer_error "missing CSystem objects" "$work/out-partial" "$partial/build" "$partial/src"

# No module at all reports the module lookup.
nomodule="$work/nomodule"
make_source_root "$nomodule/src"
mkdir -p "$nomodule/build"
if ( cd "$nomodule/src" && OUT="$work/out-nomodule" BUILD_ROOT="$nomodule/build" SWIFTC="$SWIFTC" \
  LIBRARY_SUFFIX="$library_suffix" bash "$installer" ) > "$work/nomodule.log" 2>&1; then
  failed "no module: the installer exited 0"
elif grep -q 'SystemPackage.swiftmodule was not built' "$work/nomodule.log"; then
  pass "no module: installer diagnostic names the missing module"
else
  failed "no module: expected the module lookup diagnostic"
fi

# A toolchain stamp that does not match the recorded toolchain fails before
# the link, so a stale stamped derivation cannot ship foreign artifacts.
version_file="$work/version.txt"
printf 'Swift version 6.2.4 (swift-6.2.4-RELEASE)\nTarget: x86_64-unknown-linux-gnu\n' > "$version_file"
if ( cd "$native/src" && OUT="$work/out-stamp-mismatch" BUILD_ROOT="$native/build" \
  SWIFTC="$SWIFTC" LIBRARY_SUFFIX="$library_suffix" \
  TOOLCHAIN_STAMP="Swift version 9.9.9 (swift-9.9.9-RELEASE)" \
  TOOLCHAIN_VERSION_FILE="$version_file" bash "$installer" ) > "$work/stamp.log" 2>&1; then
  failed "stamp mismatch: the installer exited 0"
elif grep -q 'the evaluated toolchain is not the toolchain that ran the build' "$work/stamp.log"; then
  pass "stamp mismatch: installer refuses a stale toolchain stamp"
else
  failed "stamp mismatch: expected the toolchain stamp diagnostic"
fi

# A matching stamp is recorded in the output, so the devShell can compare it
# with the host toolchain.
out_stamped="$work/out-stamped"
if ( cd "$native/src" && OUT="$out_stamped" BUILD_ROOT="$native/build" SWIFTC="$SWIFTC" \
  LIBRARY_SUFFIX="$library_suffix" \
  TOOLCHAIN_STAMP="Swift version 6.2.4 (swift-6.2.4-RELEASE)" \
  TOOLCHAIN_VERSION_FILE="$version_file" bash "$installer" ) > "$work/stamped.log" 2>&1 \
  && grep -q '^stamp=Swift version 6.2.4 (swift-6.2.4-RELEASE)$' "$out_stamped/swift-toolchain.txt"; then
  pass "matching stamp: recorded in swift-toolchain.txt"
else
  failed "matching stamp: expected the stamp in swift-toolchain.txt"
fi

if [ "$fail" -ne 0 ]; then
  echo "swift-system install layout check: FAILED" >&2
  exit 1
fi
echo "swift-system install layout check: all cases pass"
