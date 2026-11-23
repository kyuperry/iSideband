#!/bin/bash
set -euo pipefail

cd "${CI_PRIMARY_REPOSITORY_PATH:?}"

if ! command -v go >/dev/null 2>&1; then
  brew install go
fi

frameworks="Native/Runcore/flutter/native/apple/Frameworks"
bash "$frameworks/build.sh" ios
ditto "$frameworks/iOS/Runcore.xcframework" ThirdParty/Runcore/Runcore.xcframework
