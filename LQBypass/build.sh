#!/bin/bash
set -e

echo "=== Đang biên dịch LQBypass.dylib cho iOS ARM64 ==="

SDK_PATH=$(xcrun --sdk iphoneos --show-sdk-path)
echo "SDK Path: $SDK_PATH"

clang -isysroot "$SDK_PATH" \
      -arch arm64 \
      -target arm64-apple-ios14.0 \
      -dynamiclib \
      -framework Foundation \
      -framework UIKit \
      -fobjc-arc \
      -O2 \
      -o LQBypass.dylib \
      LQBypass.m fishhook.c

echo "=== Kiểm tra file sau biên dịch ==="
ls -la LQBypass.dylib
file LQBypass.dylib
