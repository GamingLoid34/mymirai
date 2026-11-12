# Migrationsplan: my_mirai → eget Firebase-projekt

**Mål:** Bryta loss my_mirai helt från La Familia (`la-familia-5d9f5`) och köra på ett eget Firebase-projekt (arbetsnamn `my-mirai-app-2025` — verifiera exakt projekt-ID i Fas 0).

**Roller:** Människan gör Fas 0 (Firebase Console). Cursor gör Fas 1–3 och 5 i kod. Fas 4 kräver beslut.

**Viktig skyddsregel under hela migreringen:** Deploya ALDRIG `firestore:rules`, `storage` eller `functions` mot `la-familia-5d9f5`. Efter Fas 1 skyddar `.firebaserc` mot misstag, men dubbelkolla `--project`-flaggan i varje kommando tills dess.

---

## Läget idag (verifierat i koden)

| Beroende | Var |
|---|---|
| Firebase-config pekar på La Familia | `lib/firebase_options.dart` (alla 4 plattformar: web, android, ios, windows) |
| Hårdkodat projekt-ID i feltexter | `lib/services/ai_service.dart` (7 st), `lib/screens/document_create_flow_screen.dart` (1 st) |
| Auth förutsätter La Familia | `lib/services/auth_service.dart` (endast `signInWithEmailAndPassword`, ingen registrering/reset), `lib/screens/sign_in_screen.dart` ("Skapa konto i La Familia-appen"), `lib/screens/missing_family_screen.dart` (återvändsgränd) |
| Datamodell familje-scopad | `familyId` på `homework`, `decks`, `flashcards`; läses från `users/{uid}.familyId` |
| Storage-paths | `families/{familyId}/homework/...` och `documents/{uid}/...` |
| Regler ägs av La Familia | `firebase/firestore.rules` (permissiv wildcard), `firebase/storage.rules` |
| Docs | `README.md` genomsyras av La Familia-instruktioner |

App-ID:n som ska registreras i nya projektet: Android `com.mymirai.my_mirai`, iOS `com.mymirai.myMirai`, Web (används även av Windows-builden).

---

## Fas 0 — Firebase Console (MÄNNISKAN, inte Cursor)

1. **Verifiera projektet.** Gå till console.firebase.google.com → hitta projektet → *Project settings* → notera exakt **Project ID** (visningsnamn ≠ projekt-ID; det kan vara `my-mirai-app-2025` eller något liknande). Skriv in det korrekta ID:t överallt där denna plan säger `<PROJEKT-ID>`.
2. **Blaze-plan.** Uppgradera till Blaze (krävs för Cloud Functions med utgående anrop till Anthropic/ElevenLabs/Google STT).
3. **Aktivera tjänster:**
   - Authentication → Sign-in method → **Email/Password** på.
   - Firestore → skapa databas om den inte finns. Region: **eur3** eller **europe-west1** (funktionerna ligger i europe-west1).
   - Storage → aktivera (samma region).
4. **Aktivera Cloud Speech-to-Text API** i Google Cloud Console för projektet (används av `transcribeRecording`/`transcribeUserAudio`).
5. **Registrera apparna** (Project settings → Add app):
   - Android: paketnamn `com.mymirai.my_mirai`
   - iOS: bundle-ID `com.mymirai.myMirai`
   - Web: en webbapp (Windows-builden återanvänder web-configen)
   - Ladda INTE ner config-filer manuellt — `flutterfire configure` i Fas 1 hämtar allt.
6. **Secrets** (från projektroten, efter att Firebase CLI är inloggat):
   ```bash
   firebase functions:secrets:set ANTHROPIC_API_KEY --project=<PROJEKT-ID>
   firebase functions:secrets:set ELEVENLABS_API_KEY --project=<PROJEKT-ID>
   ```
   Valfri param (annars används default-rösten): sätt `ELEVENLABS_VOICE_ID` vid deploy-prompt eller i `functions/.env.<PROJEKT-ID>`.

**Klart-kriterium Fas 0:** Projektet har Blaze, Auth (email/password), Firestore, Storage, STT-API aktiverat, tre appar registrerade och två secrets satta.

---

## Fas 1 — Peka om appen (CURSOR)

1. Kör om FlutterFire-konfigurationen:
   ```bash
   dart pub global activate flutterfire_cli
   flutterfire configure --project=<PROJEKT-ID> --platforms=android,ios,web,windows
   ```
   Detta skriver om `lib/firebase_options.dart`. Committa den nya versionen.
2. Skapa `.firebaserc` i projektroten (skydd mot feldeploy):
   ```json
   { "projects": { "default": "<PROJEKT-ID>" } }
   ```
3. Rensa hårdkodade `la-familia-5d9f5` i kod:
   - `lib/services/ai_service.dart` — 7 felmeddelanden nämner `--project=la-familia-5d9f5`. Ersätt med projektneutral text, t.ex. "Kör firebase deploy --only functions:<namn> mot appens Firebase-projekt (region europe-west1)." Hårdkoda INTE det nya ID:t i klientkod.
   - `lib/screens/document_create_flow_screen.dart` — samma sak (1 ställe).
   - `firebase/storage.rules` — uppdatera deploy-kommentaren högst upp.
4. Rör INTE `familyId`-logiken i denna fas — datamodellen behålls (se Fas 2).

**Klart-kriterium Fas 1:**
- `flutter run` loggar `[main] Firebase projectId=<PROJEKT-ID>`.
- `grep -ri "la-familia" lib/ functions/ firebase/` ger 0 träffar.
- Inloggning misslyckas ännu (inga konton i nya projektet) — det är väntat.

---

## Fas 2 — Egen auth & familje-bootstrap (CURSOR)

**Princip:** Behåll `familyId`-datamodellen (den är bra och genomsyrar allt), men my_mirai äger nu kontoskapande och familjeskapande själv.

### 2a. AuthService (`lib/services/auth_service.dart`)
- Lägg till `registerWithEmail(email, password)` → `createUserWithEmailAndPassword`.
- Lägg till `sendPasswordReset(email)` → `sendPasswordResetEmail`.
- Uppdatera feltexter som nämner La Familia ("Logga in i La Familia först…", "har du gått med i en familj i La Familia?") till my_mirai-egna formuleringar.

### 2b. Familje-bootstrap (ny logik, förslagsvis i AuthService.initialize)
Vid inloggning, om `users/{uid}` saknas ELLER saknar `familyId`:
1. Skapa `families/{autoId}`: `{ name: null, memberUids: [uid], createdAt: serverTimestamp() }`.
2. Skriv `users/{uid}`: `{ familyId: <autoId>, persona: null, email, createdAt }` (merge om dokumentet delvis finns).
3. Låt befintlig `needsPersonaOnboarding`-logik ta över (persona-pickern finns redan).

Detta gör `missing_family_screen` onåbar i normalflödet.

### 2c. UI
- `lib/screens/sign_in_screen.dart`: växel **Logga in / Skapa konto** + länk **Glömt lösenord?**. Ta bort texterna "Använder samma konto som La Familia" och "Skapa konto i La Familia-appen". Undertexten kan bli: "Läxor, läsning och repetition för hela familjen".
- `lib/screens/missing_family_screen.dart`: förenkla till en fallback med knappen **"Skapa familj"** (kör bootstrap-logiken) — eller ta bort skärmen helt om bootstrap gör den död. Behåll gärna en TODO-kommentar: "Gå med i befintlig familj via kod — framtida funktion (fler barn/vårdnadshavare)."

### 2d. Tester
- Uppdatera `test/auth_service_test.dart` (nya metoder + borttagna La Familia-antaganden).
- Nytt test: bootstrap skapar familj + user-dok vid första inloggning.

**Klart-kriterium Fas 2:** Ny användare kan i appen: skapa konto → familj skapas automatiskt → välja persona → landa på Hem. `flutter test` grönt.

---

## Fas 3 — Backend i nya projektet (CURSOR skriver, MÄNNISKAN kör deploy)

### 3a. Nya Firestore-regler — vi äger dem nu, härda direkt
Ersätt hela `firebase/firestore.rules` med Bilaga A. Notera: Cloud Functions använder Admin SDK och påverkas inte av reglerna, så serverside-skrivningar (flashcards, chat_turns m.m.) fortsätter fungera.

### 3b. Storage-regler
`firebase/storage.rules` behålls i sak (paths `families/{familyId}/homework/...` och `documents/{uid}/...` stämmer med koden). Uppdatera bara kommentarerna.

### 3c. Deploy (körs av människan, Cursor förbereder)
```bash
cd functions && npm ci && cd ..
firebase deploy --only firestore:rules,firestore:indexes,storage --project=<PROJEKT-ID>
firebase deploy --only functions --project=<PROJEKT-ID>
```
Första functions-deployen i ett nytt projekt aktiverar Cloud Build/Artifact Registry — godkänn prompterna.

**Klart-kriterium Fas 3:** Alla 21 funktioner listas som deployade i Console. I appen (med `--dart-define=USE_FIRESTORE_HOMEWORK=true`): skapa läxa med foto → text extraheras → sammanfattning genereras.

---

## Fas 4 — Data från La Familia-projektet (BESLUT KRÄVS)

- **Alternativ A — nystart (rekommenderas):** Inga steg. Konton och data skapas på nytt i nya projektet. Enklast och renast om befintlig data mest är test.
- **Alternativ B — migrera er familjs data:** Kräver ägaråtkomst till `la-familia-5d9f5`. En full `gcloud firestore export` tar ALLT (även La Familias övriga data) — gör istället ett engångsskript (Node, två Admin SDK-instanser) som kopierar dokument filtrerat på er `familyId` ur `homework`, `decks`, `flashcards`, samt `documents` + `user_stats` per uid, plus tillhörande Storage-filer. Auth-konton flyttas med `firebase auth:export/import` (kräver hash-parametrar från gamla projektets konsol) — eller enklare: skapa konton på nytt och mappa uid:n i skriptet.

Om Alternativ B väljs: be Claude om skriptspecen som separat arbetsorder.

---

## Fas 5 — Städning & slutverifiering (CURSOR)

1. **README.md**: skriv om — bort med alla La Familia-avsnitt; nya setup-steg (Fas 0-listan), deploy-kommandon med `--project=<PROJEKT-ID>`, korrigera även den inaktuella raden "Hastighet sparas inte mellan sessioner ännu" (hastigheten sparas numera via SharedPreferences).
2. **Sanity-grep** (ska ge 0 träffar utanför `docs/`-PDF:erna):
   ```bash
   grep -ri "la.familia" --include="*.dart" --include="*.ts" --include="*.rules" --include="*.json" --include="*.md" . | grep -v docs/
   ```
3. **Manuell slutchecklista** (mot nya projektet, molnläge på):
   - [ ] Skapa konto → familj auto-skapas → persona-val → Hem
   - [ ] Glömt lösenord skickar mail
   - [ ] Ny läxa manuellt + "Fota läxan" → extraktion → sammanfattning
   - [ ] Glosläxa: klistra in → parsa → gloskort
   - [ ] Matteläxa: foto → problem → förklara steg
   - [ ] Flashcards genereras, Dagens pass, Förhör med AI-bedömning
   - [ ] Gör ett test → resultat
   - [ ] TTS (enhetsröst) + Lyssningsberättelse (ElevenLabs)
   - [ ] Vuxen: dokument via fil + länk, premium-ljud, lyssningskö
   - [ ] Inspelning → transkribering (STT) → sammanfattning
   - [ ] Dokumentchatt
   - [ ] Andra användare kan INTE läsa er familjs data (testa med ett andra konto i en egen familj — reglerna ska blockera)

**Direkt efter migreringen** (egna arbetsordrar, nu möjliga eftersom vi äger projektet): F2 App Check (`enforceAppCheck: true` per funktion + App Check-registrering) och F1 kvoter per användare.

---

## Bilaga A — Ny `firebase/firestore.rules`

```
rules_version = '2';
// my_mirai — eget projekt. Vi äger dessa regler fullt ut.
// Cloud Functions använder Admin SDK och går förbi reglerna.
service cloud.firestore {
  match /databases/{database}/documents {

    function signedIn() {
      return request.auth != null;
    }

    function myFamilyId() {
      return get(/databases/$(database)/documents/users/$(request.auth.uid))
        .data.get('familyId', '');
    }

    // --- Användarprofil: bara ägaren ---
    match /users/{uid} {
      allow read, write: if signedIn() && request.auth.uid == uid;
    }

    // --- Familj: bara medlemmar ---
    match /families/{familyId} {
      allow read, update: if signedIn()
        && request.auth.uid in resource.data.memberUids;
      allow create: if signedIn()
        && request.auth.uid in request.resource.data.memberUids;
      // delete medvetet avstängt tills vidare
    }

    // --- Familje-scopad data: homework, decks, flashcards ---
    match /homework/{id} {
      allow read, update, delete: if signedIn()
        && resource.data.familyId == myFamilyId();
      allow create: if signedIn()
        && request.resource.data.familyId == myFamilyId();
    }
    match /decks/{id} {
      allow read, update, delete: if signedIn()
        && resource.data.familyId == myFamilyId();
      allow create: if signedIn()
        && request.resource.data.familyId == myFamilyId();
    }
    match /flashcards/{id} {
      allow read, update, delete: if signedIn()
        && resource.data.familyId == myFamilyId();
      allow create: if signedIn()
        && request.resource.data.familyId == myFamilyId();
    }

    // --- Vuxen-dokument: ägarstyrt (samma som tidigare utkast) ---
    match /documents/{docId} {
      allow read, delete: if signedIn()
        && resource.data.ownerUid == request.auth.uid;
      allow create: if signedIn()
        && request.resource.data.ownerUid == request.auth.uid;
      allow update: if signedIn()
        && resource.data.ownerUid == request.auth.uid
        && request.resource.data.ownerUid == resource.data.ownerUid;

      // Chatthistorik under dokumentet: bara dokumentägaren läser.
      // Skrivs av chatWithDocument (Admin SDK, förbi reglerna).
      match /chat_turns/{turnId} {
        allow read: if signedIn()
          && get(/databases/$(database)/documents/documents/$(docId))
               .data.ownerUid == request.auth.uid;
        allow write: if false;
      }
    }

    // --- Statistik: bara ägaren ---
    match /user_stats/{uid} {
      allow read, write: if signedIn() && request.auth.uid == uid;
      match /daily/{day} {
        allow read, write: if signedIn() && request.auth.uid == uid;
      }
    }

    // INGEN wildcard. Allt annat är stängt per default.
  }
}
```

Kända avvägningar: `myFamilyId()` gör en `get()` per regelutvärdering (kostar en läsning). Acceptabelt nu; kan senare ersättas med custom claims. Om någon skärm läser/skriver en collection som inte listas ovan kommer den att få `permission-denied` — det är ett fynd, inte ett fel: lägg då till en explicit regel.

## Bilaga B — Exakta filer som röres

| Fil | Fas | Ändring |
|---|---|---|
| `lib/firebase_options.dart` | 1 | Regenereras av flutterfire |
| `.firebaserc` (ny) | 1 | Default-projekt |
| `lib/services/ai_service.dart` | 1 | 7 feltexter avprojektifieras |
| `lib/screens/document_create_flow_screen.dart` | 1 | 1 feltext |
| `lib/services/auth_service.dart` | 2 | registrering, reset, bootstrap, feltexter |
| `lib/screens/sign_in_screen.dart` | 2 | Skapa konto + Glömt lösenord, texter |
| `lib/screens/missing_family_screen.dart` | 2 | Skapa familj-fallback (eller tas bort) |
| `test/auth_service_test.dart` | 2 | Uppdateras + bootstrap-test |
| `firebase/firestore.rules` | 3 | Ersätts med Bilaga A |
| `firebase/storage.rules` | 3 | Endast kommentarer |
| `README.md` | 5 | Skrivs om |

## Bilaga C — Kommandoreferens

```bash
# Fas 1
flutterfire configure --project=<PROJEKT-ID> --platforms=android,ios,web,windows

# Fas 3
cd functions && npm ci && cd ..
firebase deploy --only firestore:rules,firestore:indexes,storage --project=<PROJEKT-ID>
firebase deploy --only functions --project=<PROJEKT-ID>

# Köra appen i molnläge
flutter run --dart-define=USE_FIRESTORE_HOMEWORK=true

# Fas 5 sanity
grep -ri "la.familia" --include="*.dart" --include="*.ts" --include="*.rules" --include="*.json" --include="*.md" . | grep -v docs/
```
