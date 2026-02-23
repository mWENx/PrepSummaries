import 'dart:convert';
import 'package:http/http.dart' as http;

class OpenAIService {
  final String apiKey;
  static const _endpoint = 'https://api.openai.com/v1/responses';
  static const _model = 'gpt-4.1-mini';

  const OpenAIService(this.apiKey);

  /// Calls the OpenAI Responses API with web search enabled and returns
  /// the biography bullet list for the given donor.
  Future<List<String>> fetchBiography({
    required String donorName,
    required String employer,
    required String jobTitle,
    required String affiliation,
  }) async {
    final prompt = '''
Search the web for $donorName.

Only use:
- company websites
- LinkedIn
- other reputable sources

Verify identity by confirming:
- worked as $jobTitle at $employer
- affiliated with Northwestern University

Return ONLY valid JSON with this schema:

{
  "found": boolean,
  "biography": [string],
  "sources": [string]
}

The strings in "biography" should follow this general order:
1st string: current position, how long it's been, and primary responsibilities
2nd to Nth string: previous positions, likewise include length of term and primary responsibilities. Can split into multiple strings if extensive.
(N+1)th string: Educational background
(N+2)th string: where they are currently based if the info is available
Last string: any personal notes, like who they're married to

DO NOT include any text outside the JSON.
''';

    final response = await http.post(
      Uri.parse(_endpoint),
      headers: {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'model': _model,
        'input': prompt,
        'tools': [
          {'type': 'web_search_preview'}
        ],
      }),
    );

    if (response.statusCode != 200) {
      throw Exception(
          'OpenAI API error ${response.statusCode}: ${response.body}');
    }

    final responseJson = jsonDecode(response.body) as Map<String, dynamic>;
    final outputText = _extractOutputText(responseJson);
    if (outputText == null || outputText.trim().isEmpty) {
      throw Exception('OpenAI returned an empty response.');
    }

    final parsed = _parseJson(outputText);
    final bio = parsed['biography'];
    if (bio == null) return [];
    if (bio is List) return bio.map((e) => e.toString()).toList();
    throw Exception("Expected 'biography' to be a list in the OpenAI response.");
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  /// Extracts the assistant text from the Responses API output array.
  static String? _extractOutputText(Map<String, dynamic> json) {
    final output = json['output'] as List?;
    if (output == null) return null;
    for (final item in output) {
      if (item['type'] == 'message') {
        final content = item['content'] as List?;
        if (content != null) {
          for (final c in content) {
            if (c['type'] == 'output_text') {
              return c['text'] as String?;
            }
          }
        }
      }
    }
    return null;
  }

  /// Parses JSON from the model output, stripping ```json fences if present.
  static Map<String, dynamic> _parseJson(String text) {
    var cleaned = text.trim();

    if (cleaned.startsWith('```')) {
      final lines = cleaned.split('\n');
      // Drop the opening fence line and the closing ``` line
      cleaned = lines
          .skip(1)
          .where((l) => l.trim() != '```')
          .join('\n')
          .trim();
      if (cleaned.endsWith('```')) {
        cleaned = cleaned.substring(0, cleaned.length - 3).trim();
      }
    }

    try {
      return jsonDecode(cleaned) as Map<String, dynamic>;
    } catch (_) {
      // Fallback: extract the first {...} block
      final match = RegExp(r'\{[\s\S]*\}').firstMatch(cleaned);
      if (match != null) {
        return jsonDecode(match.group(0)!) as Map<String, dynamic>;
      }
      throw Exception(
          'Could not parse JSON from OpenAI response. Preview: '
          '${cleaned.length > 200 ? cleaned.substring(0, 200) : cleaned}');
    }
  }
}
