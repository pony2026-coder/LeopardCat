#!/usr/bin/env bash
set -euo pipefail

SING_BOX_VERSION="${SING_BOX_VERSION:-v1.14.0}"
SING_BOX_REPOSITORY="${SING_BOX_REPOSITORY:-https://github.com/SagerNet/sing-box.git}"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_ROOT="${BUILD_ROOT:-${PROJECT_ROOT}/.build/sing-box-${SING_BOX_VERSION}}"
ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-${HOME}/Library/Android/sdk}}"
ANDROID_NDK_HOME="${ANDROID_NDK_HOME:-${ANDROID_SDK_ROOT}/ndk/28.2.13676358}"
JAVA_HOME="${JAVA_HOME:-/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home}"
GOBIN="${GOBIN:-${HOME}/go/bin}"

if [[ ! -x "${JAVA_HOME}/bin/java" ]]; then
  echo "JDK 17 not found: ${JAVA_HOME}" >&2
  exit 1
fi
if [[ ! -d "${ANDROID_NDK_HOME}" ]]; then
  echo "Android NDK 28 not found: ${ANDROID_NDK_HOME}" >&2
  exit 1
fi

export PATH="${JAVA_HOME}/bin:${GOBIN}:${PATH}"
export JAVA_HOME ANDROID_NDK_HOME

mkdir -p "${BUILD_ROOT}"
if [[ ! -d "${BUILD_ROOT}/.git" ]]; then
  git clone --filter=blob:none --no-checkout "${SING_BOX_REPOSITORY}" "${BUILD_ROOT}"
fi
cd "${BUILD_ROOT}"
git fetch --depth 1 origin "${SING_BOX_VERSION}"
git checkout --force "${SING_BOX_VERSION}"

go install github.com/sagernet/gomobile/cmd/gomobile@v0.1.13
go install github.com/sagernet/gomobile/cmd/gobind@v0.1.13

go run ./cmd/internal/build_libbox -target android -platform android/arm64
aarch64_aar="${BUILD_ROOT}/libbox.aar"
cp "${aarch64_aar}" "${BUILD_ROOT}/libbox-arm64-v8a.aar"

go run ./cmd/internal/build_libbox -target android -platform android/arm
arm_aar="${BUILD_ROOT}/libbox.aar"
cp "${arm_aar}" "${BUILD_ROOT}/libbox-armeabi-v7a.aar"

go run ./cmd/internal/build_libbox -target android -platform android/amd64
amd64_aar="${BUILD_ROOT}/libbox.aar"
cp "${amd64_aar}" "${BUILD_ROOT}/libbox-x86_64.aar"

go run ./cmd/internal/merge_aar \
  -output "${PROJECT_ROOT}/android/app/libs/libbox.aar" \
  "${BUILD_ROOT}/libbox-arm64-v8a.aar" \
  "${BUILD_ROOT}/libbox-armeabi-v7a.aar" \
  "${BUILD_ROOT}/libbox-x86_64.aar"

sha256sum_cmd="$(command -v shasum || true)"
if [[ -n "${sha256sum_cmd}" ]]; then
  "${sha256sum_cmd}" -a 256 "${PROJECT_ROOT}/android/app/libs/libbox.aar" \
    | sed "s#${PROJECT_ROOT}/android/app/libs/##" \
    > "${PROJECT_ROOT}/android/app/libs/libbox-v1.14.0.sha256"
else
  shasum -a 256 "${PROJECT_ROOT}/android/app/libs/libbox.aar" \
    | sed "s#${PROJECT_ROOT}/android/app/libs/##" \
    > "${PROJECT_ROOT}/android/app/libs/libbox-v1.14.0.sha256"
fi

printf '\nBuilt multi-ABI libbox.aar:\n'
unzip -l "${PROJECT_ROOT}/android/app/libs/libbox.aar" | grep -E 'lib/(arm64-v8a|armeabi-v7a|x86_64)/libbox.so'
printf '\nSHA-256:\n'
cat "${PROJECT_ROOT}/android/app/libs/libbox-v1.14.0.sha256"
