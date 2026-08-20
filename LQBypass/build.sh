#!/bin/bash
# =========================================================================
# Script build LQBypass.dylib trên macOS / Linux (với iOS SDK)
# =========================================================================

echo "=== Đang biên dịch LQBypass.dylib cho iOS ARM64 ==="

SDK_PATH=$(xcrun --sdk iphoneos --show-sdk-path 2>/dev/null)

if [ -z "$SDK_PATH" ]; then
    echo "Dùng clang mặc định với target iOS..."
    clang -target arm64-apple-ios14.0 \
          -dynamiclib \
          -framework Foundation \
          -framework UIKit \
          -fobjc-arc \
          -O2 \
          -o LQBypass.dylib \
          LQBypass.m
else
    echo "Dùng Xcode iOS SDK: $SDK_PATH"
    clang -isysroot "$SDK_PATH" \
          -arch arm64 \
          -dynamiclib \
          -framework Foundation \
          -framework UIKit \
          -fobjc-arc \
          -O2 \
          -o LQBypass.dylib \
          LQBypass.m
fi

echo "=== Hoàn tất: LQBypass.dylib đã được tạo! ==="
