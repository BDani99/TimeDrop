# TimeDrop — teendők kiadás előtt

Ez a lista azt tartalmazza, **amit neked kell elvégezned**. A kód, az adatbázis
és a szerveroldali logika kész és élesben tesztelve — ami itt szerepel, az vagy
külső fiókot igényel (App Store Connect, Play Console), vagy tudatosan rád
tartozó döntés, vagy fizikai eszközt kér.

Utolsó frissítés: 2026-08-01

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

```bash
flutter build appbundle --release \
  --dart-define=REVENUECAT_API_KEY_ANDROID=goog_XXXXXXXX \
  --dart-define=REVENUECAT_API_KEY_IOS=appl_XXXXXXXX

flutter build ipa --release \
  --dart-define=REVENUECAT_API_KEY_IOS=appl_XXXXXXXX \
  --dart-define=REVENUECAT_API_KEY_ANDROID=goog_XXXXXXXX
```

> Érdemes ezeket egy `--dart-define-from-file=env.json` fájlba tenni és
> gitignore-olni, hogy ne kelljen minden buildnél begépelni.

### 4. Ingyen drop limit visszaállítása 1-re

**Jelenleg 100**, mert teszteléshez fel volt nyomva. Ha így adod ki, minden
új felhasználó 100 ingyen dropot kap.

```sql
update public.system_settings set value = 1 where key = 'free_drop_limit';
```

> Szándékosan nem állítottam át: ha most 1-re megy, a saját teszteszközöd
> azonnal elakad. Kiadás előtt viszont kötelező.

### 5. Android release aláírás és App Link ujjlenyomat

A címzetti folyamat mostantól **deep linkre** épül: a kapott linkre koppintva
az appnak kell megnyílnia, nem a böngészőnek. Ehhez a Google-nek ellenőriznie
kell, hogy a domain és az app összetartozik — és ehhez a **release aláírás
SHA-256 ujjlenyomata** kell.

**Két külön dolog hiányzik:**

1. **A release build most a debug kulccsal ír alá.**
   `mobile/android/app/build.gradle.kts:36-37` —
   `signingConfig = signingConfigs.getByName("debug")`. Így nem lehet a Play
   Store-ba feltölteni, és az ujjlenyomat sem lenne stabil. Készíts release
   keystore-t, és állítsd át rá a `release` buildTypes blokkot.

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

Ugyanez Apple oldalon. A `Runner.entitlements` fájl **elkészült**
(`applinks:time-drop-pink.vercel.app`), és a `CODE_SIGN_ENTITLEMENTS` mindhárom
konfigurációra be van állítva — de az AASA fájlba a **Team ID** kell.

1. Apple Developer → **Membership** → Team ID (10 karakter, pl. `A1B2C3D4E5`)
2. Írd be ide: `web/public/.well-known/apple-app-site-association` →
   `REPLACE_WITH_APPLE_TEAM_ID.com.timedrop.timedropMobile`
3. Az Apple Developer portálon a **Associated Domains** capability-t is
   engedélyezni kell az App ID-nál, különben a build alá sem íródik

> A pontos kitöltési útmutató a `web/public/.well-known/README.md`-ben van.

---

## 🟡 FONTOS — biztonsági teendők

### 7. Elfogadott kockázat: `pg_net` a kliens szerepköröknek

A `net.http_post` / `http_get` / `http_delete` EXECUTE joga a `PUBLIC`-on
keresztül az `anon` és `authenticated` szerepköröknek is megvan — ez a
`pg_net` kiterjesztés Supabase-alapértelmezése (a takarító jobhoz kellett
engedélyezni).

**Ellenőriztem: nem kihasználható.** A PostgREST csak a `public` sémát teszi
közzé, a `/rest/v1/rpc/http_post` 404-et ad. A jogot **nem tudjuk visszavonni**:
a függvények tulajdonosa `supabase_admin`, a mi `postgres` szerepkörünk nem
tagja annak, így a REVOKE csendben hatástalan (ezt is leteszteltem).

**Amire figyelj:** ha valaha további sémát teszel közzé a PostgREST-en
(Settings → API → Exposed schemas), ez azonnal SSRF-fé válik. Ilyenkor kérj
Supabase támogatást a jog visszavonásához.


### 8. Terms és Privacy oldalak

Az appban a paywall alján ezekre mutat link, de jelenleg **placeholder**:

- `https://time-drop-pink.vercel.app/terms`
- `https://time-drop-pink.vercel.app/privacy`

Mindkét store elutasítja a beküldést valódi tartalom nélkül. Az adatvédelmi
tájékoztatóban ki kell térni: helyadat, kamera/mikrofon, végponttól végpontig
titkosítás, fióktörlés, és az ingyen dropok 3 hónapos megőrzési ideje.

> A megőrzési szabály **pontos** megfogalmazása: az ingyenes dropot a nyitás
> után egy hónappal töröljük, **kivéve, ha a feladó valaha fizetett** (bármikori
> előfizetés vagy drop csomag). Aki fizetett, annak az ingyenes dropjai is
> megmaradnak, a lemondás után is.

> ⚠️ **Új, és muszáj szerepelnie:** a feladó dropronként bekapcsolhatja a
> „Openable with the code alone" opciót. Az ilyen dropoknál a kulcs a
> szerverre kerül, tehát **azt az egy emléket a szolgáltatás vissza tudja
> fejteni**. A tájékoztató nem állíthatja, hogy minden tartalom végponttól
> végpontig titkosított — azt kell írni, hogy alapértelmezetten az, és a
> feladó dropronként lemondhat róla. (Részletek: `0030` migráció fejléce.)
>
> A **vágólap-használatot** is érdemes említeni: az app az első indításkor
> **egyetlen egyszer** megnézi a vágólapot, hogy a weboldalról érkező linket a
> telepítés után át tudja venni. Ezt követően soha többé nem olvassa.

---

## 🔵 A CÍMZETTI FOLYAMAT ÚJ RÉSZEI

### 9. Weboldal újratelepítése

A `web/` átállt az új rendszerre, tehát **újra kell deployolni**, különben a
weboldal még a régi „Copy link" folyamatot mutatja, amit az app már nem kezel.

Ami változott:

- **A domain gyökere mostantól rendes landing page** — hero, „hogyan működik"
  három lépésben, „miért más" három pontban, záró letöltő gombok, görgetésre
  beúszó animációkkal. A korábbi két mondatos doboz megszűnt.
- **A droplink oldal (`/c/{kód}`) szándékosan változatlan** — aki egy emléket
  kapott, annak nem terméket kell mutatni.
- **„Open in TimeDrop"** gomb — a `timedrop://` sémán adja át a dropot a
  telepített appnak, a kulccsal együtt. Erre azért van szükség, mert a
  böngésző már ezen a domainen áll, és egy ugyanoda mutató link **nem**
  aktiválja újra az App/Universal Link kezelést.
- **„Don't have the app? Get it"** — a teljes linket a vágólapra teszi, majd a
  store-ba visz. Az app az **első indításkor, életében egyszer** megnézi a
  vágólapot, és ha TimeDrop linket talál, azzal nyit.
- A **6 karakteres kód** nagyban, koppintásra másolható.
- A Play Store link javítva: `com.timedrop.app` → `com.timedrop.timedrop_mobile`
  (a régi minden Android címzettet 404-re vitt).

### 10. Store-azonosítók a weboldalon

`web/src/utils/osDetector.js`:

```js
export const APP_STORE_URL = 'https://apps.apple.com/app/timedrop/id0000000000';
```

Az `id0000000000` **helyőrző**. Amint létrejön az App Store Connect
app-rekord, írd át a valódi Apple ID-ra, különben az iOS-es „Get it" gomb
404-re visz. A Play-oldali link már helyes.

Ez a konstans **három helyen** látszik: a droplink oldal „Get it" gombján, a
landing page hero-jában és a záró CTA-ban. Egy helyen kell átírni.

> Az iOS `timedrop://` séma az `Info.plist`-ben már be van állítva
> (`CFBundleURLTypes`), külön Apple-oldali engedélyt nem igényel — az
> Associated Domains capability viszont igen, lásd a 6. pontot.

### 11. Landing page szövegek átolvasása

A landing page szövegeit én írtam, angolul, a termék tényleges viselkedése
alapján. Három állítás szerepel benne, amit érdemes tudatosan jóváhagynod,
mert marketing-ígéretként fognak működni:

- *„We cannot watch it"* — alapértelmezetten igaz. A „kóddal is megnyitható"
  opcióval viszont **nem**, és ezt a landing page nem árnyalja. Ha ez zavar,
  vagy a szöveget kell finomítani, vagy a store-leírásban külön kitérni rá.
- *„Your first drop is free"* — a `free_drop_limit` jelenleg **100**
  (4. pont). Kiadás előtt 1-re kell állítani, különben a mondat nem igaz.
- Az App Store / Play gombok **mindkét platformon látszanak**, eszköztől
  függetlenül — asztali gépen ez a helyes, mobilon egy fölösleges gomb.
