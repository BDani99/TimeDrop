# TimeDrop — teendők kiadás előtt

Ez a lista azt tartalmazza, **amit neked kell elvégezned**. A kód, az adatbázis
és a szerveroldali logika kész és élesben tesztelve — ami itt szerepel, az vagy
külső fiókot igényel (App Store Connect, Play Console), vagy tudatosan rád
tartozó döntés, vagy fizikai eszközt kér.

Utolsó frissítés: 2026-08-03

---

## 🔴 BLOKKOLÓ — enélkül nem lehet kiadni

### 1. Store termékek felvétele

A RevenueCat oldali regisztráció **kész**, de a termékek a store-okban még nem
léteznek. Amíg nem hozod létre őket ugyanezekkel az azonosítókkal, a paywall
üres marad, és a vásárlás nem működik.

**App Store Connect** → Funkciók → Alkalmazáson belüli vásárlások

| Azonosító | Típus | Megjegyzés |
|---|---|---|
| `com.timedrop.pro.monthly` | Auto-renewable subscription | `timedrop_pro` csoportba |
| `com.timedrop.pro.annual` | Auto-renewable subscription | ugyanabba a csoportba |
| `com.timedrop.drops.1` | Consumable | 1 drop |
| `com.timedrop.drops.2` | Consumable | 2 drop |
| `com.timedrop.drops.3` | Consumable | 3 drop |
| `com.timedrop.drops.5` | Consumable | 5 drop |
| `com.timedrop.drops.10` | Consumable | 10 drop |

**Play Console** → Bevételszerzés

| Azonosító | Típus | Megjegyzés |
|---|---|---|
| `timedrop_pro` | Subscription | **két base plan**: `monthly` és `annual` |
| `drops_1` | In-app product | **Consumable**-ra állítva |
| `drops_2` | In-app product | consumable |
| `drops_3` | In-app product | consumable |
| `drops_5` | In-app product | consumable |
| `drops_10` | In-app product | consumable |

> ⚠️ A Play-nél a consumable jelölés fontos: ha nem az, a felhasználó egy
> csomagot csak egyszer tud megvenni, sosem többször.

**Árazás:** a RevenueCat nem tárol árat, mindkét store-ban ott állítod be.
Az appban az ár mindig a store-tól jön (`storeProduct.priceString`), tehát
nincs kódmódosítás, ha árat változtatsz.

### 2. RevenueCat store-kapcsolatok

RevenueCat dashboard → **TimeDrop** projekt (`proj0b348db1`) → Apps:

- **TimeDrop iOS** (`app07c6a50326`) — App Store Connect **App-Specific Shared
  Secret** és/vagy In-App Purchase Key feltöltése
- **TimeDrop Android** (`app65c17905af`) — Google Play **Service Account JSON**
  feltöltése és a Play Developer API hozzáférés engedélyezése

Enélkül a RevenueCat nem tudja validálni a vásárlásokat, és a webhook sem
küld eseményt.

### 3. Kliens API kulcsok beépítése

Az app jelenleg **mock módban** van (nincs kulcs → nem lehet vásárolni).
A kulcsok a RevenueCat → Project Settings → **SDK API keys** alatt vannak
(ezek a publikus `appl_…` / `goog_…` kulcsok, nem a titkosak).

Másold a `mobile/env.example.json`-t `env.json`-ra (gitignore-olva van), írd
bele a két kulcsot, és:

```bash
flutter build appbundle --release --dart-define-from-file=env.json
flutter build ipa       --release --dart-define-from-file=env.json
```

### 4. Ingyen drop limit visszaállítása 1-re

**Jelenleg 100**, mert teszteléshez fel volt nyomva. Ha így adod ki, minden
új felhasználó 100 ingyen dropot kap.

```sql
update public.system_settings set value = 1 where key = 'free_drop_limit';
```

> Szándékosan nincs átállítva: ha most 1-re megy, a saját teszteszközöd azonnal
> elakad. Kiadás előtt viszont kötelező — a landing page „Your first drop is
> free" mondata is csak így igaz.

### 5. Android release keystore és App Link ujjlenyomat

1. **Keystore létrehozása.** Másold a `mobile/android/key.properties.example`-t
   `key.properties`-re, és:

   ```bash
   keytool -genkey -v -keystore upload-keystore.jks \
     -keyalg RSA -keysize 2048 -validity 10000 -alias upload
   ```

   A `key.properties`, a `*.jks` és a `*.keystore` gitignore-olva van. **A
   keystore-ról csinálj biztonsági mentést**, olyan helyre, ahol öt év múlva is
   megvan. Amíg nincs meg, a `flutter build appbundle --release` szándékosan
   hibaüzenettel megáll.

2. **Az ujjlenyomatot NEM a saját keystore-odból másold.** Új appoknál a Play
   App Signing kötelező, tehát a Google újraírja az aláírást. A helyes érték:
   **Play Console → Setup → App signing → App signing key certificate → SHA-256**.

   Ezután írd be ide:
   `web/public/.well-known/assetlinks.json` → `REPLACE_WITH_PLAY_CONSOLE_SHA256_FINGERPRINT`

   Formátum: nagybetűs hexa, kettősponttal tagolva
   (`AB:CD:EF:…`, 32 bájt = 95 karakter).

**Ellenőrzés eszközön** (telepítés után):

```bash
adb shell pm get-app-links com.timedrop.timedrop_mobile
```

A `time-drop-pink.vercel.app` sornak `verified`-nek kell lennie. Ha
`legacy_failure`, akkor a fájl nem érhető el vagy az ujjlenyomat nem egyezik.

### 6. iOS Team ID és associated domains

A `Runner.entitlements` fájl kész (`applinks:time-drop-pink.vercel.app`), és a
`CODE_SIGN_ENTITLEMENTS` mindhárom konfigurációra be van állítva — de az AASA
fájlba a **Team ID** kell.

1. Apple Developer → **Membership** → Team ID (10 karakter, pl. `A1B2C3D4E5`)
2. Írd be ide: `web/public/.well-known/apple-app-site-association` →
   `REPLACE_WITH_APPLE_TEAM_ID.com.timedrop.timedropMobile`
3. Az Apple Developer portálon a **Associated Domains** capability-t is
   engedélyezni kell az App ID-nál, különben a build alá sem íródik

> A pontos kitöltési útmutató a `web/public/.well-known/README.md`-ben van.

### 7. Jogi szövegek véglegesítése

1. **A helykitöltők kitöltése** a `/terms` és `/privacy` oldalon:

   ```bash
   grep -rn '\[\[' web/src/components/legal/
   ```

   `[[LEGAL_ENTITY]]`, `[[REGISTERED_ADDRESS]]`, `[[GOVERNING_LAW]]`,
   `[[COURTS]]`. Amíg ezek benne vannak, ne küldd be a store-oknak.

2. **Nézesd át jogásszal.** A szöveg a termék tényleges viselkedése alapján
   készült (kód-feloldás kivétele, 3 hónapos megőrzés, egyszeri
   vágólap-olvasás), de nem jogi tanácsadás — EU-s kiadásnál a GDPR-rész és az
   adatkezelő megnevezése az, ami számít.

3. **A `support@timedrop.app` cím fogadjon levelet.** Az appban és mindkét jogi
   oldalon ez a kapcsolattartási cím, és a store-ok a review alatt **ténylegesen
   írnak rá**. Ha a domainen nincs postafiók, ez néma elutasítás lesz.

### 8. Store-azonosító a weboldalon

`web/src/utils/osDetector.js`:

```js
export const APP_STORE_URL = 'https://apps.apple.com/app/timedrop/id0000000000';
```

Az `id0000000000` **helyőrző**. Amint létrejön az App Store Connect
app-rekord, írd át a valódi Apple ID-ra, különben az iOS-es letöltő gomb
404-re visz. A Play-oldali link már helyes.

Ez a konstans **három helyen** látszik: a droplink oldal „Get it" gombján, a
landing page hero-jában és a záró CTA-ban. Egy helyen kell átírni.

### 9. Weboldal újratelepítése

A `web/` a legutóbbi deploy óta változott (jogi oldalak, eszközfüggő store
gombok, pontosított titkosítási állítás), tehát **deployolni kell** — különben
a `/terms` és `/privacy` link továbbra is a landing page-re visz, amit mindkét
store elutasít.

---

## 🟡 FONTOS — biztonsági teendők

### 10. Elfogadott kockázat: `pg_net` a kliens szerepköröknek

A `net.http_post` / `http_get` / `http_delete` EXECUTE joga a `PUBLIC`-on
keresztül az `anon` és `authenticated` szerepköröknek is megvan — ez a
`pg_net` kiterjesztés Supabase-alapértelmezése (a takarító jobhoz kellett
engedélyezni).

**Ellenőrizve: nem kihasználható.** A PostgREST csak a `public` sémát teszi
közzé, a `/rest/v1/rpc/http_post` 404-et ad. A jogot **nem tudjuk visszavonni**:
a függvények tulajdonosa `supabase_admin`, a mi `postgres` szerepkörünk nem
tagja annak, így a REVOKE csendben hatástalan.

**Amire figyelj:** ha valaha további sémát teszel közzé a PostgREST-en
(Settings → API → Exposed schemas), ez azonnal SSRF-fé válik. Ilyenkor kérj
Supabase támogatást a jog visszavonásához.
