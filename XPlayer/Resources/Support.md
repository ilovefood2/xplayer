# xplayer Support

## Import videos and folders

Open Library and open the … menu, then choose Import Videos or Import Folder. Choose files from
the iOS Files picker. Folder imports preserve nested folders. Imports copy
files, so enough free device storage is needed. Keep xplayer open until the
copy finishes. Duplicate names receive a numbered suffix.

In Finder, select your iPhone or iPad → Files → xplayer and drag videos or
folders into the app. In Files, use On My iPhone or On My iPad → xplayer.
These transfers appear directly in Library. Wait for the transfer to finish,
then reopen xplayer or pull down in Library to refresh if it is already open.

Videos imported with earlier versions remain in the Videos folder. Open that
folder in Library to find them; their playlists and favorites are preserved.
The update does not move your video files. The system-managed Inbox folder is
hidden; use Import Videos or Import Folder to copy content from it.

## Supported videos

xplayer supports MP4, M4V, and MOV containers with codecs supported by your
device's Apple media player, typically H.264 and HEVC. A filename extension
alone does not guarantee its codec is supported. MKV (Matroska), AVI, WebM, and MPEG-TS (.ts, .mts, .m2ts) files use the
bundled MobileVLCKit decoder. Damaged files, unsupported codecs, and protected/DRM
content may not play. DRM-protected playback is not supported.

Import these files or folders through Files, or copy them into xplayer using Finder.
These videos work with playlists, favorites, moves, and batch deletion. Their
player has Play/Pause and a seek slider for seekable files; system volume buttons
control audio. Video decoding may consume more battery than native playback.

AVI and WebM compatibility checks include MPEG-4 Part 2/MP3 in AVI and
VP8/Vorbis, VP9/Opus, and AV1/Opus in WebM. These checks do not cover every
codec/profile, damaged file, high-resolution stream, or subtitle combination.

## Playback controls

Double-tap the left half of the video to go back 15 seconds, or the right half
to go forward 15 seconds. A single tap shows or hides controls. Seeking stays
within the video's available timeline; live streams may not allow seeking.

Tap the speed button (initially 1×) in the upper-right corner to open a slider.
Choose 0.25× to 2× in quarter-speed steps. Changing speed keeps a paused video
paused, and the selected speed carries over to the next video. These controls
work with native and MobileVLCKit playback. VoiceOver users can also choose the
15-second skip actions on the speed button.

## Folders and playlists

Use … → New Folder to create a folder. Long-press a file or folder to move it,
rename it, share a video, or add its videos to a playlist. Renaming a video keeps
its file extension and renames its subtitle files too. In Playlists,
create a list, add videos from any folder, and use Edit to reorder or remove
entries. Play All advances to the next video automatically.

Moving files within xplayer updates playlists and favorites. If you move or rename a file
outside the app, remove its missing playlist entry and add the file again.
Removing a playlist entry does not delete the video.

## Sorting, thumbnails, and progress

Library rows show a thumbnail, duration, and size for each video. Use … →
Sort By to order by name, date added, date modified, or size, in either
direction; folders stay at the top. A bar under the thumbnail shows how much
of a video you have watched.

## Resume, subtitles, and audio

xplayer remembers where you stopped each library video and continues from
there; tap Start Over in the banner to begin again. Videos you finished, or
stopped in the first few seconds, start from the beginning.

Subtitle files with the same name as the video (Movie.srt, Movie.en.srt,
Movie.zh.ass) are shown automatically. SRT, WebVTT, ASS, and SSA are supported,
including Chinese (GB18030/Big5) and Japanese (Shift JIS) files. Import subtitle
files together with their videos, or copy them into the same folder. While
playing, tap the … button to choose subtitles, switch the audio language, set
Repeat (All or One), turn on Shuffle, or share the video.

## Background, Picture in Picture, and AirPlay

By default, audio keeps playing when you leave xplayer or lock the screen; turn
this off in Help & About → Play Audio in Background. Apple-format videos (MP4,
M4V, MOV) can continue in Picture in Picture, and the lock screen and Control
Center show play/pause, skip, and the timeline. Apple-format videos support
AirPlay from the player controls. For MKV, AVI, WebM, and MPEG-TS, the AirPlay
button sends audio to AirPlay speakers; use Screen Mirroring to show the video.

## Network shares

Open the Network tab and tap + → Add Share. Choose SMB for shared folders on a
Mac, Windows PC, or NAS (for example nas.local or smb://192.168.1.10/Videos),
or WebDAV for an HTTP or HTTPS share. Enter a user name and password, or leave
them blank for guest access; use DOMAIN\user for a Windows domain. Browse the
folders and tap a video to play it; playback continues through the folder.
Passwords are stored in this device's Keychain. Videos play directly from the
share and are not copied into your library. Allow Local Network access when iOS
asks. If a share does not open, check its address, sign-in, and that your
device is on the same network.

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
and tap Play. MP4, M4V, MOV, MKV, AVI, WebM, MPEG-TS, and HLS (.m3u8) streams are supported subject to their codecs.
MKV, AVI, WebM, and MPEG-TS use MobileVLCKit; other links start with Apple playback and can fall back
to MobileVLCKit if the system player cannot open them. Website pages, embedded username/password
URLs, and DRM-protected streams are not supported; use the Network tab for shares that need a password.
Your 20 most recent links are listed for quick access and kept only on this device; swipe one to
remove it, or tap Clear Recent Links. The server receives your IP address and URL; HTTP is
unencrypted, so prefer HTTPS.

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
closes playback. Audio continues in the background unless you turn that off in
Help & About. If audio plays on another device, check the system
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
