#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${ROOT_DIR}/.build/release"
APP_DIR="${ROOT_DIR}/dist/AgentLight.app"

swift build -c release --product AgentLightMenuBar
mkdir -p "${APP_DIR}/Contents/MacOS" "${APP_DIR}/Contents/Resources"
cp "${BUILD_DIR}/AgentLightMenuBar" "${APP_DIR}/Contents/MacOS/AgentLight"
cp "${ROOT_DIR}/Info.plist" "${APP_DIR}/Contents/Info.plist"
codesign --force --deep --sign - "${APP_DIR}"
echo "Built ${APP_DIR}"
