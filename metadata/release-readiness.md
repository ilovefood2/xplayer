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
4. Verify the public policy/support URLs return the final documents before upload.
5. Complete age-rating, pricing/availability, content-rights, and export-compliance
   forms using the actual app behavior. No custom/non-exempt encryption is used.
6. Supply actual review contact details and screenshots of this build. Do not
   use the user's private video content in store screenshots.
7. Export with App Store distribution signing and run Apple's archive validation.
8. Obtain Apple review. Local checks do not guarantee acceptance or legal clearance.

The source/license audit supports an independent implementation; the scope and
limits are in PROVENANCE.md. Existing upstream GPL licenses are not changed.
If adding upstream code, third-party SDKs, codecs, cloud sync, analytics, ads,
accounts, or paid features, review licenses and privacy declarations again.

## Primary references checked

- https://developer.apple.com/app-store/review/guidelines/
- https://developer.apple.com/app-store/submitting/
- https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api
- https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitypereasons
- https://www.gnu.org/licenses/gpl-faq.en.html#ReleaseUnderGPLAndNF
- https://www.gnu.org/licenses/gpl-faq.en.html#MereAggregation
