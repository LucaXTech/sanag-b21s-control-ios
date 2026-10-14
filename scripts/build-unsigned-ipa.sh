#!/usr/bin/env bash
# Build an unsigned iPhone IPA for SideStore to sign and install.
# Does not touch a connected phone or overwrite an installed app.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED="${HOME}/Downloads/SanagBuild-045"
OUTPUT="${HOME}/Downloads/SanagControl-0.4.5.ipa"

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "Xcode non disponibile. Usa il Mac con Xcode installato." >&2
  exit 1
fi

xcodebuild \
  -project "$ROOT/SanagControl.xcodeproj" \
  -scheme SanagControl \
  -configuration Debug \
  -sdk iphoneos \
  -destination "generic/platform=iOS" \
  -derivedDataPath "$DERIVED" \
  CODE_SIGNING_ALLOWED=NO \
  -quiet build

APP="$DERIVED/Build/Products/Debug-iphoneos/SanagControl.app"
if [ ! -d "$APP" ]; then
  echo "App compilata non trovata: $APP" >&2
  exit 1
fi

IDENTIFIER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Info.plist")"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Info.plist")"
ENDPOINT="$(/usr/libexec/PlistBuddy -c 'Print :DeviceReportURL' "$APP/Info.plist")"

if [ "$VERSION" != "0.4.5" ]; then
  echo "Versione imprevista: $VERSION (attesa 0.4.5)." >&2
  exit 1
fi

echo "Bundle ID: $IDENTIFIER"
echo "Versione: $VERSION"
if [ -z "$ENDPOINT" ]; then
  echo "ATTENZIONE: DeviceReportURL vuoto, invio remoto disattivato."
else
  case "$ENDPOINT" in
    https://*/v1/report) echo "Ricevitore HTTPS configurato: $ENDPOINT" ;;
    *) echo "Endpoint non valido: $ENDPOINT" >&2; exit 1 ;;
  esac
fi

TMP_PACKAGE="$(mktemp -d "${TMPDIR:-/tmp/}sanag-package.XXXXXXXX")"
trap 'rm -rf "$TMP_PACKAGE"' EXIT
mkdir -p "$TMP_PACKAGE/Payload"
ditto "$APP" "$TMP_PACKAGE/Payload/SanagControl.app"
rm -f "$OUTPUT"
(cd "$TMP_PACKAGE" && zip -qry "$OUTPUT" Payload)
unzip -tq "$OUTPUT"
ls -lh "$OUTPUT"
echo "IPA non firmata pronta per SideStore: $OUTPUT"
