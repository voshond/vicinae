#!/usr/bin/env bash
# Builds vicinae from this checkout and installs it, then restarts the running server.
# Uses its own build directory so it never picks up the dev build (QML loaded from source).
#
# Environment:
#   PREFIX     install prefix (default: /usr/local)
#   BUILD_DIR  build directory (default: build-release)
#   LTO        ON/OFF, link time optimization (default: ON, slower to build)
#
# Extra arguments are forwarded to the cmake configure step, e.g. -DENABLE_PREVIEW_FEATURES=ON.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PREFIX="${PREFIX:-/usr/local}"
BUILD_DIR="${BUILD_DIR:-build-release}"
LTO="${LTO:-ON}"

cd "$REPO_DIR"

cmake --preset linux-release -B "$BUILD_DIR" \
	-DCMAKE_INSTALL_PREFIX="$PREFIX" \
	-DLTO="$LTO" \
	-DBUILD_TESTS=OFF \
	-DVICINAE_DEV_MODE=OFF \
	-DVICINAE_NODE_RUNTIME_DOWNLOAD=ON \
	"$@"
cmake --build "$BUILD_DIR"

if [[ -w "$PREFIX" ]]; then
	cmake --install "$BUILD_DIR"
else
	sudo cmake --install "$BUILD_DIR"
fi

echo "Installed vicinae to $PREFIX"

if systemctl --user cat vicinae >/dev/null 2>&1; then
	systemctl --user daemon-reload
	systemctl --user restart vicinae
	echo "Restarted vicinae.service"
else
	"$PREFIX/bin/vicinae" server --replace >/dev/null 2>&1 &
	disown
	echo "Started vicinae server"
fi
