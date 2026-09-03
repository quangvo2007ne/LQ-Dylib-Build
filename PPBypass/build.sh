#!/bin/bash
set -e

echo "=== Đang biên dịch PPBypass.dylib (arm64 iOS) ==="

SDK_PATH=$(xcrun --sdk iphoneos --show-sdk-path)
echo "SDK Path: $SDK_PATH"

clang -isysroot "$SDK_PATH" \
      -arch arm64 \
      -target arm64-apple-ios13.0 \
      -dynamiclib \
      -framework Foundation \
      -framework UIKit \
      -fobjc-arc \
      -O2 \
      -o PPBypass.dylib \
      PPBypass.m

codesign -f -s - PPBypass.dylib || true

echo "=== Kiểm tra file sau biên dịch ==="
ls -la PPBypass.dylib
file PPBypass.dylib
