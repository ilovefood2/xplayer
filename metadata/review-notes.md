# App Review notes

No login, demo account, subscription, paid content, or special hardware is
required. This is a local and network video player; it does not provide a media catalog,
download videos from websites, or share user content with other users.

1. Install the app and open Library.
2. Tap … → Import Videos. Choose a small H.264 MP4 file in Files.
3. Confirm it appears in Library and tap it to play. The × button closes playback.
4. Tap … → Import Folder to import a folder containing MP4/M4V/MOV videos.
   The original folder hierarchy is preserved in local copies.
5. Long-press a file or folder to move it or add it to a playlist.
6. In Playlists, create a list and add videos from different folders. Edit
   reorders or removes entries; Play All advances automatically.
7. Library → … → Help & About contains offline privacy, support, MIT license, and third-party notices,
   plus public privacy/support links.

Supported containers are MP4, M4V, MOV, MKV, AVI, and WebM. MKV, AVI, and WebM use MobileVLCKit;
other supported formats use native AVKit playback when possible. Backgrounding pauses playback. File access is granted through the
system document picker; the app does not request Photo Library, camera,
microphone, location, contacts, or tracking permissions. Local Network permission
is requested by iOS when connecting to a user-entered local server URL.

The synthetic `clip.mp4` in XPlayerTests/Fixtures may be supplied separately
as a review attachment. It is a generated color-bar pattern with no personal
or copyrighted media and is not bundled in the production app.

Before submitting, the account holder must provide real review contact details,
complete Apple's age-rating/export-compliance forms, and confirm the final
store name and rights. This file is a review draft, not a record of approval.

## New in 4.11.135

Library → Select supports multiple files/folders and a confirmation before
local deletion. Long-press a video → Add to Favorites, then use Favorites.
Library → … → Open Network Video accepts direct HTTP/HTTPS media and HLS links.
No server discovery, account login, URL history, or network downloads into the
library are provided. A real reachable media URL is needed for network review.

The AVFoundation media-only ATS exception supports user-entered HTTP media
servers with unknown hostnames. The UI explains that HTTP is unencrypted and
recommends HTTPS. General-purpose arbitrary network loads remain disabled.
This exception needs Apple's review; local validation does not establish approval.

Apple documents the media-specific exception at
https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity/nsallowsarbitraryloadsformedia.

## MKV support in 4.11.136

Import a Matroska (.mkv) file using Files, play it from Library or a playlist,
and use Play/Pause or the seek slider. A synthetic H.264/AAC clip.mkv is in the
test fixtures, not the shipped app. Direct network MKV URLs are supported too.
MobileVLCKit 3.7.3 is embedded as an unmodified dynamic framework. Its license
is readable offline in About, and source/build links are in Third-Party Notices.
Review SDK privacy requirements and codec/export obligations before submission;
build/test success is not App Store approval.

## AVI and WebM support in 4.11.139

AVI and WebM can be imported through Files or folder imports and opened using
file sharing or direct network URLs. They use the existing MobileVLCKit decoder
and retain playback controls, playlists, and favorites. The framework version
and license are unchanged; no DRM integration was added. Codec/patent and
App Store distribution review remains separate from these functionality checks.
