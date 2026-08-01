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

### 5. Review-jelszó élesítése

A store review csapatának kell egy belépési mód (10 koppintás a paywall
címére → jelszó). A jelszó **szerveroldalon** van, nincs az APK-ban.

1. Nyisd meg: `supabase/scripts/set_reviewer_passcode.sql.example`
2. Másold le `set_reviewer_passcode.sql` néven (ez gitignore-olt)
3. Cseréld a `<PASSCODE>` helyőrzőt a valódi jelszóra
4. Futtasd le a Supabase SQL editorban
5. Írd be ugyanazt a jelszót a store beküldési jegyzeteibe:
   - App Store Connect → App Review Information → **Sign-in required** →
     „Tap the paywall headline 10 times, then enter: `<PASSCODE>`"
   - Play Console → App content → **App access** → ugyanez

**Jóváhagyás után kapcsold ki** (nem kell hozzá app-frissítés):

```sql
update public.secret_settings
   set setting_value = 'false'::jsonb, updated_at = now()
 where setting_key = 'reviewer_passcode_enabled';
```

### 6. Android release aláírás és App Link ujjlenyomat

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

### 7. iOS Team ID és associated domains

Ugyanez Apple oldalon. A `Runner.entitlements` fájl **elkészült**
(`applinks:time-drop-pink.vercel.app`), és a `CODE_SIGN_ENTITLEMENTS` mindhárom
konfigurációra be van állítva — de az AASA fájlba a **Team ID** kell.

1. Apple Developer → **Membership** → Team ID (10 karakter, pl. `A1B2C3D4E5`)
2. Írd be ide: `web/public/.well-known/apple-app-site-association` →
   `REPLACE_WITH_APPLE_TEAM_ID.com.timedrop.timedropMobile`
3. Az Apple Developer portálon a **Associated Domains** capability-t is
   engedélyezni kell az App ID-nál, különben a build alá sem íródik

> A pontos kitöltési útmutató a `web/public/.well-known/README.md`-ben van.

### 8. A web újratelepítése a `.well-known` fájlokkal

A két fájl kitöltése után **a webet újra kell deployolni**, mert az Apple és a
Google élőben tölti le őket a domainről.

A `web/vercel.json` már fel van készítve rá: a `.well-known/` útvonal ki van
véve az `index.html` rewrite alól (enélkül HTML-t kapnának JSON helyett), és
mindkét fájl explicit `Content-Type: application/json` fejlécet kap — az
`apple-app-site-association`-nak nincs kiterjesztése, e nélkül az Apple
visszautasítaná.

**Deploy után ellenőrizd böngészőből**, hogy JSON jön vissza és nem a weboldal:

- `https://time-drop-pink.vercel.app/.well-known/assetlinks.json`
- `https://time-drop-pink.vercel.app/.well-known/apple-app-site-association`

> ⏱️ Az Apple CDN-je gyorsítótárazza az AASA-t. Ha rosszul töltötted ki és
> javítod, a friss érték **akár egy napig** is késhet. Fejlesztés közben ezt
> az iOS Settings → Developer → **Associated Domains Development** kapcsolóval
> lehet megkerülni.

---

## 🟡 FONTOS — biztonsági teendők

### 8/a. Elfogadott kockázat: `pg_net` a kliens szerepköröknek

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


### 9. API kulcsok rotálása

A beszélgetés során kikerültek kulcsok:

| Kulcs | Állapot | Teendő |
|---|---|---|
| RevenueCat v1 `sk_tSlWW…` | chatbe beírva | **Töröld** a dashboardon (v2 API-hoz úgyis használhatatlan) |
| RevenueCat v2 `sk_HqNBI…` | képernyőképen | **Rotáld**, ha a transzkript bárhová kikerül |
| Supabase PAT `sbp_749a…` | `.mcp.json`-ban | gitignore-olt, de érdemes rotálni |

RevenueCat: Project Settings → API keys → a régi mellett `…` → Delete.
Supabase: Account → Access Tokens → Revoke + új generálás, majd `.mcp.json`
frissítése.

### 10. Terms és Privacy oldalak

Az appban a paywall alján ezekre mutat link, de jelenleg **placeholder**:

- `https://time-drop-pink.vercel.app/terms`
- `https://time-drop-pink.vercel.app/privacy`

Mindkét store elutasítja a beküldést valódi tartalom nélkül. Az adatvédelmi
tájékoztatóban ki kell térni: helyadat, kamera/mikrofon, végponttól végpontig
titkosítás, fióktörlés, és az ingyen dropok 3 hónapos megőrzési ideje.

---

## 🟢 TESZTELÉS ESZKÖZÖN

Ezeket nem tudtam elvégezni — nincs bekötött eszköz/emulátor.

### 11. Onboarding végigjátszása

- [ ] Mind a 9 oldal elérhető, a haladásjelző töltődik
- [ ] A vissza gomb minden oldalon működik — **kivéve** az „elemzés" oldalt
- [ ] Kis kijelzőn (5") egyik oldal sem csordul túl
- [ ] Kérdésre koppintva automatikusan tovább lép
- [ ] Az „elemzés" animáció végigfut és magától továbbmegy
- [ ] A paywall főcíme igazodik ahhoz, amit a „What should they feel" kérdésre válaszoltál
- [ ] **Újratelepítés után nincs újra onboarding** (helyi flag)
- [ ] Fiók linkelése után, másik eszközön sincs újra (szerver flag)

### 12. Fizetés sandboxban

Előbb hozz létre sandbox tesztfiókot (App Store Connect → Users and Access →
Sandbox Testers; Play Console → License testing).

- [ ] Havi előfizetés → **10 drop néhány másodpercen belül**
- [ ] A kiválasztott csomag az, amit ténylegesen megterhelnek (havi ≠ éves!)
- [ ] Drop csomag vásárlása → az egyenleg nő
- [ ] „Restore purchases" visszaállítja az előfizetést
- [ ] Vásárlás megszakítása nem dob hibaüzenetet
- [ ] Repülőgép módban indítva az előfizető nem látszik lejártnak

### 13. Fiókkezelés

- [ ] Kijelentkezés → friss anonim fiók, az app nem akad meg
- [ ] Google/Apple linkelés → az eszközön lévő emlékek átjönnek
- [ ] Fióktörlés → minden eltűnik, az app használható marad
- [ ] Ha a merge elbukik, a Beállításokban megjelenik az „Emlékek
      áthelyezésének újrapróbálása" sor

### 14. Drop kvóta

- [ ] Az ingyen drop dátumválasztója **nem enged 2 hónapnál távolabbra**
- [ ] Elfogyott egyenlegnél a Seal a paywallra visz
- [ ] Elakadt feltöltés eldobása visszaadja a dropot
- [ ] Vásárolt droppal 2 hónapnál távolabbra is lehet küldeni

### 15. Review-belépés

- [ ] 10 koppintás a paywall címére megnyitja a jelszó ablakot
- [ ] 9 koppintás nem, és lassú koppintás nullázza a számlálót
- [ ] Helyes jelszó után korlátlanul lehet dropot létrehozni

### 16. A kiadás előtti auditból származó javítások

- [ ] **Beállítások → Drops panel**: az egyenleg bontása (ingyen / előfizetési /
      vásárolt) a valós számokat mutatja, és a „következő nullázás" dátuma stimmel
- [ ] **Restore purchases a Beállításokban** lefut, és nem hagy akadt állapotot
      (ezt a store reviewer is meg fogja nyomni)
- [ ] **Manage subscription** megnyitja a store előfizetéskezelőjét
- [ ] **Egyenleg-chip a Home-on** a valós számot mutatja; drop létrehozása
      után azonnal csökken; 0-nál piros
- [ ] **Megőrzés nem-előfizetőként**: a modal *azonnal* kimondja, hogy ez Pro
      funkció (nem a fiók-linkelés után!), a „See plans" a paywallra visz, és
      onnan visszajutva nem ragadsz képernyőn
- [ ] **Ingyen drop elköltése után** a dátumválasztó már **nem** korlátoz
      2 hónapra (fizetett droppal bármeddig lehet küldeni)
- [ ] **Csonka megosztási link** beillesztésekor világos üzenet jön
      („This share link looks incomplete"), nem pedig „a kulcs sérült"
- [ ] **Radar**: egy még feltöltés alatt álló drop megnyitásakor a radar
      percekig pollozhat anélkül, hogy sebességkorlátba ütközne

### 17. Az újraépített címzetti folyamat

Ez a rész **csak eszközön ellenőrizhető**, és ez az egyetlen olyan
funkcióegység, aminek a lényegét nem tudtam leszimulálni.

**Deep link (a 6–8. pont után!)**

- [ ] WhatsAppból kapott linkre koppintva **az app nyílik meg, nem a böngésző**
      — Androidon és iOS-en külön
- [ ] Hidegindítás (app teljesen bezárva) és melegindítás (háttérben) is működik
- [ ] Ugyanarra a linkre **másodszor koppintva is megnyílik** (a korábbi
      „egyszer már megmutattuk" logika megszűnt)
- [ ] **Androidon megérkezik-e a `#` utáni kulcs.** Ha nem, a tartalék ág lép
      életbe: „Ez az emlék hozzád tartozik, de a megnyitásához a teljes link
      kell" + beillesztő mező. Helyes shareId esetén ez kinyitja a dropot,
      eltérő linkre viszont hibát ad.
- [ ] Az app **nem olvassa többé a vágólapot** magától (a Redeem lap
      előkitöltése megmaradt — az szándékos, felhasználó által kezdeményezett)

**Makró térkép és mikró radar**

- [ ] Több kilométerről indítva **utcatérkép** látszik a céllal és a saját
      pozícióval
- [ ] A **„Get Directions"** megnyitja a natív térképet (iOS: Apple Maps,
      Android: alapértelmezett; ha nincs, Google Maps a böngészőben)
- [ ] **50 m alatt** átvált a radarra, és ezzel egyszerre indul a haptikus
      lüktetés
- [ ] A határ körül sétálva **nem villog oda-vissza** (visszaváltás csak 65 m
      fölött)
- [ ] Ha az idő még nem telt le, de odaértél: térkép + visszaszámláló látszik

**A felnyitás**

- [ ] Fekete felvezetés: „Recorded" + dátum + „x hónapja" **egyszerre** jelenik
      meg
- [ ] Utána **csak a kapszula** látszik, és megreped — ekkor még nincs szöveg
- [ ] A repedés után **minden felirat egyszerre** úszik be („It's yours." +
      hely + dátum + távolság)
- [ ] A teljes szekvencia kb. **7 másodperc**, és utána azonnal indul a videó
- [ ] Nincs többé külön fekete „pre-roll" a lejátszó előtt

**A videó után**

- [ ] A „Done" **nem dob fel fizetési falat**
- [ ] Friss telepítésnél: onboarding → paywall → **Vault** (nem Home)
- [ ] Már onboardolt felhasználónál: egyenesen a **Vault**
- [ ] A Vault odagörget a friss emlékhez, ami **arany átsuhanást** és egy finom
      rezgést kap
- [ ] Közvetlenül alatta a **„Keep this memory safe."** kártya, és ilyenkor az
      oldal alján lévő banner **nem látszik**
- [ ] A Vaultból újranézve *nincs* kiemelés és *nincs* átirányítás — a Back
      egyszerűen visszavisz

---

## ℹ️ AMI MÁR KÉSZ — nincs vele teendőd

Csak hogy tudd, mire ne pazarolj időt:

**Adatbázis (9 migráció, mind alkalmazva)**
`0019` merge grantok + audit · `0020` drop ledger + szerveroldali kvóta ·
`0021` review-belépés · `0022` RevenueCat termékek + webhook ·
`0023` merge idempotencia · `0024` megőrzési szabály · `0025` takarítás ·
`0026` megosztási kód sebességkorlátozása ·
`0028` `radar_switch_meters` (a térkép/radar váltás szerverről hangolható)

**Edge Functions (mind telepítve)**
`merge-anonymous-account` · `delete-user-account` · `revenuecat-webhook` ·
`purge-expired-capsules`

**Ütemezett feladat**
`free-capsule-purge` — naponta 03:17 UTC, aktív

**RevenueCat** (`proj0b348db1`)
2 app · 16 termék regisztrálva (14 sajátunk + 2 Test Store) · `pro`
entitlement · `default` + `packs` offering · webhook integráció beállítva,
titok a helyén

**Titkok beállítva**
`REVENUECAT_WEBHOOK_SECRET` · `PURGE_JOB_SECRET` · `reviewer_passcode_salt`

**Szerveroldalon letesztelve**
IDOR-védelem · kvóta-kikényszerítés · éves ciklus havi osztása · webhook
idempotencia · merge idempotencia · rate limit · megőrzési szabály

---

## 📌 Megjegyzések, amikről tudnod érdemes

**A meglévő 22 kapszulát a takarító job soha nem törli.** Nincs
`funding_bucket`-jük (a mező most született), és visszamenőleg nem tudjuk,
melyik volt ingyenes. Ez tudatos óvatosság.

**Az előfizetés nem hozzáférési kapu.** Aki nem fizet, továbbra is használja
az appot — csak a havi 10 drop és a „Megőrzés" funkció köthető előfizetéshez.

**A Test Store termékek (`monthly`, `yearly`) rajta vannak a `pro`
entitlementen.** Ez azért kell, hogy sandboxban tudj tesztelni, mielőtt a
store termékek léteznének. Éles kiadás előtt eltávolíthatod őket, ha zavar —
de kockázat nincs, a Test Store csak debug módban él.

**A megosztási kódok próbálgatása korlátozva van.** Felhasználónként 20
*sikertelen* keresés óránként. Szándékosan csak a sikertelenek számítanak: a
radar 3 másodpercenként pollozza ugyanezt a végpontot egy még feltöltés alatt
álló dropnál, tehát egy összesített limit azonnal eltörné az appot. A határ a
`system_settings.share_lookup_miss_hourly_limit` kulcsból hangolható.

Őszintén a korlátjáról: a regisztráció nyitott, tehát egy elszánt támadó
anonim fiókokat forgatva nullázhatja a saját számlálóját. Ez megdrágítja a
támadást (fiókonként egy regisztráció 20 tippenként, a Supabase saját IP-alapú
korlátai mellett), de nem teszi lehetetlenné. Ennél erősebbhez él-oldali,
IP-alapú korlátozás kellene.

**A címzetti folyamat újraépült (`fejlesztes.md` v3.0).** A vágólap-figyelés
megszűnt, a navigáció makró térképre + mikró radarra bomlott, a felnyítási
szertartás 14,6 mp-ről ~7,2 mp-re rövidült (a külön pre-roll beleolvadt), és a
videó utáni fizetési fal helyét a Vault vette át. Ami ebből **nem működik
automatikusan**: a deep link, amíg a 6–8. pont nincs kész — addig a link a
böngészőben nyílik, és onnan nem vezet vissza az appba.

**A `radar_switch_meters` szerverről hangolható.** Ha 50 m túl korainak vagy
túl késeinek bizonyul terepen, nem kell app-frissítés:

```sql
update public.system_settings set value = 65 where key = 'radar_switch_meters';
```

A hiszterézis automatikusan követi (visszaváltás mindig az érték 1,3-szorosánál).

**Nem commitoltam semmit.** A módosítások a working tree-ben vannak.
