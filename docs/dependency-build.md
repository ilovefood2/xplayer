# MobileVLCKit dependency and rebuilding

xplayer 4.11.136 uses the official **MobileVLCKit 3.7.3** dynamic XCFramework.
No SPlayer desktop code or assets are used. The application source remains MIT;
MobileVLCKit, libVLC, and its codec dependencies keep their original licenses.
See THIRD_PARTY_NOTICES.md and XPlayer/Resources/MobileVLCKit-LGPL.txt.

## Reproduce the application build

1. Install Xcode and Python 3.12 or newer; choose your signing team for a device.
2. Run `python3 scripts/fetch-vlckit.py`. This downloads the official archive,
   checks SHA-256 against the CocoaPods 3.7.3 specification, safely extracts it,
   and checks for device and arm64-simulator slices plus the license.
3. Run `scripts/build.sh build`, or open XPlayer.xcodeproj. `project.yml` is the
   XcodeGen source of truth if regenerating the project.

The archive checksum is
`0d04059906962ddc9a7bd1ebaa12e1f9ae85eb2466116a97a2f46886dd27a0a9`.
The binary source is
https://download.videolan.org/pub/cocoapods/prod/MobileVLCKit-3.7.3-319ed2c0-79128878.tar.xz
and the registry specification is
https://trunk.cocoapods.org/api/v1/pods/MobileVLCKit/specs/3.7.3.
Downloaded frameworks and archives are ignored and must not be committed.

## Build and relink a modified decoder

The complete app source is available at https://github.com/ilovefood2/xplayer.
VLCKit source, patches and build instructions are available at
https://code.videolan.org/videolan/VLCKit/-/tree/3.7.3.
Its buildMobileVLCKit.sh pins libVLC commit `79128878`, available at
https://code.videolan.org/videolan/vlc/-/tree/79128878.
The libVLC contrib recipes identify dependency sources, checksums and licenses.

Clone VLCKit, check out tag `3.7.3` (commit prefix `319ed2c0`), and follow its
README's build requirements. `./buildMobileVLCKit.sh -f -a aarch64` requests a
dynamic framework for device and simulator; the script assembles
`build/MobileVLCKit.xcframework`. Building upstream from source is separate from
the binary-based xplayer checks and was not performed for this change.

After making your library changes, point the framework dependency in
project.yml to your resulting XCFramework and run `xcodegen generate`. Build
the resulting Xcode project directly with Xcode/xcodebuild (the convenience
script fetches the official pinned binary). Sign the app with your own Apple
team to install it on your device. This source/build path permits relinking
without relying on the original developer's private signing credentials.

Do not remove library notices or restrict modification/reverse engineering
rights granted by the LGPL. App Store SDK privacy, export and distribution
review remains a separate release task.
