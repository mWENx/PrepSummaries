import 'dart:convert';
import 'package:http/http.dart' as http;

class ClaudeService {
  final String apiKey;
  static const _endpoint = 'https://api.anthropic.com/v1/messages';
  static const _model = 'claude-sonnet-4-6';

  const ClaudeService(this.apiKey);

  /// Sends a prompt with web search enabled. Returns raw text.
  Future<String> searchWeb(String prompt) async {
    return _call(prompt, tools: [
      {
        'type': 'web_search_20250305',
        'name': 'web_search',
        'max_uses': 20,
      }
    ]);
  }

  /// Sends a prompt without web search. Returns raw text.
  Future<String> complete(String prompt) async {
    return _call(prompt);
  }

  Future<String> _call(String prompt,
      {List<Map<String, dynamic>>? tools}) async {
    final body = <String, dynamic>{
      'model': _model,
      'max_tokens': 4096,
      'messages': [
        {'role': 'user', 'content': prompt}
      ],
    };
    if (tools != null) body['tools'] = tools;

    final response = await http.post(
      Uri.parse(_endpoint),
      headers: {
        'x-api-key': apiKey,
        'anthropic-version': '2023-06-01',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(body),
    );

    if (response.statusCode != 200) {
      throw Exception(
          'Claude API error ${response.statusCode}: ${response.body}');
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return _extractText(json) ?? '';
  }

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
}
