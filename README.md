# my_mirai

Flutter-app för att hantera skolläxor (åk 2–9) med stöd för innehåll, bilagor och molnlagring när Firebase är aktiverat.

## Körning

- Installera [Flutter](https://docs.flutter.dev/get-started/install) och kör `flutter pub get` i projektroten.
- Starta med `flutter run`. Standardläget öppnar barnets läxor direkt och sparar uppgifter och övningssteg på enheten mellan starter.
- För att använda Firestore, AI-funktioner m.m.: följ avsnittet [Cloud Functions & AI-features](#cloud-functions--ai-features) nedan.

## Läxor från SchoolSoft och Vardag

1. Öppna **Hem → Läxor från veckobrev → Hämta från Vardag**. Logga in med ett befintligt vuxenkonto i Vardag och välj ett SchoolSoft-brev. Du kan även klistra in text, dela brevtext från Android eller prova med exempelbrevet.
2. Granska förslagen mot originalet. Pennan öppnar rubrik, ämne, uppgift och sista dag. Veckodagar utan ett entydigt datum finns kvar i uppgiftstexten. Du kan själv lägga till en missad uppgift. **Spara valda** lägger läxorna på den här enheten och känner igen en upprepad import av samma brev.
3. Öppna en läxa från **Hem** eller **Läxor**. Öva på glospar och enkla räknetal ur uppgiften, eller följ läs- och arbetssteg. Du kan lyssna med enhetens röst, be om en ledtråd och återuppta nästa steg senare. **Skriv en egen läxa** fungerar även utan veckobrev.

My Mirai hämtar RSS-poster ur Vardags samling `notes` på begäran. Den tillfälliga inloggningen avslutas efter hämtning. Vardags regler avgör åtkomsten till familjens och den inloggades egna brev. Källans RSS-adress behövs bara i Vardag. Sparade läxor tillhör den lokala läxlistan på enheten.

Bygg Androidversionen med `flutter build apk --release`. För ett testpaket som kan installeras bredvid en äldre My Mirai använder du `ORG_GRADLE_PROJECT_miraiTestApp=true flutter build apk --release`. För ett isolerat prov av inloggningen och inkorgen kan ett debugbygge använda `--dart-define=MIRAI_TEST_VARDAG_EMULATOR=true` med projektet `demo-mirai`, Auth på port 9134 och Firestore på port 8134 med Vardags befintliga regler.

## Cloud Functions & AI-features

Anropbara Cloud Functions (region `europe-west1`) använder Anthropic via en hemlig API-nyckel:

- `summarizeHomework` — läx-/dokumenttext → kort sammanfattning. Tar `audience`: `child` (standard, läxor) eller `adult` (vuxen-dokumentflödet).
- `extractTextFromAttachment` — bakom knappen **Extrahera text från bilaga** (läser uppladdad fil i Storage)
- `generateFlashcards` — bakom **Generera** under **Skapa flashcards** i läsläget (läxa → måste ha **sammanfattning**, sedan AI-skapade kort i Firestore)
- `gradeAnswer` — **Förhör**: bedömer elevens fritextsvar mot ett kort och returnerar `verdict` + `feedback`
- `generateTest` — **Gör ett test** (barn): slumpade öppna + flervalfrågor från valda lekar (`deckIds`, `count`, `mixWithMultipleChoice`)
- `extractFromUrl` — **Nytt dokument → Importera länk**: hämtar HTML, extraherar artikel (`@mozilla/readability` på servern), returnerar `title` + `text` + `sourceType: article`

1. **Installera beroenden**

   ```bash
   cd functions
   npm install
   ```

2. **Hemlig API-nyckel** (för [Anthropic](https://console.anthropic.com/) — lägg aldrig nyckel i källkoden eller i appar):

   ```bash
   firebase functions:secrets:set ANTHROPIC_API_KEY
   ```

3. **Bygga och deploya funktioner**

   Deploya bara de funktioner du ändrat (exempel):

   ```bash
   firebase deploy --only functions:summarizeHomework --project=<la-familia-project-id>
   ```

   Full deploy av alla funktioner går också (samma repo som La Familia):

   ```bash
   firebase deploy --only functions --project=<la-familia-project-id>
   ```

4. **Lokal emulator (endast funktioner)**

   ```bash
   firebase emulators:start --only functions
   ```

5. **Flutter med Firestore- och molnstöd** (körbar AI-knapp och synk) — använd miljövariabel med `--dart-define`:

   ```bash
   flutter run --dart-define=USE_FIRESTORE_HOMEWORK=true
   ```

   Utan `USE_FIRESTORE_HOMEWORK=true` startar appen med beständiga lokala läxor och övningar. Molnfunktionerna nedan hör till det separata Firestore-läget.

6. I produktion/riktig inloggning: se till att användaren är inloggad med Firebase Auth så att anropen får `context.auth` på servern.

## Flashcards & studier

Flashcards visas i läsläget under varje läxa när **`USE_FIRESTORE_HOMEWORK`** är sant.

1. **Flödet:** hämtad eller skriven läxtext → **sammanfattning** (`summarizeHomework`) → **Skapa flashcards** → Callable **`generateFlashcards`** läser läxans `summary`, anropar Anthropic och skriver ett **deck** (`decks`) + **kort** (`flashcards`) samt **sätter `homework.linkedDeckId`** på serversidan.

2. **I appen idag:** studie-/quizläge per deck (**SM‑2**), **Förhör** (fritext → `gradeAnswer`), samt **Plugga inför prov** (välj ämneslekar → blandad frågesession). I standardläget finns i stället de lokala övningarna som beskrivs ovan.

3. **Deploy bara vad du ändrat** — oftast `--only functions:…`. **Firestore-regler** i det här repot är tänkta som förslag/avstämning med La Familia: publicera/uppdatera regler i Firebase Console bara om det är överenskommet; **deploya inte** `firestore:rules` på autopilot om La Familia redan äger säkerhetsmodellen. **Index**: om du lägger till nya compound-queries, kör vid behov `firebase deploy --only firestore:indexes` efter kört konsolens förslag (samma förbehåll som för regler).

   ```bash
   firebase deploy --only functions:generateFlashcards --project=<la-familia-project-id>
   ```

## Dokument & personer (vuxen)

- Vid inloggning väljs **persona** (`child` / `adult` / `both`) och sparas på `users/{uid}.persona`.
- **Vuxenläge** visar **dokumentbibliotek** (Firestore `documents`, ägarstyrt). Dokumentsammanfattning använder **`summarizeHomework` med `audience: adult`**. Konton med **both** växlar Barn/Vuxen på **Hem** i vuxenläget (segmentknapp); i barnläget öppnar du personsymbolen högst till höger → **Visningsläge** + **Logga ut**.

## Textextrahering

Efter att en läxa **sparats** med en bilaga i molnet kan du i redigeringsvyn klicka **Extrahera text från bilaga**. Då körs `extractTextFromAttachment` som:

- **PDF** med textlager: läser text (första 30 sidorna) med `pdf-parse` på servern.
- **DOCX**: råtext via `mammoth`.
- **Bilder** (t.ex. JPG, PNG, WebP, HEIC): OCR via Claude vision (Haiku).

**Scannade PDF:er utan textlager** ger inget utdrag i fältet utan ett tydligt meddelande: ta **foto** av sidan tills OCR på skannade PDF:er finns i en senare version. Samma deploy räcker: `firebase deploy --only functions` (inga nya CLI-steg utöver `npm install` i `functions/` om beroenden ändrats).

## Lyssna (TTS)

Appen kan läsa upp läxans sammanfattning (eller hela texten om sammanfattning saknas) med en bottom sheet-player.

- Använder enhetens system-TTS (gratis) via `flutter_tts`, ingen extra backend-konfiguration.
- Svenska röster ställs in i mobilen:
  - Android: **Settings → Language & input → Text-to-speech**
  - iOS: **Inställningar → Tillgänglighet → Talat innehåll → Röster**
- Om svensk röst saknas används engelsk fallback-röst (`en-US`) och en varning visas en gång.
- Hastighet sparas inte mellan sessioner ännu.

## Inloggning & Firebase-setup

my_mirai delar Firebase-projekt med La Familia. Det betyder samma användarkonton,
samma familjer, samma `users/{uid}`-profiler.

### Engångskonfiguration

1. Hitta La Familias project-id (se `lib/firebase_options.dart` i La Familia-projektet,
   värdet på `projectId`).

2. Aktivera FlutterFire CLI om det inte redan är gjort:

   ```bash
   dart pub global activate flutterfire_cli
   ```

3. Kör i my_mirai-projektroten:

   ```bash
   flutterfire configure --project=<la-familia-project-id>
   ```

   Välj: Android, iOS (web/macos/windows valfritt). Detta skriver:
   - `lib/firebase_options.dart`
   - `android/app/google-services.json`
   - `ios/Runner/GoogleService-Info.plist`

4. INGA av dessa tre filer ska checkas in (`.gitignore` hanterar det).

5. Verifiera i Firebase Console (rätt projekt!) att:
   - `Authentication` → `Sign-in method` → `Email/Password` är aktiverad
   - Firestore Rules tillåter dig att läsa `users/{uid}` för dig själv

### Köra appen

```bash
flutter run --dart-define=USE_FIRESTORE_HOMEWORK=true
```

Vid start skrivs `[main] Firebase projectId=...` ut. Verifiera att det är
La Familias project-id, inte något annat.

### Kodkvalitet (lokal / CI)

- `flutter analyze --fatal-warnings` — måste vara utan fel varning i kvalitetssynkron.
- `flutter test`

**AuthGate:** är en `StatefulWidget` som återanvänder **`FirestoreDeckRepository`** för ett givet `familyId` mellan notifieringar från `AuthService`; en ny instans skapas bara vid byte av familjekontext (inte vid varje `build`). `DocumentRepository` (`FirestoreDocumentRepository.watchOne`) används som tidigare för dokumentstreams.

### Logga in

Använd exakt samma e-post + lösenord som i La Familia. Måste vara skapat där först —
my_mirai har inget signup-flöde och skapar inga familjer.

### Felsökning

- "Inloggning misslyckades" + felkod `user-not-found`: kontot finns inte i detta
  Firebase-projekt. Kontrollera projectId i konsolen.
- Missing-family-skärm: du är inloggad men `users/{uid}.familyId` är tomt.
  Logga in i La Familia, gå med i eller skapa en familj där, kom tillbaka.
- "Saknar behörighet": Firestore-reglerna i La Familia-projektet tillåter inte läsning.
  Kontakta admin / kontrollera reglerna.
- Det gamla my_mirai-Firebase-projektet är frikopplat men inte raderat. Det går bra att
  låta det ligga — det används inte längre. Vill du städa upp det manuellt:
  Firebase Console → välj gamla projektet → Project settings → längst ner "Delete project".

## Felsökning

- `cd functions && npm run lint` och `npm run build` före deploy (kör också automatiskt som predeploy om du använder `firebase deploy` med den medföljande `firebase.json`).

### Planerat senare

- OCR-fallback för skannade PDF:er, auto-extrahering direkt vid uppladdning, samt valfri årskurs (`gradeHint`) i gränssnittet för sammanfattning.
- TTS: spara uppläsningshastighet mellan sessioner.
- Dokument: rikare import (t.ex. Drive), mer robust länk/läshämtning om det behövs.
- Hem: tydligare CTA till studier när hjäläxans länkade deck har kort som är **due** (SM‑2).
