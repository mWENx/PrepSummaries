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

  /// Persistent key used in SharedPreferences for the API key.
  String get prefsKey => switch (this) {
        openai => 'openai_api_key',
        gemini => 'gemini_api_key',
        claude => 'claude_api_key',
      };

  /// Persistent key used in SharedPreferences for the selected model.
  String get modelPrefsKey => switch (this) {
        openai => 'openai_model',
        gemini => 'gemini_model',
        claude => 'claude_model',
      };

  /// Available models for this provider.
  /// Cost estimate assumes 7 calls (3 search + verify + LinkedIn extract/check + bio write).
  List<LlmModel> get models => switch (this) {
        openai => const [
            LlmModel('gpt-4.1-mini', 'GPT-4.1 Mini', 0.15),
            LlmModel('gpt-4.1', 'GPT-4.1', 1.50),
            LlmModel('gpt-4.1-nano', 'GPT-4.1 Nano', 0.06),
            LlmModel('gpt-4o', 'GPT-4o', 1.25),
            LlmModel('gpt-4o-mini', 'GPT-4o Mini', 0.12),
          ],
        gemini => const [
            LlmModel('gemini-2.0-flash', 'Gemini 2.0 Flash', 0.04),
            LlmModel('gemini-2.5-flash-preview-05-20', 'Gemini 2.5 Flash', 0.08),
            LlmModel('gemini-2.5-pro-preview-05-06', 'Gemini 2.5 Pro', 0.80),
          ],
        claude => const [
            LlmModel('claude-sonnet-4-6', 'Claude Sonnet 4', 1.00),
            LlmModel('claude-haiku-4-5-20251001', 'Claude Haiku 4.5', 0.25),
          ],
      };

  /// Default model ID for this provider.
  String get defaultModel => models.first.id;

  /// Convert to/from string for storage.
  static LlmProvider fromString(String s) =>
      LlmProvider.values.firstWhere((e) => e.name == s,
          orElse: () => LlmProvider.openai);
}

/// A specific model within a provider.
class LlmModel {
  final String id;
  final String displayName;

  /// Estimated max cost per run (7 API calls) in USD.
  final double estimatedCostPerRun;

  const LlmModel(this.id, this.displayName, this.estimatedCostPerRun);

  /// Formatted cost string for display.
  String get costLabel => 'up to \$${estimatedCostPerRun.toStringAsFixed(2)}/run';
}
