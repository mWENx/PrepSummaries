import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'bio_prompt.dart';
import 'bio_result.dart';
import 'excel_service.dart';
import 'llm_provider.dart';
import 'openai_service.dart';
import 'gemini_service.dart';
import 'claude_service.dart';
import 'docx_service.dart';

class GeneratorService {
  static Stream<String> generate({
    required String excelPath,
    required String outputDir,
    required String apiKey,
    required String targetName,
    required LlmProvider provider,
    String? linkedInPdfPath,
    String? model,
  }) async* {
    // ── Step 1/5: Parse Excel ─────────────────────────────────────────────
    yield 'Step 1/5 — Reading donor data from Excel…';
    final donorData =
        ExcelService.extractDonorData(excelPath, targetName: targetName);
    yield 'Step 1/5 — Found ${donorData.donorName}.';

    // ── Step 2/5: LinkedIn PDF (if provided) ────────────────────────────
    SearchExcerpt? linkedInExcerpt;
    Map<String, dynamic>? linkedInIdentity;
    if (linkedInPdfPath != null) {
      yield 'Step 2/5 — Extracting LinkedIn profile summary…';
      final linkedInText = _extractPdfText(linkedInPdfPath);
      if (linkedInText.isNotEmpty) {
        final extractResponse = await _complete(provider, apiKey,
            BioPrompt.buildLinkedInExtractPrompt(linkedInText), model: model);
        linkedInIdentity = BioPrompt.parseLinkedInExtract(extractResponse);
        final identity = linkedInIdentity;

        yield 'Step 2/5 — Verifying LinkedIn profile matches ${donorData.donorName}…';
        final checkResponse = await _complete(
            provider,
            apiKey,
            BioPrompt.buildLinkedInCheckPrompt(
              donorName: donorData.donorName,
              employer: donorData.primaryEmployer,
              jobTitle: donorData.donorJobTitle,
              affiliation: donorData.donorAffiliation,
              linkedInIdentity: identity,
            ),
            model: model);
        final check = BioPrompt.parseLinkedInCheck(checkResponse);

        if (check.isMatch) {
          yield 'Step 2/5 — LinkedIn verified: ${check.confidence} confidence — ${check.reason}';
          linkedInExcerpt = SearchExcerpt(
            url: 'LinkedIn PDF (uploaded by user, verified)',
            title:
                'LinkedIn Profile — ${identity['name'] ?? donorData.donorName}',
            text: linkedInText,
          );
        } else {
          yield 'Step 2/5 — LinkedIn PDF does NOT match ${donorData.donorName}: ${check.reason}';
          yield 'Step 2/5 — Skipping LinkedIn PDF.';
        }
      }
    } else {
      yield 'Step 2/5 — No LinkedIn PDF provided, skipping.';
    }

    // ── Step 3/5: Web search (3 parallel searches) ─────────────────────
    yield 'Step 3/5 — Searching the web for ${donorData.donorName} via ${provider.displayName} (career + education + personal)…';

    final searchArgs = {
      'donorName': donorData.donorName,
      'employer': donorData.primaryEmployer,
      'jobTitle': donorData.donorJobTitle,
      'affiliation': donorData.donorAffiliation,
      'linkedInIdentity': linkedInIdentity,
    };

    final results = await Future.wait([
      _searchWeb(provider, apiKey,
          BioPrompt.buildSearchPromptCareer(
            donorName: searchArgs['donorName'] as String,
            employer: searchArgs['employer'] as String,
            jobTitle: searchArgs['jobTitle'] as String,
            affiliation: searchArgs['affiliation'] as String,
            linkedInIdentity: searchArgs['linkedInIdentity'] as Map<String, dynamic>?,
          ), model: model),
      _searchWeb(provider, apiKey,
          BioPrompt.buildSearchPromptEducation(
            donorName: searchArgs['donorName'] as String,
            employer: searchArgs['employer'] as String,
            jobTitle: searchArgs['jobTitle'] as String,
            affiliation: searchArgs['affiliation'] as String,
            linkedInIdentity: searchArgs['linkedInIdentity'] as Map<String, dynamic>?,
          ), model: model),
      _searchWeb(provider, apiKey,
          BioPrompt.buildSearchPromptPersonal(
            donorName: searchArgs['donorName'] as String,
            employer: searchArgs['employer'] as String,
            jobTitle: searchArgs['jobTitle'] as String,
            affiliation: searchArgs['affiliation'] as String,
            linkedInIdentity: searchArgs['linkedInIdentity'] as Map<String, dynamic>?,
          ), model: model),
    ]);

    // Merge and deduplicate across all three searches
    final webExcerpts = <SearchExcerpt>[];
    final seenUrls = <String>{};
    final seenTitles = <String>{};
    for (final response in results) {
      for (final excerpt in BioPrompt.parseSearchResult(response)) {
        final normUrl = excerpt.url.split('?').first.split('#').first
            .replaceAll(RegExp(r'/+$'), '').toLowerCase();
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

    if (webExcerpts.isEmpty && linkedInExcerpt == null) {
      yield 'Step 3/5 — No results found. Generating briefing with empty bio notes…';
      await _generateOutputs(
        donorData: donorData,
        bioNotes: [],
        verifiedExcerpts: [],
        outputDir: outputDir,
        provider: provider,
      );
      yield _outputPath(outputDir, donorData.donorName);
      return;
    }

    yield 'Step 3/5 — Found ${webExcerpts.length} web source(s)${linkedInExcerpt != null ? ' + LinkedIn PDF' : ''}.';

    // Dump raw (pre-verification) sources for debugging
    await _writeRawSources(
      donorName: donorData.donorName,
      webExcerpts: webExcerpts,
      linkedInExcerpt: linkedInExcerpt,
      outputDir: outputDir,
      provider: provider,
    );

    // ── Step 4/5: Verify web sources ────────────────────────────────────
    yield 'Step 4/5 — Verifying sources against LinkedIn profile…';
    List<SearchExcerpt> verifiedWeb = [];
    if (webExcerpts.isNotEmpty) {
      final verifyPrompt = BioPrompt.buildVerifyPrompt(
        donorName: donorData.donorName,
        employer: donorData.primaryEmployer,
        jobTitle: donorData.donorJobTitle,
        affiliation: donorData.donorAffiliation,
        excerpts: webExcerpts,
        linkedInIdentity: linkedInIdentity,
      );
      final verifyResponse = await _complete(provider, apiKey, verifyPrompt, model: model);
      verifiedWeb = BioPrompt.parseVerifyResult(verifyResponse, webExcerpts);
    }

    final allChecked = <SearchExcerpt>[
      if (linkedInExcerpt != null) linkedInExcerpt,
      ...verifiedWeb,
    ];
    final verified = allChecked.where((e) => e.verified).toList();
    final excluded = allChecked.where((e) => !e.verified).length;
    yield 'Step 4/5 — ${verified.length} verified, $excluded excluded.';

    if (verified.isEmpty) {
      yield 'Step 4/5 — No verified sources. Generating briefing with empty bio notes…';
      await _generateOutputs(
        donorData: donorData,
        bioNotes: [],
        verifiedExcerpts: allChecked,
        outputDir: outputDir,
        provider: provider,
        usedLinkedIn: linkedInExcerpt != null,
      );
      yield _outputPath(outputDir, donorData.donorName);
      return;
    }

    // ── Step 5/5: Write biography & generate documents ──────────────────
    yield 'Step 5/5 — Writing biography from ${verified.length} verified source(s)…';
    final bioPrompt = BioPrompt.buildBioPrompt(
      donorName: donorData.donorName,
      verifiedExcerpts: verified,
    );

    final bioResponse = await _complete(provider, apiKey, bioPrompt, model: model);
    final bioNotes = BioPrompt.parseBioResult(bioResponse);

    yield 'Step 5/5 — Generating briefing and research materials…';
    await _generateOutputs(
      donorData: donorData,
      bioNotes: bioNotes,
      verifiedExcerpts: allChecked,
      outputDir: outputDir,
      provider: provider,
      usedLinkedIn: linkedInExcerpt != null,
    );

    yield _outputPath(outputDir, donorData.donorName);
  }

  // ── PDF text extraction ────────────────────────────────────────────────

  static String _extractPdfText(String pdfPath) {
    try {
      final bytes = File(pdfPath).readAsBytesSync();
      final document = PdfDocument(inputBytes: bytes);
      final extractor = PdfTextExtractor(document);
      final text = extractor.extractText();
      document.dispose();
      return text.trim();
    } catch (e) {
      return '';
    }
  }

  // ── Output generation ───────────────────────────────────────────────────

  static Future<void> _generateOutputs({
    required DonorData donorData,
    required List<String> bioNotes,
    required List<SearchExcerpt> verifiedExcerpts,
    required String outputDir,
    required LlmProvider provider,
    bool usedLinkedIn = false,
  }) async {
    final safeName =
        donorData.donorName.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), '_');

    // Build verified research materials .docx
    final sourcesPath =
        p.join(outputDir, '$safeName - Research Materials.docx');
    final sourcesMd = _buildVerifiedSourcesMd(
      donorName: donorData.donorName,
      employer: donorData.primaryEmployer,
      jobTitle: donorData.donorJobTitle,
      affiliation: donorData.donorAffiliation,
      verifiedExcerpts: verifiedExcerpts,
      bioNotes: bioNotes,
      provider: provider,
      usedLinkedIn: usedLinkedIn,
    );
    await DocxService.createFromMarkdown(
      markdownContent: sourcesMd,
      outputPath: sourcesPath,
    );

    // Fill briefing template
    final templateData =
        await rootBundle.load('assets/templates/new_template_mar13.docx');
    final templateBytes = templateData.buffer.asUint8List();
    final outputPath = _outputPath(outputDir, donorData.donorName);

    await DocxService.fillTemplate(
      templateBytes: templateBytes,
      outputPath: outputPath,
      mergeFields: donorData.mergeFields,
      bioNotes: bioNotes,
      contacts: donorData.contacts,
      donorFirstName: donorData.donorFirstName,
    );
  }

  static String _outputPath(String outputDir, String donorName) {
    final safeName =
        donorName.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), '_');
    return p.join(outputDir, '$safeName - Briefing.docx');
  }

  // ── Verified sources markdown ───────────────────────────────────────────

  static String _buildVerifiedSourcesMd({
    required String donorName,
    required String employer,
    required String jobTitle,
    required String affiliation,
    required List<SearchExcerpt> verifiedExcerpts,
    required List<String> bioNotes,
    required LlmProvider provider,
    bool usedLinkedIn = false,
  }) {
    final date = DateTime.now().toIso8601String().split('T').first;
    final buf = StringBuffer();

    buf.writeln('# Research Materials: $donorName');
    buf.writeln();
    buf.writeln('**Provider:** ${provider.displayName}');
    buf.writeln(
        '**Identity:** $jobTitle at $employer${affiliation.isNotEmpty ? ', $affiliation' : ''}');
    buf.writeln('**Generated:** $date');
    buf.writeln();

    // ── Verified Sources ──
    buf.writeln('---');
    buf.writeln();
    buf.writeln('# Verified Sources');
    buf.writeln();

    final verified = verifiedExcerpts.where((e) => e.verified).toList();
    // Separate LinkedIn from web sources
    final webVerified =
        verified.where((e) => !e.url.contains('LinkedIn PDF')).toList();

    if (usedLinkedIn) {
      buf.writeln('## LinkedIn Profile (uploaded by user, verified)');
      buf.writeln();
      buf.writeln(
          '> Content not duplicated here — refer to the uploaded LinkedIn PDF.');
      buf.writeln();
    }

    if (webVerified.isEmpty && !usedLinkedIn) {
      buf.writeln('No verified sources found.');
      buf.writeln();
    }

    for (int i = 0; i < webVerified.length; i++) {
      buf.writeln('## [${i + 1}] ${webVerified[i].title}');
      buf.writeln('**URL:** ${webVerified[i].url}');
      buf.writeln();
      for (final line in webVerified[i].text.split('\n')) {
        buf.writeln('> $line');
      }
      buf.writeln();
    }

    // ── Excluded Sources ──
    final excluded = verifiedExcerpts.where((e) => !e.verified).toList();
    if (excluded.isNotEmpty) {
      buf.writeln('---');
      buf.writeln();
      buf.writeln('# Excluded Sources');
      buf.writeln();
      for (final ex in excluded) {
        buf.writeln('### ${ex.title}');
        buf.writeln('**URL:** ${ex.url}');
        buf.writeln('**Reason:** ${ex.reason}');
        buf.writeln();
      }
    }

    // ── Bio Notes ──
    if (bioNotes.isNotEmpty) {
      buf.writeln('---');
      buf.writeln();
      buf.writeln('# Biography Notes (as used in briefing)');
      buf.writeln();
      for (final note in bioNotes) {
        buf.writeln('- $note');
      }
      buf.writeln();
    }

    return buf.toString();
  }

  // ── Raw sources dump (debug) ──────────────────────────────────────────

  static Future<void> _writeRawSources({
    required String donorName,
    required List<SearchExcerpt> webExcerpts,
    SearchExcerpt? linkedInExcerpt,
    required String outputDir,
    required LlmProvider provider,
  }) async {
    final safeName =
        donorName.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), '_');
    final date = DateTime.now().toIso8601String().split('T').first;
    final buf = StringBuffer();
    buf.writeln('# Raw Sources (Pre-Verification): $donorName');
    buf.writeln();
    buf.writeln('**Provider:** ${provider.displayName}');
    buf.writeln('**Generated:** $date');
    buf.writeln();

    if (linkedInExcerpt != null) {
      buf.writeln('---');
      buf.writeln();
      buf.writeln('## LinkedIn Profile (uploaded)');
      buf.writeln();
      for (final line in linkedInExcerpt.text.split('\n')) {
        buf.writeln('> $line');
      }
      buf.writeln();
    }

    buf.writeln('---');
    buf.writeln();
    buf.writeln('# Web Sources (${webExcerpts.length} total)');
    buf.writeln();

    for (int i = 0; i < webExcerpts.length; i++) {
      buf.writeln('## [${i + 1}] ${webExcerpts[i].title}');
      buf.writeln('**URL:** ${webExcerpts[i].url}');
      buf.writeln();
      for (final line in webExcerpts[i].text.split('\n')) {
        buf.writeln('> $line');
      }
      buf.writeln();
    }

    final rawPath = p.join(outputDir, '$safeName - Raw Sources.docx');
    await DocxService.createFromMarkdown(
      markdownContent: buf.toString(),
      outputPath: rawPath,
    );
  }

  // ── LLM dispatch ───────────────────────────────────────────────────────

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
