#!/bin/bash
# SessionStart hook: provision the Flutter SDK for Claude Code on the web so
# `flutter analyze` / `flutter test` / `dart run build_runner` work in remote
# sessions. The container image is cached after this completes, so the SDK
# download happens at most once per cached image; the idempotency check below
# skips it on every subsequent start.
set -euo pipefail

# Only run in remote (Claude Code on the web) environments.
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

FLUTTER_VERSION="3.44.4"   # bundles Dart 3.12.2 (satisfies pubspec sdk: ^3.12.0)
FLUTTER_DIR="/opt/flutter"
FLUTTER_BIN="$FLUTTER_DIR/bin"
DART_BIN="$FLUTTER_DIR/bin/cache/dart-sdk/bin"

log() { echo "[session-start] $*" >&2; }

if [ ! -x "$FLUTTER_BIN/flutter" ]; then
  log "Installing Flutter ${FLUTTER_VERSION} to ${FLUTTER_DIR} ..."
  TARBALL="/tmp/flutter_${FLUTTER_VERSION}.tar.xz"
  URL="https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz"
  curl -sSL --retry 3 --retry-delay 2 -o "$TARBALL" "$URL"
  tar -xf "$TARBALL" -C /opt
  rm -f "$TARBALL"
  log "Flutter extracted."
else
  log "Flutter already present, skipping download."
fi

export PATH="$FLUTTER_BIN:$DART_BIN:$PATH"
export PUB_CACHE="${PUB_CACHE:-/root/.pub-cache}"

# Flutter ships as a git checkout; allow running it as root in this container.
git config --global --add safe.directory "$FLUTTER_DIR" >/dev/null 2>&1 || true
flutter config --no-analytics --no-cli-animations >/dev/null 2>&1 || true

# Persist PATH/PUB_CACHE for the rest of the session.
if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
  {
    echo "export PATH=\"${FLUTTER_BIN}:${DART_BIN}:\$PATH\""
    echo "export PUB_CACHE=\"${PUB_CACHE}\""
  } >> "$CLAUDE_ENV_FILE"
fi

# Resolve project dependencies (quietly).
if [ -f "${CLAUDE_PROJECT_DIR:-$PWD}/pubspec.yaml" ]; then
  cd "${CLAUDE_PROJECT_DIR:-$PWD}"
  log "Running flutter pub get ..."
  flutter pub get >/dev/null 2>&1 || log "WARNING: flutter pub get failed"
fi

log "Ready: $(flutter --version 2>/dev/null | head -1)"
