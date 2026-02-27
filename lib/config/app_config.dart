/// App-konfiguration. Groq API-nyckel sätts via --dart-define vid körning:
/// flutter run --dart-define=GROQ_API_KEY=din_nyckel
class AppConfig {
  static const groqApiKey = String.fromEnvironment('GROQ_API_KEY', defaultValue: '');
}
