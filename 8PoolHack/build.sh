#!/bin/bash
set -e

echo "=== Compiling 8PoolHack.dylib (arm64 iOS) ==="

SDK_PATH=$(xcrun --sdk iphoneos --show-sdk-path)
echo "SDK: $SDK_PATH"

# Copy fishhook from sibling LQBypass module
cp -f ../LQBypass/fishhook.h .
cp -f ../LQBypass/fishhook.c .

clang -isysroot "$SDK_PATH" \
      -arch arm64 \
      -target arm64-apple-ios13.0 \
      -dynamiclib \
      -framework Foundation \
      -framework UIKit \
      -fobjc-arc \
      -O2 \
      -o 8PoolHack.dylib \
      8PoolHack.m fishhook.c

codesign -f -s - 8PoolHack.dylib || true

echo "=== Build result ==="
ls -la 8PoolHack.dylib
file 8PoolHack.dylib
