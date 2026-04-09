import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'bio_prompt.dart';
import 'bio_result.dart';
import 'excel_service.dart';
import 'llm_provider.dart';
import 'openai_service.dart';
import 'gemini_service.dart';
import 'claude_service.dart';
import 'event_docx_service.dart';

class EventGeneratorService {
  /// Generates a combined event briefing document for [selectedDonors].
  /// Yields status messages; the final yield is the output file path.
  static Stream<String> generate({
    required String excelPath,
    required String outputDir,
    required List<String> selectedDonors,
    required String apiKey,
    required LlmProvider provider,
    String? model,
  }) async* {
    final total = selectedDonors.length;
    final donorEntries = <EventDonorEntry>[];

    for (int i = 0; i < selectedDonors.length; i++) {
      final name = selectedDonors[i];
      yield 'Donor ${i + 1}/$total — Reading data for $name…';
      final donorData =
          ExcelService.extractDonorData(excelPath, targetName: name);

      // ── Web search (3 parallel searches) ─────────────────────────────
      yield 'Donor ${i + 1}/$total — Searching the web for $name…';
      final results = await Future.wait([
        _searchWeb(provider, apiKey,
            BioPrompt.buildSearchPromptCareer(
              donorName: donorData.donorName,
              employer: donorData.primaryEmployer,
              jobTitle: donorData.donorJobTitle,
              affiliation: donorData.donorAffiliation,
            ),
            model: model),
        _searchWeb(provider, apiKey,
            BioPrompt.buildSearchPromptEducation(
              donorName: donorData.donorName,
              employer: donorData.primaryEmployer,
              jobTitle: donorData.donorJobTitle,
              affiliation: donorData.donorAffiliation,
            ),
            model: model),
        _searchWeb(provider, apiKey,
            BioPrompt.buildSearchPromptPersonal(
              donorName: donorData.donorName,
              employer: donorData.primaryEmployer,
              jobTitle: donorData.donorJobTitle,
              affiliation: donorData.donorAffiliation,
            ),
            model: model),
      ]);

      // Deduplicate excerpts
      final webExcerpts = <SearchExcerpt>[];
      final seenUrls = <String>{};
      final seenTitles = <String>{};
      for (final response in results) {
        for (final excerpt in BioPrompt.parseSearchResult(response)) {
          final normUrl = excerpt.url
              .split('?').first
              .split('#').first
              .replaceAll(RegExp(r'/+$'), '')
              .toLowerCase();
          final normTitle = excerpt.title.trim().toLowerCase();
          if (seenUrls.contains(normUrl) ||
              (normTitle.isNotEmpty && seenTitles.contains(normTitle))) {
            continue;
          }
          seenUrls.add(normUrl);
          if (normTitle.isNotEmpty) seenTitles.add(normTitle);
          webExcerpts.add(excerpt);
        }
      }

      List<String> bioNotes = [];

      if (webExcerpts.isNotEmpty) {
        // ── Verify sources ──────────────────────────────────────────────
        yield 'Donor ${i + 1}/$total — Verifying sources for $name…';
        final verifyPrompt = BioPrompt.buildVerifyPrompt(
          donorName: donorData.donorName,
          employer: donorData.primaryEmployer,
          jobTitle: donorData.donorJobTitle,
          affiliation: donorData.donorAffiliation,
          excerpts: webExcerpts,
        );
        final verifyResponse =
            await _complete(provider, apiKey, verifyPrompt, model: model);
        final verified = BioPrompt.parseVerifyResult(verifyResponse, webExcerpts)
            .where((e) => e.verified)
            .toList();

        if (verified.isNotEmpty) {
          // ── Write biography ───────────────────────────────────────────
          yield 'Donor ${i + 1}/$total — Writing biography for $name…';
          final bioPrompt = BioPrompt.buildBioPrompt(
            donorName: donorData.donorName,
            verifiedExcerpts: verified,
          );
          final bioResponse =
              await _complete(provider, apiKey, bioPrompt, model: model);
          bioNotes = BioPrompt.parseBioResult(bioResponse);
        }
      }

      donorEntries.add(EventDonorEntry(
        mergeFields: donorData.mergeFields,
        bioNotes: bioNotes,
      ));
    }

    yield 'Building event briefing document…';

    final templateData =
        await rootBundle.load('assets/templates/event_briefing_template.docx');
    final templateBytes = templateData.buffer.asUint8List();

    final outputPath = _outputPath(outputDir);
    await EventDocxService.fillEventTemplate(
      templateBytes: templateBytes,
      outputPath: outputPath,
      donors: donorEntries,
    );

    yield outputPath;
  }

  static String _outputPath(String outputDir) {
    final date = DateTime.now().toIso8601String().split('T').first;
    return p.join(outputDir, 'Event Briefing $date.docx');
  }

  static Future<String> _searchWeb(
      LlmProvider provider, String apiKey, String prompt,
      {String? model}) {
    switch (provider) {
      case LlmProvider.openai:
        return OpenAIService(apiKey, model: model ?? provider.defaultModel)
            .searchWeb(prompt);
      case LlmProvider.gemini:
        return GeminiService(apiKey, model: model ?? provider.defaultModel)
            .searchWeb(prompt);
      case LlmProvider.claude:
        return ClaudeService(apiKey, model: model ?? provider.defaultModel)
            .searchWeb(prompt);
    }
  }

  static Future<String> _complete(
      LlmProvider provider, String apiKey, String prompt,
      {String? model}) {
    switch (provider) {
      case LlmProvider.openai:
        return OpenAIService(apiKey, model: model ?? provider.defaultModel)
            .complete(prompt);
      case LlmProvider.gemini:
        return GeminiService(apiKey, model: model ?? provider.defaultModel)
            .complete(prompt);
      case LlmProvider.claude:
        return ClaudeService(apiKey, model: model ?? provider.defaultModel)
            .complete(prompt);
    }
  }
}
