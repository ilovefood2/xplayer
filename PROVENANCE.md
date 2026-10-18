# Source and licensing boundary

xplayer is a standalone native iPhone/iPad application. Its application code,
tests, build configuration, and new artwork are offered under the MIT license
in this directory. The project owner authorized this independent release on
2026-10-18. This grant does not relicense any upstream SPlayer work.

## Development record

The initial five Swift source files were written for a native SwiftUI/AVKit
application in commit `7aec85288625af418fa799a79c8ba57229a881d0` of
https://github.com/ilovefood2/splayerx. The implementation uses Apple APIs for
file picking, local file storage, SwiftUI views, and AVKit playback. It does not
compile, translate, or call the upstream Electron/Vue desktop player or SPlayer
subtitle implementation. Starting with 4.11.136, a separately downloaded,
unmodified VideoLAN MobileVLCKit framework supplies MKV decoding under its own
LGPL license. No decoder code is copied from the SPlayer desktop project;
THIRD_PARTY_NOTICES.md records the pinned binary and corresponding sources.

Filesystem fixes are recorded in `afd66ae2a` and `6560983d3` in that repository.
The source snapshot before the xplayer release preparation is `6560983d3`.
These public commits preserve the development history without importing the
desktop repository or historical artwork into this standalone project.

The first development build temporarily copied the upstream SPlayer icon. It
was replaced before this extraction. The current icon was generated without a
reference image; see AppIcon.md for the prompt and provenance. The upstream
icon is not included in xplayer's source tree or application bundle. The test
video is a synthetic FFmpeg test pattern, not a third-party film or recording,
and is included in the test bundle only. The HLS fixture `stream.ts` is eight
repetitions of that same pattern, remuxed with
`ffmpeg -stream_loop 7 -i clip.mp4 -c copy -f mpegts stream.ts`.
The MKV test fixture is generated from FFmpeg's testsrc2 pattern and sine tone,
encoded as H.264/AAC, and contains no personal or third-party media. The controls
tests repeat this pattern to 18 seconds and remux a copy to MP4 so visibility
and pause behavior can be checked without the fixture ending early. The FFmpeg
command-line executable is only a fixture-generation tool; codec code inside
MobileVLCKit remains governed by its upstream licenses.

## What is not relicensed

The original https://github.com/chiflix/splayerx project and its desktop fork
remain governed by their existing GPL-3.0-or-later license and notices. Their
brand, logos, implementations, and third-party dependencies are not licensed
to others by this project's MIT grant. Earlier GPL grants, where applicable,
are not revoked by the separate MIT grant for independently created material.

The same feature idea, a new programming language, or moving a file alone does
not establish independence. Do not import upstream implementations or artwork
without reviewing the actual license and distribution requirements. New
contributions must be original or accompanied by compatible permissions and
attribution. Record any new dependency in THIRD_PARTY_NOTICES.md.

## Remaining external checks

The name xplayer is user-selected. Similar names exist in public app listings;
this document does not establish trademark clearance or App Store name
availability. Apple review and any professional legal opinion remain separate
from the source/build checks in this project.

## Additional format test fixtures

The AVI and WebM fixtures added in 4.11.139 are six-second FFmpeg testsrc2 color
patterns with generated sine audio, not recordings or third-party media:
clip.avi uses MPEG-4 Part 2 with an XVID tag and MP3 audio; clip.webm uses VP8
and Vorbis; vp9.webm uses VP9 and Opus; av1.webm uses AV1 and Opus. Encoding tools
are not shipped in the app. AVI/WebM playback uses the same pinned, unmodified
MobileVLCKit framework introduced for MKV; no additional runtime dependency
or artwork from the SPlayer desktop project was imported.

The Finder-sharing regression fixtures finder.ts and finder.m2ts are remuxes
of the same synthetic clip: H.264/AAC in MPEG-TS and H.264/AC-3 in M2TS.
No personal video is included in these fixtures or the application bundle.

The seek.mp4 and seek.mkv gesture/speed fixtures are 90-second loops/remuxes of
the existing synthetic controls.mp4 test pattern. They ship in test bundles only.
