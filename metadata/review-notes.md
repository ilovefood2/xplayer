# App Review notes

No login, demo account, subscription, paid content, or special hardware is
required. This is a local and network video player; it does not provide a media catalog,
download videos from websites, or share user content with other users.

1. Install the app and open Library.
2. Tap + → Import Videos. Choose a small H.264 MP4 file in Files.
3. Confirm it appears in Library and tap it to play. Done stops playback.
4. Tap + → Import Folder to import a folder containing MP4/M4V/MOV videos.
   The original folder hierarchy is preserved in local copies.
5. Long-press a file or folder to move it or add it to a playlist.
6. In Playlists, create a list and add videos from different folders. Edit
   reorders or removes entries; Play All advances automatically.
7. About contains offline privacy, support, MIT license, and third-party notices,
   plus public privacy/support links.

Supported containers are MP4, M4V, and MOV; the device's AVKit codec support
applies. Backgrounding pauses playback. File access is granted through the
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
Library → + → Open Network Video accepts direct HTTP/HTTPS media and HLS links.
No server discovery, account login, URL history, or network downloads into the
library are provided. A real reachable media URL is needed for network review.

The AVFoundation media-only ATS exception supports user-entered HTTP media
servers with unknown hostnames. The UI explains that HTTP is unencrypted and
recommends HTTPS. General-purpose arbitrary network loads remain disabled.
This exception needs Apple's review; local validation does not establish approval.

Apple documents the media-specific exception at
https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity/nsallowsarbitraryloadsformedia.
