/// Supported LLM providers for biography generation.
enum LlmProvider {
  openai,
  gemini,
  claude;

  String get displayName => switch (this) {
        openai => 'OpenAI',
        gemini => 'Google Gemini',
        claude => 'Anthropic Claude',
      };

  String get keyHint => switch (this) {
        openai => 'sk-…',
        gemini => 'AIza…',
        claude => 'sk-ant-…',
      };

  /// Persistent key used in SharedPreferences.
  String get prefsKey => switch (this) {
        openai => 'openai_api_key',
        gemini => 'gemini_api_key',
        claude => 'claude_api_key',
      };

  /// Convert to/from string for storage.
  static LlmProvider fromString(String s) =>
      LlmProvider.values.firstWhere((e) => e.name == s,
          orElse: () => LlmProvider.openai);
}
