import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'excel_service.dart';
import 'openai_service.dart';
import 'docx_service.dart';

class GeneratorService {
  /// Runs the full pipeline and yields status strings as it progresses.
  /// Throws on any error.
  static Stream<String> generate({
    required String excelPath,
    required String outputDir,
    required String openAiApiKey,
    required String targetName,
  }) async* {
    yield 'Looking up "$targetName" in Excel…';
    final donorData =
        ExcelService.extractDonorData(excelPath, targetName: targetName);

    yield 'Searching the web for ${donorData.donorName}…';
    final openAI = OpenAIService(openAiApiKey);
    final bioNotes = await openAI.fetchBiography(
      donorName: donorData.donorName,
      employer: donorData.primaryEmployer,
      jobTitle: donorData.donorJobTitle,
      affiliation: donorData.donorAffiliation,
    );

    yield 'Filling briefing template…';
    final templateData =
        await rootBundle.load('assets/templates/Briefing_Template.docx');
    final templateBytes = templateData.buffer.asUint8List();

    // Build a safe filename from the donor name
    final safeName =
        donorData.donorName.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), '_');
    final outputPath = p.join(outputDir, '$safeName - Briefing.docx');

    await DocxService.fillTemplate(
      templateBytes: templateBytes,
      outputPath: outputPath,
      replacements: donorData.replacements,
      bioNotes: bioNotes,
    );

    yield outputPath;
  }
}
