<p align="center">
  <img src="mobile/assets/icon/android_icon.png" width="96" alt="TimeDrop icon" />
</p>

<h1 align="center">TimeDrop</h1>

<p align="center">
  <b>Seal a video to a time and a place.</b><br />
  It stays closed until the day you chose — and it only opens for the person<br />
  you left it for, once they are standing there.
</p>

<p align="center">
  <img alt="Flutter" src="https://img.shields.io/badge/Mobile-Flutter-02569B?logo=flutter&logoColor=white" />
  <img alt="React" src="https://img.shields.io/badge/Web-React%20%2B%20Vite-61DAFB?logo=react&logoColor=black" />
  <img alt="Supabase" src="https://img.shields.io/badge/Backend-Supabase-3ECF8E?logo=supabase&logoColor=white" />
  <img alt="RevenueCat" src="https://img.shields.io/badge/Billing-RevenueCat-FF5722" />
  <img alt="License" src="https://img.shields.io/badge/license-All%20rights%20reserved-lightgrey" />
</p>

---

## What is TimeDrop?

TimeDrop is a **time- and location-locked video capsule**. You record a short video, attach a
few photos and a note, pin it to a spot on the map, and choose the day it may be opened. The
capsule is end-to-end encrypted on the device before it ever leaves it, and the decryption key
never touches the server — it only ever travels inside the share link itself.

The person you send it to can't just tap and watch. They have to wait for the date, and they
have to physically walk to the pinned location. A radar-style map guides them in as they get
close, and the capsule only decrypts once they're standing within a few meters of the spot —
turning "I made you something" into a small pilgrimage instead of a notification.

It ships as three things that live in this one repository:

| | |
|---|---|
| [`mobile/`](mobile) | The Flutter app — record, seal, share, navigate to, and unlock capsules. |
| [`web/`](web) | A small React landing site and the browser handoff page for shared links. |
| [`supabase/`](supabase) | Postgres schema, row-level security, and edge functions — the whole backend. |

## How it works

1. **Record.** Up to a 60-second video, up to 3 photos, and one optional 250-character note.
2. **Seal.** Choose a spot on the map and an unlock date. The app generates a fresh AES‑256‑GCM
   key for *this capsule only*, encrypts every file on-device, and uploads only ciphertext.
3. **Share.** A link is generated (`.../c/{shareId}#{key}`) and handed off via the native share
   sheet. The decryption key lives in the URL fragment, which browsers never send to a server —
   so even TimeDrop's own backend never sees it, unless the sender explicitly opts a capsule into
   "**openable by code alone**" (a deliberate, disclosed exception for a 6-character fallback code).
4. **Wait.** The server won't hand back the encrypted payload until the chosen unlock time has
   passed, no matter what the client asks for.
5. **Walk in.** Once it's unlock day, a map guides the recipient to the pinned spot. Inside
   100 meters a radar view fades in, with a haptic pulse that quickens as they close in. The
   capsule decrypts once the recipient is within ~15 meters of the pin (with a generous "stayed
   close for a couple of minutes" fallback so a shaky GPS fix near a building doesn't lock anyone
   out).
6. **Open.** An ~11-second choreographed reveal — the moment it was recorded, the capsule
   "cracking open," then the video plays.

## Feature highlights

- **Real end-to-end encryption** — AES-256-GCM, one key per capsule, generated and used only
  on-device; the server stores and serves ciphertext it cannot read.
- **Dual-gated unlock** — both a unlock *time* and a physical *place* have to be satisfied; the
  server enforces both, the client never decides.
- **Radar-guided navigation** — a live proximity UI (`flutter_map` + OpenStreetMap, no API key)
  that escalates from a normal map to a radar view to a "closing in" state as the recipient
  approaches.
- **Anonymous-first accounts** — every install gets a working anonymous Supabase session
  immediately; users can later link a permanent identity with Google or Apple Sign-In, with a
  dedicated edge function to safely merge an anonymous device into a pre-existing account.
- **Free, subscription, and pack-based drops** — a one-time free allowance, a monthly
  subscription grant, and permanent purchased packs, debited in that order by a server-side
  ledger (RevenueCat handles the store receipts; TimeDrop owns the balance).
- **Free-drop retention rules** — free drops are capped to a shorter unlock horizon and are
  automatically purged some time after opening unless the recipient explicitly keeps them; paid
  drops are never purged.
- **Store-review friendly** — a hidden, rate-limited reviewer passcode (never shipped in the
  binary, validated server-side) lets App Store / Play reviewers create and unlock drops without
  a special build.
- **No Firebase required** — unlock-day reminders are scheduled locally on-device; there's no
  push infrastructure to stand up to run the app.
- **Universal Links / App Links** — a shared link opens straight into the app if it's installed;
  otherwise the web handoff page offers "Open in TimeDrop" or a store download, based on the
  visitor's OS.

## Architecture

```
TimeDrop/
├── mobile/     Flutter app (iOS + Android)
├── web/        React + Vite marketing site & link-handoff page
└── supabase/   Postgres migrations, RLS policies & Deno edge functions
```

### Mobile — `mobile/`

Flutter app using `provider` for state management and `supabase_flutter` as the backend client.

| Concern | Package / location |
|---|---|
| Backend & auth | `supabase_flutter` |
| Payments / entitlements | `purchases_flutter` (RevenueCat) — falls back to a mock mode with no API key |
| Location & geocoding | `geolocator`, `geocoding`, `permission_handler` |
| Map & radar UI | `flutter_map` + OpenStreetMap tiles, `latlong2` |
| Encryption | `cryptography` — isolated in `lib/core/crypto/` |
| Camera & media | `camera`, `image_picker`, `image`, `video_player`, `video_compress` |
| Local notifications | `flutter_local_notifications`, `timezone` |
| Secure local storage | `flutter_secure_storage` |
| Account linking | `google_sign_in`, `sign_in_with_apple` |
| Deep links | `app_links` (Universal Links / App Links) |

Structure inside `lib/`:

```
lib/
├── core/        constants, env config, crypto primitives, theming, error mapping
├── services/    Supabase, storage, crypto, geolocation, RevenueCat, notifications, uploads
├── providers/   ChangeNotifier state (auth, capsules, vault, payments, drop balance…)
├── models/      capsule / drop-state / vault data models
└── ui/          screens (camera, capsule config, radar, unlock sequence, paywall…) & widgets
```

### Web — `web/`

A static, client-side-only React app (React 19 + Vite + Tailwind 4) — no backend calls of any
kind. It exists purely to present the landing page and to hand a tapped share link off to the
app (or the app stores if it isn't installed yet). The share link's decryption key travels only
in the URL hash and is never read, logged, or transmitted by this site.

```
web/src/
├── components/
│   ├── landing/   Hero, HowItWorks, WhyDifferent, StoreButtons, ClosingCta
│   ├── droplink/  LandingCard, OpenInAppButton, GetTheAppButton, ShareCode
│   └── legal/     Terms & Privacy pages
├── pages/         LandingPage, TermsPage, PrivacyPage
└── utils/         OS detection (App Store / Play redirect), share-link parsing
```

### Backend — `supabase/`

Postgres (via Supabase) with row-level security as the real access-control boundary, plus four
Deno edge functions:

| Function | Purpose |
|---|---|
| `delete-user-account` | Full account deletion — purges every row and storage object a user owns, as required for App Store / Play compliance. |
| `merge-anonymous-account` | Reconciles the anonymous-device-signs-into-an-existing-account case, guarded by a proof-of-ownership token. |
| `purge-expired-capsules` | Retention job for free-tier drops (storage objects removed before the database rows), invoked on a schedule. |
| `revenuecat-webhook` | Receives RevenueCat purchase/renewal events and credits the drop ledger; idempotent, timing-safe-authenticated. |

Schema evolves through 36 migrations, covering capsules, user settings, the vault, a
subscription-then-ledger monetization model, and a series of security-hardening passes (audit
logging, rate-limited share lookups, locking capsule metadata after unlock, restricting which
columns clients may write).

## Getting started

### Prerequisites

| Tool | Needed for |
|---|---|
| [Flutter](https://docs.flutter.dev/get-started/install) (stable channel — Dart SDK `^3.12.0`) | `mobile/` |
| [Node.js](https://nodejs.org/) 20+ and npm | `web/` |
| [Supabase CLI](https://supabase.com/docs/guides/cli) | applying migrations / deploying edge functions |
| A [RevenueCat](https://www.revenuecat.com/) account | only if you want real in-app purchases; the app runs fine without one |

### Mobile app

```bash
cd mobile
flutter pub get
flutter run
```

By default the app talks to the **live hosted Supabase project** — its URL and public anon key
are baked in as defaults, so it runs with zero configuration. It also starts in **mock payment
mode** (no purchases possible) until RevenueCat keys are supplied:

```bash
cp env.example.json env.json      # gitignored — fill in your own RevenueCat SDK keys
flutter run --dart-define-from-file=env.json
```

To point the app at a different Supabase project instead, pass `SUPABASE_URL` /
`SUPABASE_ANON_KEY` the same way (see `lib/core/env/env.dart`).

### Web site

```bash
cd web
npm install
npm run dev        # dev server with HMR
npm run build       # production build → dist/
npm run preview     # serve the production build locally
npm run lint         # oxlint
```

The site has no environment variables and no backend of its own.

### Supabase backend

This project develops directly against a hosted Supabase project rather than a local Postgres
stack. `supabase/config.toml` only pins per-function JWT verification settings
(`revenuecat-webhook` and `purge-expired-capsules` authenticate with their own shared secrets
instead, since their callers aren't Supabase sessions).

```bash
supabase link --project-ref <your-project-ref>
supabase db push                       # apply migrations in supabase/migrations/
supabase functions deploy delete-user-account
supabase functions deploy merge-anonymous-account
supabase functions deploy purge-expired-capsules
supabase functions deploy revenuecat-webhook
```

Two function secrets need to be set on the project (dashboard → Edge Functions → Secrets, or
`supabase secrets set`):

| Secret | Used by |
|---|---|
| `REVENUECAT_WEBHOOK_SECRET` | `revenuecat-webhook` |
| `PURGE_JOB_SECRET` | `purge-expired-capsules` (called by a scheduled job) |

The hidden store-reviewer passcode is a separate, intentionally undocumented-in-git step — it's
a salted hash written straight into the database by hand, never committed.

## Testing

```bash
cd mobile && flutter test    # unit/widget tests: crypto, drop-balance math, onboarding,
                              # share-link parsing, radar hysteresis, unlock choreography
```

The web app has Playwright installed but no spec files yet. The `revenuecat-webhook` edge
function has a Deno test alongside it (`supabase/functions/revenuecat-webhook/index_test.ts`).

## Deploying

Each part deploys independently:

- **Mobile** — `flutter build appbundle --release` / `flutter build ipa --release` (both with
  `--dart-define-from-file=env.json`). Android release builds require a signing keystore —
  copy `mobile/android/key.properties.example` to `key.properties` and generate one with
  `keytool`; the release build intentionally refuses to run without it.
- **Web** — deploys as a static site (currently on Vercel); `vercel.json` handles SPA routing
  and serves `web/public/.well-known/` with the correct content type for the app-link
  verification files.
- **Supabase** — `supabase db push` + `supabase functions deploy <name>` against the linked
  project.

Universal Links / App Links require `web/public/.well-known/apple-app-site-association` and
`assetlinks.json` to carry your real Apple Team ID and Play App Signing SHA-256 fingerprint —
see `web/public/.well-known/README.md` for the exact steps and how to verify them.

## License

No license has been published for this repository yet — until one is added, all rights are
reserved by the author.
