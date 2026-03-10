import 'dart:convert';
import 'package:http/http.dart' as http;

class ClaudeService {
  final String apiKey;
  static const _endpoint = 'https://api.anthropic.com/v1/messages';
  static const _model = 'claude-sonnet-4-6';

  const ClaudeService(this.apiKey);

  /// Calls the Anthropic Messages API with web search and returns
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
        'x-api-key': apiKey,
        'anthropic-version': '2023-06-01',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'model': _model,
        'max_tokens': 4096,
        'tools': [
          {
            'type': 'web_search_20250305',
            'name': 'web_search',
            'max_uses': 5,
          }
        ],
        'messages': [
          {
            'role': 'user',
            'content': prompt,
          }
        ],
      }),
    );

    if (response.statusCode != 200) {
      throw Exception(
          'Claude API error ${response.statusCode}: ${response.body}');
    }

    final responseJson = jsonDecode(response.body) as Map<String, dynamic>;
    final outputText = _extractText(responseJson);
    if (outputText == null || outputText.trim().isEmpty) {
      throw Exception('Claude returned an empty response.');
    }

    final parsed = _parseJson(outputText);
    final bio = parsed['biography'];
    if (bio == null) return [];
    if (bio is List) return bio.map((e) => e.toString()).toList();
    throw Exception(
        "Expected 'biography' to be a list in the Claude response.");
  }

  /// Extracts text from the Claude Messages API response.
  static String? _extractText(Map<String, dynamic> json) {
    final content = json['content'] as List?;
    if (content == null) return null;
    final buf = StringBuffer();
    for (final block in content) {
      if (block['type'] == 'text') {
        buf.write(block['text']);
      }
    }
    return buf.isEmpty ? null : buf.toString();
  }

  static Map<String, dynamic> _parseJson(String text) {
    var cleaned = text.trim();

    if (cleaned.startsWith('```')) {
      final lines = cleaned.split('\n');
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
      final match = RegExp(r'\{[\s\S]*\}').firstMatch(cleaned);
      if (match != null) {
        return jsonDecode(match.group(0)!) as Map<String, dynamic>;
      }
      throw Exception(
          'Could not parse JSON from Claude response. Preview: '
          '${cleaned.length > 200 ? cleaned.substring(0, 200) : cleaned}');
    }
  }
}
