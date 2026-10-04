#!/bin/bash
# Builds llama.cpp as an xcframework with iOS device, iOS Simulator and macOS slices.
# The official release zip has no simulator slice, which stops the app building for the simulator.
# Output: Packages/LolekRuntime/Vendor/llama.xcframework (git-ignored). Takes ~10-20 minutes.
set -euo pipefail
TAG="${LLAMA_TAG:-b11388}"
HERE="$(cd "$(dirname "$0")/.." && pwd)"
WORK="${TMPDIR:-/tmp}/llama-build-$TAG"
command -v cmake >/dev/null || { echo "cmake is required: brew install cmake"; exit 1; }
rm -rf "$WORK"
git clone --depth 1 --branch "$TAG" https://github.com/ggml-org/llama.cpp "$WORK/src"
cd "$WORK/src"
./build-xcframework.sh ios-sim ios-device macos
mkdir -p "$HERE/Vendor"
rm -rf "$HERE/Vendor/llama.xcframework"
cp -R build-apple/llama.xcframework "$HERE/Vendor/llama.xcframework"
echo "Built $HERE/Vendor/llama.xcframework from llama.cpp $TAG"
