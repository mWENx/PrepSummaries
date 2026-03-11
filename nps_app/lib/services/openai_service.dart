import 'dart:convert';
import 'package:http/http.dart' as http;

class OpenAIService {
  final String apiKey;
  final String model;
  static const _endpoint = 'https://api.openai.com/v1/responses';

  const OpenAIService(this.apiKey, {this.model = 'gpt-4.1-mini'});

  /// Sends a prompt with web search enabled. Returns raw text output.
  Future<String> searchWeb(String prompt) async {
    final response = await http.post(
      Uri.parse(_endpoint),
      headers: {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'model': model,
        'max_output_tokens': 16000,
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

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return _extractOutputText(json) ?? '';
  }

  /// Sends a prompt without web search. Returns raw text output.
  Future<String> complete(String prompt) async {
    final response = await http.post(
      Uri.parse(_endpoint),
      headers: {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'model': model,
        'max_output_tokens': 16000,
        'input': prompt,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception(
          'OpenAI API error ${response.statusCode}: ${response.body}');
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return _extractOutputText(json) ?? '';
  }

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
}
