# xplayer Support

## Import videos and folders

Open Library and open the … menu, then choose Import Videos or Import Folder. Choose files from
the iOS Files picker. Folder imports preserve nested folders. Imports copy
files, so enough free device storage is needed. Keep xplayer open until the
copy finishes. Duplicate names receive a numbered suffix.

You can also use Files or Finder file sharing to copy videos into
On My iPhone or On My iPad → xplayer → Videos. Pull down in Library to refresh.

## Supported videos

xplayer supports MP4, M4V, and MOV containers with codecs supported by your
device's Apple media player, typically H.264 and HEVC. A filename extension
alone does not guarantee its codec is supported. MKV (Matroska), AVI, and WebM files use the
bundled MobileVLCKit decoder. Damaged files, unsupported codecs, and protected/DRM
content may not play. DRM-protected playback is not supported.

Import MKV, AVI, or WebM files or folders through Files, or copy them into xplayer → Videos.
These videos work with playlists, favorites, moves, and batch deletion. Their
player has Play/Pause and a seek slider for seekable files; system volume buttons
control audio. Video decoding may consume more battery than native playback.

AVI and WebM compatibility checks include MPEG-4 Part 2/MP3 in AVI and
VP8/Vorbis, VP9/Opus, and AV1/Opus in WebM. These checks do not cover every
codec/profile, damaged file, high-resolution stream, or subtitle combination.

## Folders and playlists

Use … → New Folder to create a folder. Long-press a file or folder to move it
or add its videos to a playlist. Folders can also be renamed. In Playlists,
create a list, add videos from any folder, and use Edit to reorder or remove
entries. Play All advances to the next video automatically.

Moving files within xplayer updates playlists and favorites. If you move or rename a file
outside the app, remove its missing playlist entry and add the file again.
Removing a playlist entry does not delete the video.

## Select and delete multiple items

Tap Select in Library or a folder, tap the files or folders you want to remove,
and tap Delete Selected. Confirm Delete from Library to remove the local copies
and their playlist/favorite references. Selected folders include all their
contents. Cancel keeps the files. Select All applies to the visible results;
changing the search clears the selection. Original imported files are unchanged.

## Favorites

Long-press a video and choose Add to Favorites. Open the Favorites tab to play
individual favorites or Play All. Long-press a favorite or swipe it to remove
it from Favorites without deleting the video. Favorites persist on your device.

## Network videos

In Library, tap … → Open Network Video, enter a direct HTTP or HTTPS video URL,
and tap Play. MP4, M4V, MOV, MKV, AVI, WebM, and HLS (.m3u8) streams are supported subject to their codecs.
MKV, AVI, and WebM use MobileVLCKit; other links start with Apple playback and can fall back
to MobileVLCKit if the system player cannot open them. Website pages, SMB shares, embedded username/password
URLs, and DRM-protected streams are not supported. Links are not saved or imported.
The server receives your IP address and URL; HTTP is unencrypted, so prefer HTTPS.

For a server on your Wi-Fi network, allow Local Network access when iOS asks.
If playback fails, check the address, server access, network connection, and codec.
An expired signed link needs a fresh URL. If local access was denied, enable it
for xplayer in Settings. Network playback requires a reachable server.

## Playback

Tap a video to play it. Playback controls hide automatically while playing;
tap the video to show them again. VLC playback controls stay visible while paused,
seeking, showing an error, or using VoiceOver. Apple playback retains its native
transport controls; the app's title and queue buttons also hide during playback.
Previous and Next appear when playing more than one video. The × button
closes playback. Backgrounding
the app pauses playback. If audio plays on another device, check the system
audio output or any device-mirroring session on your Mac.

## Help and appearance

Library → … → Help & About contains the full guide, support, privacy, and
licenses. Library, Favorites, and Playlists follow your device's light/dark
appearance. The video player stays dark for viewing.

## Report a problem

Email a@ikel.ca or open https://github.com/ilovefood2/xplayer/issues and describe the problem,
your device model, iOS version, app version, and steps to reproduce it.
For playback issues, include the container and codec if known. Do not attach
private videos or personal information to a public issue. The application
does not send logs or media automatically.
