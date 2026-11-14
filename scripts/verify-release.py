#!/usr/bin/env python3
"""Local release checks; does not claim trademark clearance or Apple approval."""
import argparse
import json
import plistlib
import struct
import subprocess
import sys
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--app', type=Path)
parser.add_argument('--check-urls', action='store_true')
args = parser.parse_args()
errors = []

def check(condition, message):
    if not condition:
        errors.append(message)

package = json.loads((ROOT / 'package.json').read_text())
source = ROOT / 'XPlayer'
info = plistlib.loads((source / 'Info.plist').read_bytes())
privacy = plistlib.loads((source / 'PrivacyInfo.xcprivacy').read_bytes())
check(package['license'] == 'MIT', 'Standalone package license is not MIT.')
check(info.get('CFBundleDisplayName') == 'xplayer', 'Display name must be xplayer.')
check(info.get('ITSAppUsesNonExemptEncryption') is False, 'Review the export-compliance declaration.')
check(not info.get('NSAppTransportSecurity', {}).get('NSAllowsArbitraryLoads'), 'Unrestricted network transport is enabled.')
check(privacy.get('NSPrivacyTracking') is False, 'Unexpected tracking declaration.')
check(privacy.get('NSPrivacyCollectedDataTypes') == [], 'Review data collection before release.')
reasons = {item['NSPrivacyAccessedAPIType']: set(item['NSPrivacyAccessedAPITypeReasons']) for item in privacy['NSPrivacyAccessedAPITypes']}
check(reasons.get('NSPrivacyAccessedAPICategoryFileTimestamp') == {'C617.1', '3B52.1'}, 'File metadata reason declarations do not match the audited use.')
# MobileVLCKit has no privacy manifest of its own; its binary calls mach_absolute_time,
# fstatfs, and NSUserDefaults, which App Store Connect rejects without a declared reason.
check(reasons.get('NSPrivacyAccessedAPICategorySystemBootTime') == {'35F9.1'}, 'Declare the decoder clock (system boot time) reason.')
check(reasons.get('NSPrivacyAccessedAPICategoryDiskSpace') == {'E174.1'}, 'Declare the decoder file-system (disk space) reason.')
check(reasons.get('NSPrivacyAccessedAPICategoryUserDefaults') == {'CA92.1'}, 'Declare the decoder settings (UserDefaults) reason.')
check((ROOT / 'LICENSE').read_bytes() == (source / 'Resources/License.txt').read_bytes(), 'Bundled MIT license differs from the source license.')
check((ROOT / 'THIRD_PARTY_NOTICES.md').read_bytes() == (source / 'Resources/ThirdPartyNotices.md').read_bytes(), 'Bundled third-party notices differ.')
notices = subprocess.run([sys.executable, str(ROOT / 'metadata/dependencies/collect-licenses.py'), '--check'], capture_output=True, text=True)
check(notices.returncode == 0, 'Dependency notice integrity check failed: ' + notices.stderr.strip())
check(f'ios-v{package["version"]}' in (ROOT / 'THIRD_PARTY_NOTICES.md').read_text(), 'Source links do not identify this release.')
for name in ['PrivacyPolicy.md', 'Support.md', 'License.txt', 'ThirdPartyNotices.md', 'MobileVLCKit-LGPL.txt', 'ThirdPartyLicenses.txt']:
    text = (source / 'Resources' / name).read_text()
    check(len(text) > 100, f'Missing or incomplete document: {name}')
    if name != 'ThirdPartyLicenses.txt':
        check(not any(marker in text for marker in ['TODO', 'example.com', '<your', 'TBD']), f'Placeholder in public document: {name}')
for name, limit in [('name', 30), ('subtitle', 30), ('keywords', 100), ('description', 4000)]:
    text = (ROOT / 'metadata/en-US' / (name + '.txt')).read_text().strip()
    check(0 < len(text) <= limit, f'Store metadata {name} exceeds {limit} characters.')
project = (ROOT / 'project.yml').read_text()
check(f'MARKETING_VERSION: "{package["version"]}"' in project, 'Project and package versions differ.')
check('PRODUCT_BUNDLE_IDENTIFIER: com.ilovefood2.xplayer' in project, 'Unexpected bundle identifier.')
check('SPlayer' not in project and '../' not in project, 'Project references legacy or external build sources.')
icon = (source / 'Assets.xcassets/AppIcon.appiconset/AppIcon.png').read_bytes()
check(icon[:8] == b'\x89PNG\r\n\x1a\n', 'App icon must be PNG.')
width, height, depth, color = struct.unpack('>IIBB', icon[16:26])
check((width, height, color) == (1024, 1024, 2), 'App icon must be an opaque RGB 1024-square PNG.')
check(not list(ROOT.glob('*.p12')) and not list(ROOT.glob('*.mobileprovision')), 'Signing secrets are present at the project root.')

if args.app:
    built = plistlib.loads((args.app / 'Info.plist').read_bytes())
    check(built.get('CFBundleIdentifier') == 'com.ilovefood2.xplayer', 'Built bundle identifier differs.')
    check(built.get('CFBundleDisplayName') == 'xplayer', 'Built display name differs.')
    check(built.get('CFBundleShortVersionString') == package['version'], 'Built application version differs.')
    for name in ['PrivacyInfo.xcprivacy', 'PrivacyPolicy.md', 'Support.md', 'License.txt', 'ThirdPartyNotices.md', 'MobileVLCKit-LGPL.txt', 'ThirdPartyLicenses.txt']:
        check((args.app / name).is_file(), f'Required resource absent from app: {name}')
    check(not any(list(args.app.rglob(pattern)) for pattern in ['*.mp4', '*.mkv', '*.ts', '*.avi', '*.webm', '*.mts', '*.m2ts']), 'Test media must not ship in the production app.')
    frameworks = args.app / 'Frameworks'
    check(frameworks.is_dir() and {p.name for p in frameworks.iterdir()} == {'MobileVLCKit.framework'}, 'Unexpected or missing bundled framework.')
    vlc_info = frameworks / 'MobileVLCKit.framework/Info.plist'
    if vlc_info.is_file():
        check(plistlib.loads(vlc_info.read_bytes()).get('CFBundleIdentifier') == 'org.videolan.mobilevlckit', 'Unexpected decoder bundle identifier.')
    check((args.app / 'MobileVLCKit-LGPL.txt').read_bytes() == (source / 'Resources/MobileVLCKit-LGPL.txt').read_bytes(), 'Decoder license differs from the bundled notice.')
    check((args.app / 'ThirdPartyLicenses.txt').read_bytes() == (source / 'Resources/ThirdPartyLicenses.txt').read_bytes(), 'Built dependency licenses differ from verified notices.')

if args.check_urls:
    metadata = json.loads((ROOT / 'metadata/app-privacy.json').read_text())
    urls = [(metadata['privacyPolicyURL'], 'privacy.html'), (metadata['supportURL'], 'support.html'),
            ('https://ilovefood2.github.io/xplayer/license.html', 'license.html')]
    for url, filename in urls:
        try:
            request = urllib.request.Request(url, headers={'User-Agent': 'xplayer-release-check'})
            with urllib.request.urlopen(request, timeout=20) as response:
                body = response.read().decode()
                local = ROOT / 'docs' / filename
                check(response.status == 200 and body.strip() == local.read_text().strip(), f'Public page does not match the bundled release: {url}')
        except Exception as error:
            errors.append(f'Public page unreachable: {url}: {error}')

if errors:
    print('\n'.join('FAIL: ' + error for error in errors), file=sys.stderr)
    sys.exit(1)
print('PASS: local source' + (' and app bundle' if args.app else '') + (' and public URLs' if args.check_urls else '') + ' checks. Apple review, name clearance, and account setup are separate.')
