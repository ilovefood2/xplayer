# Release preparation record

Prepared on 2026-10-18 for xplayer, bundle ID `com.ilovefood2.xplayer`.

## Implemented in this project

- Standalone native app, project, version, scripts, and MIT licensing boundary.
- Source/artwork provenance and notices; no upstream desktop code or original icon in the app.
- Offline privacy, help, and license screens under About.
- Privacy manifest: no tracking, no collected app data; file metadata reasons
  C617.1 (app container) and 3B52.1 (user-selected files).
- Only supported video types advertised to Files; remote URLs rejected.
- Import completion UI waits for the system picker to dismiss; cancellation
  does not report a successful import. Backgrounding pauses playback.
- Accurate format limitations, local-storage/delete behavior, and support guidance.
- Source-controlled store description, keywords, review notes, export settings,
  and static public policy/support pages generated from bundled documents.
- Build/archive scripts and local source/bundle/URL checks.

## Account-holder and external gates

These are not claims of completed Apple approval:

1. Paid Apple Developer membership is not active, as confirmed by the account
   holder on 2026-10-18. App Store distribution signing and submission remain blocked.
2. Create the App Store Connect app record and verify store-name availability.
   Similar XPlayer/X Player names already appear in public Canadian listings.
   The requested display name remains xplayer; trademark clearance is unresolved.
3. The account holder approved a@ikel.ca as the public support email on
   2026-10-18. The seller name will be determined by the enrolled Apple account.
4. Public policy/support URLs have been deployed and verified byte-for-byte
   against the current bundled-document website output. Recheck before upload.
5. Complete age-rating, pricing/availability, content-rights, and export-compliance
   forms using the actual app behavior. No custom/non-exempt encryption is used.
6. Supply actual review contact details in App Store Connect. Six screenshots
   are prepared under screenshots/en-US for 6.9-inch iPhone and 13-inch iPad;
   they use synthetic sample videos, not the user's private media.
7. Export with App Store distribution signing and run Apple's archive validation.
8. Obtain Apple review. Local checks do not guarantee acceptance or legal clearance.

The source/license audit supports an independent implementation; the scope and
limits are in PROVENANCE.md. Existing upstream GPL licenses are not changed.
If adding upstream code, third-party SDKs, codecs, cloud sync, analytics, ads,
accounts, or paid features, review licenses and privacy declarations again.

## Verification of 4.11.134

- iPhone 16 Pro Max simulator, iOS 26.5: 13 tests passed.
- iPad Pro 13-inch simulator, iPadOS 26.5: 13 tests passed.
- Physical iPhone 16 Pro Max, iOS 27.0.1: 11 core/resource tests passed.
- A fresh signed archive was built from the standalone repository. Bundle
  identity, version, documents, privacy manifest, and signing verification passed.
- xplayer 4.11.134 was installed and launched on the physical iPhone.
- App Store export was attempted; Apple rejected provisioning because the
  current team has no permission to create iOS App Store profiles and the
  account has no App Store Connect provider. No App Store submission occurred.
- Migration from the former development bundle could not proceed because
  that bundle was absent from the device when checked; the account holder
  confirmed manually uninstalling it. The migration stopped before copying
  or overwriting data. This is separate from the passing import
  and playlist tests; no claim of successful old-library recovery is made.

The local checks are reproducible with scripts/verify-release.py, the Xcode
test scheme, and scripts/build.sh. They do not replace Apple's server-side
validation or review, and do not certify trademark or legal clearance.

## Primary references checked

- https://developer.apple.com/app-store/review/guidelines/
- https://developer.apple.com/app-store/submitting/
- https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api
- https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitypereasons
- https://www.gnu.org/licenses/gpl-faq.en.html#ReleaseUnderGPLAndNF
- https://www.gnu.org/licenses/gpl-faq.en.html#MereAggregation

## Verification of 4.11.135

- Added multiple selection with confirmed batch deletion, persistent favorites,
  and direct HTTP/HTTPS video and HLS playback.
- Existing playlist arrays are read without modification and upgraded to the
  combined playlist/favorites metadata on the next successful write.
- Batch deletion stages selected files, updates metadata atomically, and restores
  the files if staging or metadata writing fails. Parent/child selections are
  deduplicated. Moves and deletion update favorite references too.
- Physical iPhone: all 18 core/resource/playback tests passed, including the
  aliased-container import regression and real loopback MP4/HLS playback.
- Fresh iPhone simulator and iPad simulator: all 22 core and UI tests passed on
  each. UI coverage includes deletion
  cancellation/confirmation, persistence, invalid URLs, and network failure UI.
- A fresh signed Release build passed bundle/resource validation and codesign
  verification. Device inventory confirms xplayer 4.11.135 (135) installed on the
  iPhone 16 Pro Max. Final automatic relaunch was blocked by the locked screen.
- Network URLs are not persisted. HTTP support uses the AVFoundation-only ATS
  exception; HTTPS is recommended. SMB, website extraction, and DRM are excluded.
- Updated public-site sources are in this branch's docs/. GitHub Pages previously
  served main/docs; deployment of these revised pages is not verified here.
  App Store submission still requires the existing account/name/privacy checks,
  updated screenshots, and review of the media transport exception.

## Verification of 4.11.136

- Added MKV importing/scanning and local/network playback through the official
  MobileVLCKit 3.7.3 dynamic framework. MP4/MOV/HLS retain native AVKit playback;
  network endpoints that native playback cannot open can fall back to VLCKit.
- The binary is fetched from VideoLAN with the CocoaPods-published SHA-256 pin,
  stays outside Git, and is embedded/signature-verified in the app. Full LGPL
  text, notices, source links, and rebuild/relink instructions are included.
- All 27 iPhone-simulator tests passed (22 core/resource + 5 UI). All 22 core
  tests passed on the physical iPhone. The iPad MKV playback UI test also passed.
- Tests exercise byte-preserving MKV folder import, decoded audio/video and
  displayed pictures, pause/seek, mixed MKV/MP4 queue transitions, network MKV
  with and without a filename extension, corrupt-media errors, and cleanup.
- iPhone and iPad playback screenshots were visually checked. Synthetic MKV
  fixtures use H.264/AAC; this is not exhaustive verification of every MKV codec,
  HDR mode, subtitle format, or damaged-file variant. DRM remains unsupported.
- A fresh signed Release app passed source/bundle checks and deep codesign
  verification. Version 4.11.136 (136) was installed and launched on the physical
  iPhone 16 Pro Max; device inventory confirmed the version. The app is ~99 MB.
- Upstream decoder compilation was not run. App Store SDK privacy, licensing,
  codec/export review and public-site deployment remain separate release checks.

## Verification of 4.11.137

- MKV transport controls, title, status bar, and playlist buttons hide after
  three seconds of playback. Tapping the video restores them; MKV also supports
  tapping again to hide them immediately. Controls remain visible while paused,
  scrubbing, showing an error, or using VoiceOver.
- Native AVKit retains its own transport controls and auto-hide behavior. A
  simultaneous tap observer restores the app's title and queue buttons without
  cancelling native control touches. The app's added controls hide during play.
- iPhone simulator hide/reveal checks passed for MKV and native playback,
  including MKV pause/resume and native paused-state visibility. The hidden MKV
  frame was visually checked.
- The iPad simulator passed 24 selected checks: all 22 core/resource tests plus
  both playback-control UI tests. Longer synthetic fixtures exercise visibility
  without the video ending before the controls can be tested.
- A fresh signed Release build passed source/bundle validation and deep signature
  verification. The initial physical run was blocked by the locked iPhone.
- Follow-up on October 18, 2026: both playback-control UI tests passed on the
  unlocked physical iPhone 16 Pro Max (MKV: 34.848 seconds; native: 25.687 seconds).
  They verified hiding, tap-to-reveal, and visibility while paused. The signed
  4.11.137 Release app was reinstalled after testing; the phone relocked before
  the final automatic launch, so it must be opened manually.
- VoiceOver behavior was preserved in code but not manually exercised with
  VoiceOver enabled. Live support-site deployment was not changed.

## Verification of 4.11.138

- Simplified navigation to Library, Favorites, and Playlists. Help & About is
  available in Library's … menu, with privacy and all bundled licenses retained.
- Removed the Library welcome card, persistent instructions, duplicate format
  captions, redundant list action rows, and single-video queue controls.
- Library, favorite, and playlist videos now share compact rows. Main screens
  use native light/dark appearance. MKV controls occupy one compact panel over
  the video; multi-video queues retain Previous/Next and controls still auto-hide.
- All 29 iPhone-simulator checks passed (22 core/resource and 7 UI), and all 7
  iPad UI checks passed. They cover import/library persistence, selection/deletion,
  playlist navigation, moved Help access, network playback, MKV, and auto-hide.
- Populated light-mode iPhone and dark-mode iPad screens and the new MKV panel
  were visually reviewed. QA screenshots use synthetic media only and are kept
  outside Git in build/ui138/screenshots/.
- The fresh signed Release app passed source/bundle and deep codesign validation.
  Device inventory confirms 4.11.138 (138) installed on the physical iPhone.
- Follow-up on October 18, 2026: all three selected UI checks passed on the
  unlocked iPhone 16 Pro Max: main-screen layout/navigation, MKV controls, and
  Help/privacy/license navigation. Captured Library, Favorites, and Playlists
  layouts were visually reviewed; private device screenshots remain local.
  The signed Release app was restored and successfully launched after testing.
- Library data structures and persistence were not changed. App Store screenshots
  and live support-site publication remain separate release tasks.

## Verification of 4.11.139

- AVI and WebM are accepted by the Files picker, document-type registration,
  library scan, and folder imports. Local and network playback routes these
  containers through the existing MobileVLCKit 3.7.3 framework.
- Synthetic fixtures verified MPEG-4 Part 2/MP3 in AVI, VP8/Vorbis in WebM,
  VP9/Opus in WebM, and AV1/Opus in WebM. Tests check decoded audio/video and
  displayed pictures, seeking, automatic mixed-format queue advancement, HTTP
  playback, uppercase extensions, nested imports, favorites and playlist records.
- The 25-check core/resource/playback suite passed on both the iPhone simulator
  and physical iPhone 16 Pro Max. An expanded corrupt MKV/AVI/WebM error-handling
  check subsequently passed on the physical iPhone as well.
- A fresh signed Release build passed source/bundle checks and deep signature
  verification, with test media excluded from the application. Version 4.11.139
  (139) was installed on the iPhone; it relocked before the final automatic launch.
- The decoder dependency and its license are unchanged. DRM support was not
  added. These checks do not establish exhaustive codec/profile compatibility,
  high-resolution performance, patent clearance, or App Store approval.

## Verification of 4.11.140

- Fixed Finder sharing by scanning Documents, the file-sharing destination,
  instead of only Documents/Videos. Existing media stays in place. Old playlist
  and favorite paths are prefixed once with Videos/ and saved as schema version 2,
  after retaining an exact local backup of the original metadata. Conflicting
  backups, invalid metadata, and unknown schema versions preserve existing data
  and disable reference edits. System Inbox content is excluded from the library.
- Enabled MPEG-TS (.ts, .mts, .m2ts) in file registration, import, scanning, and
  the existing MobileVLCKit playback route. Added synthetic H.264/AAC TS and
  H.264/AC-3 M2TS fixtures; the MTS alias is covered too.
- The default Documents-root regression failed against the previous code.
  All 31 core/resource/playback simulator checks then passed; the subsequent
  reserved-Inbox-folder import regression passed separately (32 total checks).
  Coverage includes retained video bytes, same-named Finder and legacy files,
  playlist/favorite migration and reopen, rollback, type registration, decoded
  audio/video, displayed pictures, and seeking.
- A fresh signed Release build passed source/bundle validation and deep signature
  verification, with synthetic test media excluded from the application.
- Physical Finder-library verification is pending device unlock. A read-only
  inventory found three TS files at Documents root and one existing MKV under
  Videos. The original playlist/favorite metadata was backed up privately before
  the update. No private media or device backup is included in Git.
- Version 4.11.140 (140) was installed on the physical iPhone. A second read-only
  inventory confirmed that all four video paths, sizes, and modification dates
  were unchanged. Launch, on-device tests, and visual confirmation still require
  the phone to be unlocked.
- Wait for Finder transfers to finish, then reopen xplayer or pull to refresh.
  Live playback during a transfer and exhaustive codec profiles are not covered.
