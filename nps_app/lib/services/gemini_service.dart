import 'dart:convert';
import 'package:http/http.dart' as http;

class GeminiService {
  final String apiKey;
  static const _model = 'gemini-2.0-flash';

  const GeminiService(this.apiKey);

  /// Calls the Gemini API with Google Search grounding and returns
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

    final endpoint = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/$_model:generateContent?key=$apiKey');

    final response = await http.post(
      endpoint,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'contents': [
          {
            'parts': [
              {'text': prompt}
            ]
          }
        ],
        'tools': [
          {'google_search': {}}
        ],
      }),
    );

    if (response.statusCode != 200) {
      throw Exception(
          'Gemini API error ${response.statusCode}: ${response.body}');
    }

    final responseJson = jsonDecode(response.body) as Map<String, dynamic>;
    final outputText = _extractText(responseJson);
    if (outputText == null || outputText.trim().isEmpty) {
      throw Exception('Gemini returned an empty response.');
    }

    final parsed = _parseJson(outputText);
    final bio = parsed['biography'];
    if (bio == null) return [];
    if (bio is List) return bio.map((e) => e.toString()).toList();
    throw Exception("Expected 'biography' to be a list in the Gemini response.");
  }

  /// Extracts text from the Gemini generateContent response.
  static String? _extractText(Map<String, dynamic> json) {
    final candidates = json['candidates'] as List?;
    if (candidates == null || candidates.isEmpty) return null;
    final content = candidates[0]['content'] as Map<String, dynamic>?;
    if (content == null) return null;
    final parts = content['parts'] as List?;
    if (parts == null) return null;
    final buf = StringBuffer();
    for (final part in parts) {
      if (part['text'] != null) {
        buf.write(part['text']);
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
          'Could not parse JSON from Gemini response. Preview: '
          '${cleaned.length > 200 ? cleaned.substring(0, 200) : cleaned}');
    }
  }
}
