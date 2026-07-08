TimeDrop – Flutter Mobile + React Web Implementációs Specifikáció (AI Agent Prompt)

Cél: Egy végpontokig titkosított (E2EE), geolokáció-alapú időkapszula mobilalkalmazás (Flutter), egy webes megosztó felület (React) és a backend (Supabase + RevenueCat) teljes implementációja. A gyökérkönyvtárban két külön projektként (mobile és web) kell felépíteni a rendszert.
Architektúra (Mobil): Provider alapú State Management, Repository pattern a Service réteg elkülönítésére, Anonymous-first autentikáció eszköz-azonosító (Device Hash) alapján.
1. Adatbázis Séma (Supabase) és Adatmodellek

A kódolás megkezdése előtt ezeket a modelleket kell implementálni.

time_capsules tábla: id (UUID, PK), creator_id (UUID, FK -> auth.users), share_id (String, 6 karakteres egyedi azonosító a lekérdezéshez), encrypted_payload (Text - a feltöltött média URL-je és a metaadatok AES-GCM titkosított formája), latitude (Float8), longitude (Float8), unlock_time (Timestamptz), created_at (Timestamptz).

user_settings tábla: user_id (UUID, PK -> auth.users), free_drop_used (Boolean, default: false), fcm_token (Text, push értesítésekhez).
2. E2EE Titkosítás és a Dinamikus Vercel Linkelés Logikája – KRITIKUS

A Zero-Knowledge elv és a zökkenőmentes megosztás érdekében a szerver sosem láthatja a tartalmat, a címzettnek pedig egy univerzális linken keresztül kell megkapnia a hozzáférést.

A Feladó (Mobil App) szerepe: A videó titkosítása után az applikáció legenerál egy egyedi URL-t, ami MINDIG a Vercelen hostolt React weboldalra mutat. A link formátuma kötelezően: https://[PROJECT-NAME].vercel.app/c/{share_id}#{encryption_key}. A hashtag (#) biztosítja, hogy a titkosítási kulcs lokális marad a böngészőben és nem kerül be a Vercel/szerver logokba.

A Közvetítő (React Weboldal) szerepe: Amikor a címzett megnyitja ezt a linket, a weboldal kliensoldalon értelmezi az URL-t. Nem hív be semmilyen backendet. Megjeleníti a letöltő gombot, ami kattintáskor a TELJES paraméterezett URL-t vágólapra másolja, majd átirányít az App Store-ba / Google Play-be.

A Címzett (Mobil App) szerepe: Az applikáció a legelső megnyitáskor (vagy ha később kerül fókuszba) ellenőrzi a rendszer vágólapját. Ha felismeri a [PROJECT-NAME].vercel.app/c/ formátumot, automatikusan szétszedi a linket, kinyeri belőle a share_id-t a letöltéshez és az encryption_key-t a dekódoláshoz, majd azonnal elindítja a Radar élményt.
3. Részletes Sprint Terv és UI/Logika leírás (Mobil App)

Sprint 0: Core Architektúra, Setup és State Management
Cél a projekt alapkönyvtárainak és providereinek inicializálása. Szükséges függőségek: supabase_flutter, provider, purchases_flutter, geolocator, camera, flutter_secure_storage, cryptography, flutter_local_notifications.
Az AuthProvider kezeli az anonim belépést és az SSO linkelést. A PaymentProvider a RevenueCat logikát és a free_drop_used állapotot felügyeli. A CapsuleProvider az E2EE titkosítást, a feltöltést és a távolságmérést végzi.
A MainRouter a splash screen után vágólap (Clipboard) ellenőrzést végez. Érvényes Vercel link esetén a RadarScreen-re, anélkül a HomeScreen-re navigál.

Sprint 1: A Feladó Flow (Creator) – Létrehozás és Titkosítás
A tartalom rögzítése, titkosítása és az első ingyenes kapszula elküldése.
Képernyők: HomeScreen (Új emlék gomb), CameraScreen (60 mp rögzítő), CapsuleConfigScreen (Térkép tűvel és DatePicker), ShareScreen (Generált Vercel URL megjelenítése és natív megosztása).
Logika: A rögzítés után ellenőrzi a free_drop_used flaget. Ha true és nincs Premium, irány a PaywallScreen. Ha engedélyezett: AES-256 kulcs generálása, titkosítás memóriában, Storage feltöltés, DB rekord létrehozása, flag true-ra állítása.

Sprint 2: A Címzett Flow – Radar UI és Kinyitás
A gamifikált helymeghatározás és az élmény dekódolása.
Képernyők: RadarScreen (Blur effektes térkép 100 méteres zónával), VideoPlayerScreen (Dekódolt videó lejátszása).
Logika: Vágólap URL feldolgozása. DB lekérdezés a share_id alapján, unlock_time ellenőrzése. Folyamatos GPS stream indítása. Távolság < 15 méter esetén: HapticFeedback, titkosított fájl letöltése, dekódolás a kinyert kulccsal és lejátszás.

Sprint 3: Felelősségáthárítás és Account Linking (Biztonság)
Az anonim fiókok stabilizálása és az emlékek véglegesítése.
Képernyők: MemorySavedModal (Felhőbe mentés figyelmeztetés a megtekintés után Apple/Google SSO gombokkal), SettingsScreen (Fiók linkelése, Fiók törlése).
Logika: SSO gombra kattintáskor Supabase belépés fut le, majd meghívja a merge_anonymous_to_google Edge Functiont az anonim és a végleges fiók összefésüléséhez.

Sprint 4: Monetizáció és Paywall (RevenueCat)
Az üzleti modell bekötése a 2. kapszulától.
Képernyők: PaywallScreen (Premium előnyök, havi 3 videó / 10 kép, feliratkozás és visszaállítás gombok).
Logika: RevenueCat inicializálása, gombnyomásra purchasePackage(). Reviewer Bypass funkció: a képernyő címének 10-szeres megérintésére jelszómező jelenik meg. Helyes jelszó lokálisan Premium státuszt ad a QA tesztelőknek.
4. Webes Előtér (React Landing Page a Vercel-hez)

Cél: Egy reszponzív fogadóoldal, amit a mobil app generál, és a címzett nyit meg a chaten kapott linkből.
Technológia: React + Vite (vagy Next.js) Tailwind CSS-szel.
Működés és Logika: Az oldal a https://[PROJECT-NAME].vercel.app/c/{share_id}#{encryption_key} URL-en tölt be. A React app a DOM API-val (window.location.hash és pathname) kinyeri az adatokat. Semmilyen backend hívást nem végez, szigorúan statikus a titkosítás védelme miatt.
Felület: Sötét, elegáns "Glassmorphism" design. Központi szöveg: "[Feladó neve] hagyott neked egy időkapszulát." Animált, elmosódott térkép háttér.
Kritikus Funkció (Mágikus Gomb): Egy feltűnő "Kód másolása és App letöltése" CTA gomb. Megnyomásakor a JavaScript a teljes URL-t a vágólapra (Clipboard API) helyezi. Ezután OS detektálás (iOS/Android) alapján átirányítja a usert a megfelelő App Store / Google Play linkre.
5. Architektúra és Mappastruktúra (Monorepo)
Plaintext

/
├── mobile/ (A Flutter projekt)
│   ├── lib/
│   │   ├── core/ (constants, errors, utils, crypto)
│   │   ├── models/
│   │   ├── providers/ (auth, payment, capsule)
│   │   ├── services/ (supabase, revenuecat, geolocation, crypto_service)
│   │   ├── ui/ (router, screens, widgets)
│   │   └── main.dart
│   ├── pubspec.yaml
│   └── ...
├── web/ (A React webes projekt Vercel deploy-hoz)
│   ├── src/
│   │   ├── components/
│   │   ├── utils/ (clipboardHelper, osDetector)
│   │   ├── App.jsx
│   │   └── main.jsx
│   ├── package.json
│   └── ...
└── supabase/ (Edge Functions és Migrations)

6. Feltételek és Szabályok a kódgeneráláshoz

Hibakezelés: Egyetlen aszinkron hívás sem maradhat try-catch blokk nélkül a Flutterben. Minden hiba jelenjen meg egy SnackBar-ban.
Engedélyek: A CameraScreen és a RadarScreen betöltése ELŐTT kötelező a permission_handler ellenőrzés futtatása.
Erőforrás menedzsment: A Geolocator stream és a VideoPlayerController leállítása kötelező a dispose() metódusokban.
Mock Payment: Hiányzó RevenueCat API kulcs esetén a PaymentProvider fallbackeljen Mock módra, sikeres fizetést szimulálva.
Web fókusz: A webes React projekt maradjon ultrakönnyű és statikus a Vercel deploy optimalizálása és az adatok kiszivárgásának megakadályozása érdekében.