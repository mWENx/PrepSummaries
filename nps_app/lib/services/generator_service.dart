import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'excel_service.dart';
import 'llm_provider.dart';
import 'openai_service.dart';
import 'gemini_service.dart';
import 'claude_service.dart';
import 'docx_service.dart';

class GeneratorService {
  /// Runs the full pipeline and yields status strings as it progresses.
  /// Throws on any error.
  static Stream<String> generate({
    required String excelPath,
    required String outputDir,
    required String apiKey,
    required String targetName,
    required LlmProvider provider,
  }) async* {
    yield 'Looking up "$targetName" in Excel…';
    final donorData =
        ExcelService.extractDonorData(excelPath, targetName: targetName);

    yield 'Searching the web for ${donorData.donorName} via ${provider.displayName}…';
    final bioNotes = await _fetchBio(provider, apiKey, donorData);

    yield 'Filling briefing template…';
    final templateData =
        await rootBundle.load('assets/templates/FY26_Briefing_Template.docx');
    final templateBytes = templateData.buffer.asUint8List();

    // Build a safe filename from the donor name
    final safeName =
        donorData.donorName.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), '_');
    final outputPath = p.join(outputDir, '$safeName - Briefing.docx');

    await DocxService.fillTemplate(
      templateBytes: templateBytes,
      outputPath: outputPath,
      mergeFields: donorData.mergeFields,
      bioNotes: bioNotes,
      contacts: donorData.contacts,
      donorFirstName: donorData.donorFirstName,
    );

    yield outputPath;
  }

  static Future<List<String>> _fetchBio(
      LlmProvider provider, String apiKey, DonorData donor) {
    switch (provider) {
      case LlmProvider.openai:
        return OpenAIService(apiKey).fetchBiography(
          donorName: donor.donorName,
          employer: donor.primaryEmployer,
          jobTitle: donor.donorJobTitle,
          affiliation: donor.donorAffiliation,
        );
      case LlmProvider.gemini:
        return GeminiService(apiKey).fetchBiography(
          donorName: donor.donorName,
          employer: donor.primaryEmployer,
          jobTitle: donor.donorJobTitle,
          affiliation: donor.donorAffiliation,
        );
      case LlmProvider.claude:
        return ClaudeService(apiKey).fetchBiography(
          donorName: donor.donorName,
          employer: donor.primaryEmployer,
          jobTitle: donor.donorJobTitle,
          affiliation: donor.donorAffiliation,
        );
    }
  }
}
