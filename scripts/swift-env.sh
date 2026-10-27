#!/bin/bash
BUILD_ROOT="${ALICE_BUILD_ROOT:-$PWD/.build-local}"
mkdir -p "$BUILD_ROOT"
BUILD_ROOT="$(cd "$BUILD_ROOT" && pwd)"
export CLANG_MODULE_CACHE_PATH="$BUILD_ROOT/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$BUILD_ROOT/module-cache"
SWIFT_OPTIONS=(--scratch-path "$BUILD_ROOT/build" --cache-path "$BUILD_ROOT/cache" --config-path "$BUILD_ROOT/config" --security-path "$BUILD_ROOT/security" --disable-sandbox)
