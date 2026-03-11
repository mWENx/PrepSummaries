import 'dart:convert';
import 'package:http/http.dart' as http;

class GeminiService {
  final String apiKey;
  final String model;

  const GeminiService(this.apiKey, {this.model = 'gemini-2.0-flash'});

  /// Sends a prompt with Google Search grounding enabled. Returns raw text.
  Future<String> searchWeb(String prompt) async {
    return _call(prompt, tools: [
      {'google_search': {}}
    ]);
  }

  /// Sends a prompt without web search. Returns raw text.
  Future<String> complete(String prompt) async {
    return _call(prompt);
  }

  Future<String> _call(String prompt,
      {List<Map<String, dynamic>>? tools}) async {
    final endpoint = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$apiKey');

    final body = <String, dynamic>{
      'contents': [
        {
          'parts': [
            {'text': prompt}
          ]
        }
      ],
    };
    if (tools != null) body['tools'] = tools;

    final response = await http.post(
      endpoint,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );

    if (response.statusCode != 200) {
      throw Exception(
          'Gemini API error ${response.statusCode}: ${response.body}');
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return _extractText(json) ?? '';
  }

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
}
