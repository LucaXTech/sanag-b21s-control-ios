#!/usr/bin/env python3
"""Configure an unsigned IPA locally, before SideStore signs it.

The receiver address is never committed to the public source tree and
does not appear in GitHub Actions build logs or upload artifacts.
"""
import argparse
import os
import plistlib
import sys
import tempfile
import zipfile
from pathlib import Path
from urllib.parse import urlsplit

PLIST_PATH = "Payload/SanagControl.app/Info.plist"
EXPECTED_BUNDLE = "com.lucaxtech.sanagcontrol"
EXPECTED_VERSION = "0.5.0"


def validate_endpoint(value: str) -> None:
    parsed = urlsplit(value)
    if (
        parsed.scheme != "https"
        or not parsed.hostname
        or parsed.username
        or parsed.password
        or parsed.query
        or parsed.fragment
        or parsed.path != "/v1/report"
        or any(c.isspace() for c in value)
    ):
        raise ValueError("Endpoint must be https://HOST/v1/report, without credentials or query.")


def configure(source: Path, output: Path, endpoint: str) -> None:
    validate_endpoint(endpoint)
    if not source.is_file():
        raise FileNotFoundError(f"IPA input not found: {source}")
    if source.resolve() == output.resolve():
        raise ValueError("Input and output must be different files.")
    output.parent.mkdir(parents=True, exist_ok=True)

    fd, temporary = tempfile.mkstemp(suffix=".ipa", prefix="sanag-", dir=output.parent)
    os.close(fd)
    try:
        found_plist = False
        with zipfile.ZipFile(source) as original, zipfile.ZipFile(temporary, "w") as result:
            if original.testzip() is not None:
                raise ValueError("Input IPA ZIP is damaged.")
            for entry in original.infolist():
                contents = original.read(entry)
                if entry.filename == PLIST_PATH:
                    if found_plist:
                        raise ValueError("Duplicate Info.plist.")
                    found_plist = True
                    info = plistlib.loads(contents)
                    if info.get("CFBundleIdentifier") != EXPECTED_BUNDLE:
                        raise ValueError("Unexpected Bundle Identifier.")
                    if info.get("CFBundleShortVersionString") != EXPECTED_VERSION:
                        raise ValueError("Unexpected application version.")
                    if info.get("DeviceReportURL"):
                        raise ValueError("IPA already has an endpoint configured.")
                    info["DeviceReportURL"] = endpoint
                    fmt = plistlib.FMT_BINARY if contents.startswith(b"bplist00") else plistlib.FMT_XML
                    contents = plistlib.dumps(info, fmt=fmt, sort_keys=False)
                result.writestr(entry, contents)
        if not found_plist:
            raise ValueError(f"Missing {PLIST_PATH}.")
        with zipfile.ZipFile(temporary) as check:
            info = plistlib.loads(check.read(PLIST_PATH))
            if info.get("DeviceReportURL") != endpoint or check.testzip() is not None:
                raise ValueError("Verification of the configured IPA failed.")
        os.replace(temporary, output)
    finally:
        if os.path.exists(temporary):
            os.remove(temporary)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path, required=True, help="Unsigned IPA from GitHub Actions.")
    parser.add_argument("--output", type=Path, required=True, help="Locally configured IPA for SideStore.")
    parser.add_argument("--endpoint", required=True, help="HTTPS receiver URL, ending /v1/report.")
    args = parser.parse_args()
    try:
        configure(args.input, args.output, args.endpoint)
    except (OSError, ValueError, plistlib.InvalidFile, zipfile.BadZipFile) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1
    print(f"IPA configured and verified: {args.output}")
    print(f"Version: {EXPECTED_VERSION}; Bundle ID: {EXPECTED_BUNDLE}")
    print("Endpoint is embedded only in this local unsigned IPA. SideStore must sign it.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
