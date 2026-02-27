# Medcalc backlog (EPIC -> stories -> tasks)

## EPIC 1: Programstruktur och åtkomst

### Story 1.1 - Utöka användarprofil för studieprogram
**Mål:** Profilen kan styra synlighet för högre utbildningsmoduler.

**Tasks**
- [x] Lägg till `educationLevel` i `AppUser`.
- [x] Lägg till `activePrograms` i `AppUser`.
- [x] Lägg till feature flag `featureFlags.medcalc` i `AppUser`.
- [x] Lägg till hjälpregler: `hasNursingProgram`, `canSeeStudyPrograms`.

### Story 1.2 - Adminflöde för att sätta nivå/program
**Mål:** Medlemmar kan få rätt nivå och program direkt vid skapande.

**Tasks**
- [x] Lägg till nivåval i `ManageMembersPage`.
- [x] Lägg till switch för `nursing_rn`.
- [x] Lägg till switch för medcalc-feature flag.
- [x] Spara fälten i `users` vid skapande.

### Story 1.3 - Synlighetsregel på Hem
**Mål:** Studieprogram-kort visas endast när användaren har åtkomst.

**Tasks**
- [x] Visa "Studieprogram"-kort villkorat i `HomePage`.
- [x] Dölj kortet för grundskola/inaktiverad profil.
- [x] Länka kortet till programsidan.

---

## EPIC 2: Navigation och modulskal (MVP)

### Story 2.1 - Programsida
**Mål:** Användaren kan öppna tillgängligt program.

**Tasks**
- [x] Skapa `StudyProgramsPage`.
- [x] Visa "Sjuksköterskeprogrammet" som kort.
- [x] Hantera läge där program inte är aktiverat.

### Story 2.2 - Modulsida för sjuksköterskeprogram
**Mål:** Programmet visar modul "Läkemedelsberäkning (Säker)".

**Tasks**
- [x] Skapa `NursingProgramPage`.
- [x] Lägg modulkort med tydlig etikett.
- [x] Navigera till modulens startsida.

### Story 2.3 - Lägesval i modulen
**Mål:** Både Träna och Tentamode finns i första iteration.

**Tasks**
- [x] Skapa `MedcalcLandingPage`.
- [x] Lägg två val: Träna / Tentamode.
- [x] Skapa separata fungerande sidor för båda lägen.

---

## EPIC 3: Säker beräkningsmotor (nästa steg)

### Story 3.1 - Deterministisk motor
**Tasks**
- [x] Skapa motor med decimal/fixed-point.
- [x] Definiera formelset v1 (mg/kg, mg/ml->ml, ml/h, C1V1=C2V2).
- [x] Bygg dubbelberäkning (metod A/B) och mismatch-spärr.

### Story 3.2 - Validering och enheter
**Tasks**
- [x] Tvingade enheter i inputschema.
- [x] Rimlighetskontroller och tydliga fel.
- [x] Stoppa beräkning vid ofullständiga/inkonsekventa värden.

### Story 3.3 - Träna/Tentamode-funktionalitet
**Tasks**
- [x] Frågebank i Firestore med facit och metadata.
- [x] Träna med stegförklaring.
- [x] Tentamode med poäng och tidtagning.

---

## EPIC 4: Kvalitet och release-gates

### Story 4.1 - Dataloggning
**Tasks**
- [x] Lägg till `medcalc_sessions`.
- [x] Lägg till `medcalc_attempts` med inputs/resultat/versionsfält.

### Story 4.2 - Test och CI-gates
**Tasks**
- [x] Golden testbank med facit.
- [x] Krav: 100% pass innan deploy.
- [x] Blockera release vid mismatch eller osäker validering.
