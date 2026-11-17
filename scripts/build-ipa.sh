#!/usr/bin/env bash
# 在 macOS 上一键出未签名 IPA：xcodegen -> xcodebuild -> package
# 用法：bash scripts/build-ipa.sh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "缺少 xcodegen，安装：brew install xcodegen" >&2
  exit 1
fi

xcodegen generate --spec project.yml

xcodebuild \
  -project Pangguai.xcodeproj \
  -scheme Pangguai \
  -configuration Release \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  DEVELOPMENT_TEAM="" \
  build

bash scripts/package-ipa.sh
