# Third-party notices

## MobileVLCKit 3.7.3 / libVLC

xplayer includes a dynamic framework rebuilt from VideoLAN MobileVLCKit 3.7.3
without ZVBI to decode Matroska (MKV), AVI, WebM, and MPEG-TS videos. Copyright © VideoLAN and the VLCKit,
VLC, and contributing codec-library authors. MobileVLCKit and libVLC are
licensed under the GNU Lesser General Public License, version 2.1 or later.
Their code is not relicensed under xplayer's MIT license.

The complete LGPL 2.1 text is bundled as MobileVLCKit-LGPL.txt and is readable
in Library → … → Help & About → MobileVLCKit License. You may modify and redistribute these libraries
under their licenses, and reverse-engineer this application's use of them for
debugging your modifications. xplayer's complete source and build configuration
are available under MIT so you can rebuild it against a modified library.
These open-source permissions, including modification and reverse engineering
for debugging library modifications, are not limited by other app terms.

Source for xplayer 4.11.146:
https://github.com/ilovefood2/xplayer/tree/ios-v4.11.146

Downloadable application source:
https://github.com/ilovefood2/xplayer/archive/refs/tags/ios-v4.11.146.tar.gz

Matching decoder source, patches, dependency archives, and rebuild instructions:
https://github.com/ilovefood2/xplayer/releases/download/ios-v4.11.146/xplayer-decoder-sources-3.7.3.tar.xz

Release binary (rebuilt without ZVBI):
https://github.com/ilovefood2/xplayer/releases/download/ios-v4.11.146/MobileVLCKit-3.7.3-no-zvbi.tar.xz

SHA-256: a085d35016167144070ef5ed7aca446ac6101dd6c8e54d89e838c60be38ecc83

The app source includes the decoder rebuild patch at metadata/dependencies/mobilevlckit-no-zvbi.patch.

Corresponding VLCKit source and build scripts (tag 3.7.3, commit 319ed2c0):
https://code.videolan.org/videolan/VLCKit/-/tree/3.7.3

libVLC source used by that release (commit 79128878):
https://code.videolan.org/videolan/vlc/-/tree/79128878

The framework also incorporates FFmpeg and other libraries with their own
licenses. The complete collected notices are bundled as ThirdPartyLicenses.txt,
readable offline in Help & About → Third-Party Licenses, and published at:
https://ilovefood2.github.io/xplayer/license.html

The release source contains a versioned dependency inventory with upstream
archive hashes and verbatim license files in metadata/dependencies. It also
contains the patches, build recipes, and instructions needed to rebuild and
relink the decoder. See docs/dependency-build.md at the release source link
above. The source package includes the original notices; the application's
MIT license does not replace any dependency license or grant codec patent rights.

This product includes software developed by Niels Provos. Portions of this
software are based in part on the work of the FreeType Team (https://freetype.org/).
This software is based in part on the work of the Independent JPEG Group.

## Apple resources and development tools

The application uses Apple's system frameworks and SF Symbols under the
applicable Apple SDK terms. These resources are not covered by xplayer's MIT
license. The app has no advertising or analytics SDK.

The app icon is newly generated artwork; AppIcon.md records its provenance.
No original SPlayer artwork or desktop runtime is included.

XcodeGen, Xcode, Python, and the FFmpeg command-line tool used to create synthetic
test fixtures are development tools, not separately shipped executables. The
codec implementation bundled inside MobileVLCKit retains its upstream licenses.
