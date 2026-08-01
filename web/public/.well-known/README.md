# `.well-known` — Universal Links / App Links

These two files are what let a tapped share link open the TimeDrop app instead
of the browser. **Both currently contain placeholders and must be filled in
before they do anything.** Until then, links keep opening the web page — which
is a working fallback, not a broken state.

## `apple-app-site-association` (iOS)

Replace `REPLACE_WITH_APPLE_TEAM_ID` with your Apple Developer **Team ID**
(Apple Developer → Membership details). The result looks like `A1B2C3D4E5`, so
the `appIDs` entry becomes `A1B2C3D4E5.com.timedrop.timedropMobile`.

Note the file has **no `.json` extension** — that is required by Apple. The
`Content-Type: application/json` header is set in `web/vercel.json`.

## `assetlinks.json` (Android)

Replace `REPLACE_WITH_PLAY_CONSOLE_SHA256_FINGERPRINT` with the SHA-256
certificate fingerprint, colon-separated uppercase hex.

**Take it from Play Console → your app → Setup → App signing → "App signing key
certificate".** Not from your own keystore: Play App Signing re-signs the app
with Google's key, so a fingerprint from your upload keystore will not match
what is installed on a user's device and verification will silently fail.

## Why the rewrite in `vercel.json` matters

The SPA rewrite used to send *every* path to `index.html`, which would have
served HTML for these files and broken verification with no obvious symptom.
The rewrite now excludes `/.well-known/`.

## Verifying after deployment

```bash
curl -sI https://time-drop-pink.vercel.app/.well-known/apple-app-site-association
#   expect: HTTP 200 and content-type: application/json

curl -s https://time-drop-pink.vercel.app/.well-known/assetlinks.json
#   expect: the JSON above, with a real fingerprint
```

Android's verifier (on a device, after installing a release build):

```bash
adb shell pm get-app-links com.timedrop.timedrop_mobile
#   expect: time-drop-pink.vercel.app: verified
```

Apple's cache can take a few hours and is refreshed on app install; deleting and
reinstalling the app is the reliable way to re-test.
