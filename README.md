# My Mirai

Pedagogisk läx- och pluggapp för barn och familjer, med AI-verktyg, gamification och stöd för dyslexi.

## Teknikstack

- **Flutter** (Mobil & Web)
- **Firebase** (Firestore för users, homeworks, subjects)
- **Groq API** (LLaMA-4) för AI

## Förberedelser

### 1. Firebase

Lägg till dina Firebase-konfigurationsfiler:

- **Android**: `android/app/google-services.json`
- **iOS**: `ios/Runner/GoogleService-Info.plist`
- **Web**: Konfigurera i Firebase Console

Alternativt kör:

```bash
dart pub global activate flutterfire_cli
flutterfire configure
```

### 2. Groq API-nyckel

Kör appen med din Groq API-nyckel:

```bash
flutter run --dart-define=GROQ_API_KEY=din_nyckel
```

## Firestore-struktur

- **users**: `name`, `email`, `password`, `color`, `role` (barn/foralder/admin), `schoolYear` (1–9)
- **homeworks**: `title`, `subject`, `originalText`, `flashcards`, `aiSummary`, `substeps`, `imagesBase64`, `languageCode`
- **subjects**: `name`, `color`, `icon`

## Moduler

- **Login** – egen auth mot Firestore users
- **Hem** – Ryggsäcken (profilväxlare), energipoäng, senaste läxor, ämnen
- **Admin** – Hantera medlemmar (föräldrar)
- **Läxor** – Text, foto, .pptx, TTS, AI-sammanfattning, checklistor, frågor, glosor
- **Kort** – Flashcards med Spaced Repetition (Nivå 0–2+)
- **Matte** – Slumptal + AI-lästal (årskurs 1–9)
