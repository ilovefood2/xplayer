# MobileVLCKit sources and rebuilding

xplayer uses the official **MobileVLCKit 3.7.3** dynamic XCFramework. The app's
MIT license does not replace the licenses of MobileVLCKit, libVLC, or their
dependencies. The app includes the LGPL text and component notices in Help &
About. Source versions, archive checksums, license files, and binary inventory
evidence are recorded in `metadata/dependencies/mobilevlckit-3.7.3.json`.

## Sources for xplayer 4.11.143

The release publishes two separate source downloads:

- [App source and build configuration](https://github.com/ilovefood2/xplayer/archive/refs/tags/ios-v4.11.143.tar.gz), tag `ios-v4.11.143`.
- [Decoder and dependency sources](https://github.com/ilovefood2/xplayer/releases/download/ios-v4.11.143/xplayer-decoder-sources-3.7.3.tar.xz) and its [SHA-256 checksum](https://github.com/ilovefood2/xplayer/releases/download/ios-v4.11.143/xplayer-decoder-sources-3.7.3.tar.xz.sha256).

The decoder package contains:

- VLCKit commit `319ed2c0724e3d4c4d34889a62fef1ae269491bc` (tag 3.7.3), including
  its build scripts and all 47 libVLC patches.
- VLC base commit `79128878ddb2c280bbb6c89c76a46b31a80ade1c` with those patches
  already applied, at `VLCKit/libvlc/vlc`. Its resulting Git tree is
  `651b6d3241f7631684f79310f1f44ad2a9c73969`.
- Complete, unmodified source archives for the inventoried bundled dependencies
  in `VLCKit/libvlc/vlc/contrib/tarballs`. Their SHA-512 checksums are checked
  against the patched VLC recipes; SHA-256 checksums are recorded as well.
- All VLC contrib recipes and patches, original source/license files, these
  instructions, and `SOURCE-MANIFEST.json` with a checksum for every packaged
  file. A descriptive `src/revision.txt` is added so VLC can build without Git
  metadata; it does not change decoder behavior.

Check the downloaded package before extracting it:

```sh
shasum -a 256 -c xplayer-decoder-sources-3.7.3.tar.xz.sha256
python3 scripts/package-corresponding-source.py --verify xplayer-decoder-sources-3.7.3.tar.xz
tar -xf xplayer-decoder-sources-3.7.3.tar.xz
```

The verification command is in the app source download. It checks the entire
file inventory and every dependency archive without extracting files. Git
histories, credentials, provisioning profiles, personal media, and build
products are excluded from the source package.

## Build the app with the official decoder

1. Install Xcode and Python 3.12 or newer. A device build also needs your own
   Apple signing identity; a simulator build does not.
2. Run `python3 scripts/fetch-vlckit.py` from the app source directory. It fetches
   the pinned official binary and verifies its SHA-256, supported slices, and
   bundled license.
3. Run `scripts/build.sh build`, or open `XPlayer.xcodeproj`. `project.yml` is the
   XcodeGen source of truth when regenerating the project.

The official binary archive is
https://download.videolan.org/pub/cocoapods/prod/MobileVLCKit-3.7.3-319ed2c0-79128878.tar.xz,
with SHA-256
`0d04059906962ddc9a7bd1ebaa12e1f9ae85eb2466116a97a2f46886dd27a0a9`.
The corresponding registry specification is
https://trunk.cocoapods.org/api/v1/pods/MobileVLCKit/specs/3.7.3.

## Modify and relink the decoder

Install the build tools listed in the included VLCKit `README.md`, including
Xcode's command-line tools. Work in a path without spaces. From the extracted
decoder package, make your library changes and run:

```sh
cd xplayer-decoder-sources-3.7.3/VLCKit
./buildMobileVLCKit.sh -n -f -a aarch64
```

`-n` preserves the already patched VLC checkout instead of fetching and resetting
it. It is not a guarantee of an offline build: upstream's build-tool setup and
any dependencies selected by a different platform/toolchain can still need
downloads. The supplied contrib archives retain the filenames expected by the
upstream fetch/checksum rules. `-f -a aarch64` selects the device and Apple
Silicon simulator dynamic framework, produced at `build/MobileVLCKit.xcframework`.
Other architectures are available through the upstream script's `-a` option.

In the app source, change the `framework` dependency in `project.yml` to the
resulting XCFramework path and run `xcodegen generate`. Build the generated
project directly, rather than invoking the helper that fetches the official
binary. For example, an unsigned simulator build is:

```sh
xcodebuild -project XPlayer.xcodeproj -scheme XPlayer \
  -configuration Debug -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build/modified-decoder CODE_SIGNING_ALLOWED=NO build
```

For installation on your own device, select your Apple development team in
Xcode and run the application. No original developer signing credentials are
required. Retain the dependency license notices and rights to modify and
reverse-engineer library use for debugging modifications.

The app was built against the official binary. Source revisions, patch
application, source-archive checksums, and package contents have been checked.
The build paths and upstream command-line options above were inspected; the
entire decoder and an app using a modified decoder were **not rebuilt**.
Byte-for-byte reproduction of VideoLAN's binary is not claimed.

## Recreate the decoder source package

Use exact VLCKit and VLC Git checkouts at the revisions above. Apply all
`VLCKit/libvlc/patches/*.patch` files to the VLC base, in filename order, with
`git am`. Download the source archives listed in the dependency manifest,
preserving each `source.filename`; URLs, SHA-512, and SHA-256 are recorded there.
Then run from the app source directory:

```sh
python3 scripts/package-corresponding-source.py \
  --vlckit /path/to/vlckit-checkout \
  --vlc /path/to/patched-vlc-checkout \
  --contrib /path/to/contrib-archives
```

The packager verifies both complete Git tree identities and every dependency
archive before writing `build/corresponding-source/xplayer-decoder-sources-3.7.3.tar.xz`.
It uses Git object contents, normalized archive metadata, and a fixed order,
so the same inputs produce the same archive and checksum. Existing output is
not overwritten. Dependency sources and build products stay outside Git.
