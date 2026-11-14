#!/usr/bin/env python3
"""Fetch the pinned rebuilt MobileVLCKit binary; keep downloaded code out of Git."""
import hashlib
import plistlib
import shutil
import tarfile
import tempfile
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
VERSION = '3.7.3-no-zvbi'
SHA256 = 'a085d35016167144070ef5ed7aca446ac6101dd6c8e54d89e838c60be38ecc83'
URL = 'https://github.com/ilovefood2/xplayer/releases/download/ios-v4.11.146/MobileVLCKit-3.7.3-no-zvbi.tar.xz'
DESTINATION = ROOT / 'Vendor' / 'MobileVLCKit-NoZVBI'
ARCHIVE = ROOT / 'build' / 'dependencies' / f'MobileVLCKit-{VERSION}.tar.xz'

if not DESTINATION.exists():
    ARCHIVE.parent.mkdir(parents=True, exist_ok=True)
    if not ARCHIVE.exists():
        partial = ARCHIVE.with_suffix('.download')
        try:
            with urllib.request.urlopen(URL, timeout=120) as source, partial.open('wb') as target:
                shutil.copyfileobj(source, target)
            partial.replace(ARCHIVE)
        finally:
            partial.unlink(missing_ok=True)
    with ARCHIVE.open('rb') as source:
        digest = hashlib.file_digest(source, 'sha256').hexdigest()
    if digest != SHA256:
        raise SystemExit(f'MobileVLCKit checksum mismatch. Remove {ARCHIVE} and retry.')
    DESTINATION.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=DESTINATION.parent) as staging:
        with tarfile.open(ARCHIVE) as archive:
            members = [member for member in archive.getmembers() if
                       member.name.startswith('MobileVLCKit-binary/MobileVLCKit.xcframework/') or
                       member.name == 'MobileVLCKit-binary/COPYING.txt']
            archive.extractall(staging, members=members, filter='data')
        extracted = Path(staging) / 'MobileVLCKit-binary'
        (extracted / '.archive-sha256').write_text(SHA256)
        extracted.rename(DESTINATION)

if (DESTINATION / '.archive-sha256').read_text() != SHA256:
    raise SystemExit('The installed MobileVLCKit version does not match the pinned archive.')
framework = DESTINATION / 'MobileVLCKit.xcframework'
info = plistlib.loads((framework / 'Info.plist').read_bytes())
slices = info['AvailableLibraries']
assert any(s.get('SupportedPlatformVariant') == 'simulator' and 'arm64' in s['SupportedArchitectures'] for s in slices)
assert any(s['SupportedPlatform'] == 'ios' and 'SupportedPlatformVariant' not in s and 'arm64' in s['SupportedArchitectures'] for s in slices)
assert (DESTINATION / 'COPYING.txt').stat().st_size > 1000
print(f'Verified MobileVLCKit {VERSION}: device + Apple Silicon simulator slices and license present.')
