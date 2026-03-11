import 'dart:convert';
import 'bio_result.dart';

/// Three-step prompt pipeline: search → verify → write.
class BioPrompt {
  // ── Step 1: Web search ──────────────────────────────────────────────────

  /// Prompt that asks the LLM to search the web and return raw excerpts.
  /// Uses LinkedIn character profile to generate targeted search queries.
  static String buildSearchPrompt({
    required String donorName,
    required String employer,
    required String jobTitle,
    required String affiliation,
    Map<String, dynamic>? linkedInIdentity,
  }) {
    final buf = StringBuffer();
    buf.writeln('Search the web for "$donorName".');
    buf.writeln();

    // Build character profile from LinkedIn if available
    if (linkedInIdentity != null) {
      buf.writeln('CHARACTER PROFILE (from verified LinkedIn — use this to guide your searches):');
      if (linkedInIdentity['name'] != null) {
        buf.writeln('- Full name: ${linkedInIdentity['name']}');
      }
      if (linkedInIdentity['headline'] != null) {
        buf.writeln('- Headline: ${linkedInIdentity['headline']}');
      }
      if (linkedInIdentity['location'] != null) {
        buf.writeln('- Location: ${linkedInIdentity['location']}');
      }
      final employment = linkedInIdentity['employment'];
      if (employment != null && employment is List && employment.isNotEmpty) {
        buf.writeln('- Employment history:');
        for (final job in employment) {
          if (job is Map) {
            buf.writeln('  - ${job['title'] ?? '?'} at ${job['employer'] ?? '?'} (${job['dates'] ?? '?'})');
          }
        }
      }
      final education = linkedInIdentity['education'];
      if (education != null && education is List && education.isNotEmpty) {
        buf.writeln('- Education:');
        for (final edu in education) {
          if (edu is Map) {
            buf.writeln('  - ${edu['degree'] ?? '?'} at ${edu['school'] ?? '?'} (${edu['dates'] ?? '?'})');
          }
        }
      }
      buf.writeln();
      buf.writeln('Also from our records:');
    } else {
      buf.writeln('Identity markers (use these to confirm you have the right person):');
    }
    buf.writeln('- Works or worked as $jobTitle at $employer');
    buf.writeln('- Affiliated with Northwestern University${affiliation.isNotEmpty ? ' ($affiliation)' : ''}');

    // Build targeted search queries from character profile
    List<String> employers = [];
    List<String> schoolNames = [];
    if (linkedInIdentity != null) {
      final employment = linkedInIdentity['employment'];
      if (employment != null && employment is List) {
        for (final job in employment) {
          if (job is Map && job['employer'] != null) {
            employers.add(job['employer'].toString());
          }
        }
      }
      final education = linkedInIdentity['education'];
      if (education != null && education is List) {
        for (final edu in education) {
          if (edu is Map && edu['school'] != null) {
            schoolNames.add(edu['school'].toString());
          }
        }
      }
    }

    buf.writeln();
    buf.writeln('REQUIRED SEARCHES — you must search ALL of the following:');
    buf.writeln('1. LinkedIn profile for "$donorName" (search "site:linkedin.com $donorName")');

    int searchNum = 2;

    // Targeted employer searches from LinkedIn profile
    if (employers.isNotEmpty) {
      for (final emp in employers) {
        buf.writeln('$searchNum. Search for "$donorName $emp" (employer website, leadership page, team bio, press releases)');
        searchNum++;
      }
    } else {
      buf.writeln('$searchNum. Search for "$donorName $employer" (employer website, leadership page)');
      searchNum++;
    }

    // Targeted school searches from LinkedIn profile
    for (final school in schoolNames) {
      buf.writeln('$searchNum. Search for "$donorName $school" (alumni pages, dean\'s lists, commencement programs, class notes, campus news)');
      searchNum++;
    }
    if (!schoolNames.any((s) => s.toLowerCase().contains('northwestern'))) {
      buf.writeln('$searchNum. Search for "$donorName Northwestern University" (alumni pages, donor recognition, event mentions)');
      searchNum++;
    }

    buf.writeln('$searchNum. News articles, press releases, or media mentions of "$donorName"');
    searchNum++;
    buf.writeln('$searchNum. Board memberships, nonprofit involvement, or industry affiliations');
    searchNum++;
    buf.writeln('$searchNum. Personal interests, hobbies, community involvement, social mentions');
    searchNum++;
    buf.writeln('$searchNum. Any other pages with substantive biographical information');

    buf.writeln();
    buf.writeln('You MUST perform a SEPARATE web search for EACH numbered item above. Do not skip any.');
    buf.writeln('Aim for at least 8-15 distinct excerpts from different sources. 2-3 is NOT enough.');
    buf.writeln('Cast a WIDE net — gather as many distinct sources as possible. More is better.');
    buf.writeln('Include results about this person even if they seem tangential (personal interests, community events, university activities).');
    buf.writeln('Do NOT limit your search to Northwestern — this person has a full life and career outside of Northwestern. Search for them at every school and employer listed in their character profile.');
    buf.writeln('For each relevant page you find, extract the text that mentions this person.');
    buf.writeln('Look for: career history, roles, responsibilities, education, achievements,');
    buf.writeln('board memberships, philanthropy, personal life, awards, publications,');
    buf.writeln('speaking engagements, hobbies, and any other substantive biographical information.');
    buf.writeln();
    buf.writeln('Return ONLY valid JSON with this schema:');
    buf.writeln();
    buf.writeln('{');
    buf.writeln('  "found": true,');
    buf.writeln('  "excerpts": [');
    buf.writeln('    {');
    buf.writeln('      "url": "https://...",');
    buf.writeln('      "title": "page or article title",');
    buf.writeln('      "text": "the relevant passage about this person copied from the page"');
    buf.writeln('    }');
    buf.writeln('  ]');
    buf.writeln('}');
    buf.writeln();
    buf.writeln('If you cannot find any information, return:');
    buf.writeln('{"found": false, "excerpts": []}');
    buf.writeln();
    buf.writeln('RULES:');
    buf.writeln('- Copy the actual text you find — do not paraphrase or summarize.');
    buf.writeln('- Each excerpt should focus on one source page.');
    buf.writeln('- Include the full relevant passage, not just a single sentence.');
    buf.writeln('- Do NOT include the same source/URL more than once. Each excerpt must be from a distinct page.');
    buf.writeln('- If a search returns no new results, that is fine — do not pad with duplicates.');
    buf.writeln('- You MUST include a LinkedIn excerpt if one exists. If you cannot find their LinkedIn, note that in a separate excerpt with url "none" and title "LinkedIn — not found".');
    buf.writeln('- Do NOT include any text outside the JSON.');

    return buf.toString();
  }

  /// Parses Step 1 output into a list of raw excerpts.
  static List<SearchExcerpt> parseSearchResult(String text) {
    final json = _parseJson(text);
    final found = json['found'];
    if (found == false) return [];

    final raw = json['excerpts'] as List? ?? [];
    return raw
        .whereType<Map<String, dynamic>>()
        .where((e) =>
            (e['url']?.toString() ?? '').isNotEmpty &&
            (e['text']?.toString() ?? '').isNotEmpty)
        .map((e) => SearchExcerpt(
              url: e['url'].toString(),
              title: (e['title'] ?? e['url']).toString(),
              text: e['text'].toString(),
            ))
        .toList();
  }

  // ── Step 2: Verification ────────────────────────────────────────────────

  /// Prompt that asks the LLM to verify each excerpt against the person's
  /// character profile built from LinkedIn + donor records.
  static String buildVerifyPrompt({
    required String donorName,
    required String employer,
    required String jobTitle,
    required String affiliation,
    required List<SearchExcerpt> excerpts,
    Map<String, dynamic>? linkedInIdentity,
  }) {
    final buf = StringBuffer();
    buf.writeln('I have research materials that may be about $donorName.');
    buf.writeln();

    // Build full character profile for verification
    buf.writeln('CHARACTER PROFILE — use this to verify each excerpt:');
    buf.writeln();
    buf.writeln('From our records:');
    buf.writeln('- Name: $donorName');
    buf.writeln('- Works or worked as $jobTitle at $employer');
    buf.writeln(
        '- Affiliated with Northwestern University${affiliation.isNotEmpty ? ' ($affiliation)' : ''}');

    if (linkedInIdentity != null) {
      buf.writeln();
      buf.writeln('From their verified LinkedIn profile:');
      if (linkedInIdentity['name'] != null) {
        buf.writeln('- Full name: ${linkedInIdentity['name']}');
      }
      if (linkedInIdentity['headline'] != null) {
        buf.writeln('- Headline: ${linkedInIdentity['headline']}');
      }
      if (linkedInIdentity['location'] != null) {
        buf.writeln('- Location: ${linkedInIdentity['location']}');
      }
      final employment = linkedInIdentity['employment'];
      if (employment != null && employment is List && employment.isNotEmpty) {
        buf.writeln('- Employment history:');
        for (final job in employment) {
          if (job is Map) {
            buf.writeln('  - ${job['title'] ?? '?'} at ${job['employer'] ?? '?'} (${job['dates'] ?? '?'})');
          }
        }
      }
      final education = linkedInIdentity['education'];
      if (education != null && education is List && education.isNotEmpty) {
        buf.writeln('- Education:');
        for (final edu in education) {
          if (edu is Map) {
            buf.writeln('  - ${edu['degree'] ?? '?'} at ${edu['school'] ?? '?'} (${edu['dates'] ?? '?'})');
          }
        }
      }
    }

    buf.writeln();
    buf.writeln('VERIFICATION INSTRUCTIONS:');
    buf.writeln();
    buf.writeln('For each excerpt, determine if it is about THIS specific $donorName by cross-referencing against the character profile above.');
    buf.writeln();
    buf.writeln('IMPORTANT — DO NOT simply reject sources because they mention a non-Northwestern institution. This person has a life and career BEYOND Northwestern. Use the character profile to reason holistically:');
    buf.writeln();
    buf.writeln('CORRECT reasoning examples:');
    buf.writeln('- "This dean\'s list is from University of Michigan, and our character profile shows they attended University of Michigan from 2014-2018. This IS the same person." → KEEP');
    buf.writeln('- "This press release mentions a VP at Goldman Sachs, and our character profile shows they worked at Goldman Sachs as VP from 2020-2023. This IS the same person." → KEEP');
    buf.writeln('- "This alumni magazine from Boston College mentions someone with the same name, but our character profile shows no connection to Boston College at all." → EXCLUDE');
    buf.writeln('- "This article mentions a $donorName who is a doctor in Texas, but our character profile shows a finance professional in Chicago." → EXCLUDE');
    buf.writeln();
    buf.writeln('WRONG reasoning (DO NOT DO THIS):');
    buf.writeln('- "This source is from University of Michigan, which is not Northwestern, so it\'s probably a different person." ← WRONG — check the character profile first!');
    buf.writeln('- "This mentions an employer not in our records, so this is a different person." ← WRONG — check ALL employers in the character profile, not just the current one.');
    buf.writeln('- "This dean\'s list says Communication Studies but LinkedIn says Nonprofit Leadership, so it\'s a different person." ← WRONG — people often have multiple majors, minors, certificates, or change programs. Same name + same school + overlapping dates = same person. A mismatched field of study is NOT grounds for exclusion.');
    buf.writeln();
    buf.writeln('In short: the character profile tells you everywhere this person has been. If a source matches ANY part of their profile (any employer, any school, any location, any role), it is likely the same person. Only exclude sources that clearly describe a DIFFERENT person (different career field, different city, different age/era). When in doubt, KEEP the source.');
    buf.writeln();

    for (int i = 0; i < excerpts.length; i++) {
      buf.writeln('--- EXCERPT ${i + 1} ---');
      buf.writeln('Source: ${excerpts[i].title}');
      buf.writeln('URL: ${excerpts[i].url}');
      buf.writeln(excerpts[i].text);
      buf.writeln();
    }

    buf.writeln('Return ONLY valid JSON:');
    buf.writeln('{');
    buf.writeln('  "results": [');
    buf.writeln('    {');
    buf.writeln('      "index": 1,');
    buf.writeln('      "is_correct_person": true,');
    buf.writeln(
        '      "reason": "explain HOW you matched/didn\'t match this to the character profile"');
    buf.writeln('    }');
    buf.writeln('  ]');
    buf.writeln('}');
    buf.writeln();
    buf.writeln('Do NOT include any text outside the JSON.');

    return buf.toString();
  }

  /// Parses Step 2 output and returns excerpts annotated with verification.
  static List<SearchExcerpt> parseVerifyResult(
      String text, List<SearchExcerpt> originalExcerpts) {
    final json = _parseJson(text);
    final results = json['results'] as List? ?? [];

    final verified = <SearchExcerpt>[];
    for (int i = 0; i < originalExcerpts.length; i++) {
      final excerpt = originalExcerpts[i];
      // Find the matching verification result (1-indexed)
      final match = results.whereType<Map<String, dynamic>>().where(
          (r) => r['index'] == i + 1 || r['index'] == (i + 1).toString());

      if (match.isNotEmpty) {
        final r = match.first;
        final isCorrect = r['is_correct_person'] == true;
        final reason = (r['reason'] ?? '').toString();
        verified.add(excerpt.copyWith(
          verified: isCorrect,
          reason: isCorrect ? '' : reason,
        ));
      } else {
        // No verification result — keep it but flag as unverified
        verified.add(excerpt.copyWith(
          verified: true,
          reason: 'No explicit verification returned',
        ));
      }
    }
    return verified;
  }

  // ── LinkedIn identity extraction ─────────────────────────────────────

  /// Prompt that asks the LLM to pull just the identity fields from
  /// a LinkedIn PDF's raw text.
  static String buildLinkedInExtractPrompt(String linkedInText) =>
      '''
Extract a structured summary from this LinkedIn profile text.

LINKEDIN PROFILE TEXT:
$linkedInText

Return ONLY valid JSON:
{
  "name": "full name as shown on profile",
  "headline": "their LinkedIn headline",
  "location": "location if shown",
  "employment": [
    {
      "employer": "company name",
      "title": "job title",
      "dates": "start – end (or 'Present')"
    }
  ],
  "education": [
    {
      "school": "school name",
      "degree": "degree type and field of study (e.g. BA in Communication Studies)",
      "dates": "start – end years"
    }
  ]
}

IMPORTANT: Include EVERY degree, certificate, and program separately — even if they are at the same school. For example, if someone has both a "BA in Communication Studies" and a "Certificate in Nonprofit Leadership" at University of Iowa, list TWO separate education entries for that school. Do NOT merge or skip any.

Do NOT include any text outside the JSON.
''';

  /// Parses extracted LinkedIn identity fields.
  static Map<String, dynamic> parseLinkedInExtract(String text) =>
      _parseJson(text);

  // ── LinkedIn sanity check ──────────────────────────────────────────────

  /// Prompt that compares extracted LinkedIn identity fields against
  /// our donor records. Handles nicknames, employer changes, title
  /// format differences, etc.
  static String buildLinkedInCheckPrompt({
    required String donorName,
    required String employer,
    required String jobTitle,
    required String affiliation,
    required Map<String, dynamic> linkedInIdentity,
  }) {
    final buf = StringBuffer();
    buf.writeln('Does this LinkedIn profile belong to the person in our records?');
    buf.writeln();
    buf.writeln('OUR RECORDS:');
    buf.writeln('- Name: $donorName');
    buf.writeln('- Employer: $employer');
    buf.writeln('- Job Title: $jobTitle');
    buf.writeln('- Northwestern affiliation: ${affiliation.isNotEmpty ? affiliation : 'yes (details unknown)'}');
    buf.writeln();
    buf.writeln('LINKEDIN PROFILE:');
    buf.writeln('- Name: ${linkedInIdentity['name'] ?? 'unknown'}');
    buf.writeln('- Headline: ${linkedInIdentity['headline'] ?? 'unknown'}');
    buf.writeln('- Location: ${linkedInIdentity['location'] ?? 'unknown'}');

    final employment = linkedInIdentity['employment'];
    if (employment != null && employment is List && employment.isNotEmpty) {
      buf.writeln('- Employment history:');
      for (final job in employment) {
        if (job is Map) {
          buf.writeln('  - ${job['title'] ?? '?'} at ${job['employer'] ?? '?'} (${job['dates'] ?? '?'})');
        }
      }
    }

    final education = linkedInIdentity['education'];
    if (education != null && education is List && education.isNotEmpty) {
      buf.writeln('- Education:');
      for (final edu in education) {
        if (edu is Map) {
          buf.writeln('  - ${edu['degree'] ?? '?'} at ${edu['school'] ?? '?'} (${edu['dates'] ?? '?'})');
        }
      }
    }

    buf.writeln();
    buf.writeln('Keep in mind:');
    buf.writeln('- Names may differ (nicknames like Bill vs William, maiden/married names)');
    buf.writeln('- Employers and titles change over time — look for ANY overlap, not just current');
    buf.writeln('- Title formats vary ("VP" vs "Vice President", "Sr." vs "Senior")');
    buf.writeln();
    buf.writeln('Return ONLY valid JSON:');
    buf.writeln('{');
    buf.writeln('  "is_match": true or false,');
    buf.writeln('  "confidence": "high" or "medium" or "low",');
    buf.writeln('  "reason": "brief explanation"');
    buf.writeln('}');
    buf.writeln();
    buf.writeln('Do NOT include any text outside the JSON.');

    return buf.toString();
  }

  /// Parses the LinkedIn sanity check result.
  static ({bool isMatch, String confidence, String reason})
      parseLinkedInCheck(String text) {
    final json = _parseJson(text);
    return (
      isMatch: json['is_match'] == true,
      confidence: (json['confidence'] ?? 'low').toString(),
      reason: (json['reason'] ?? '').toString(),
    );
  }

  // ── Step 3: Bio writing ─────────────────────────────────────────────────

  /// Prompt that asks the LLM to write bio bullets from verified materials.
  static String buildBioPrompt({
    required String donorName,
    required List<SearchExcerpt> verifiedExcerpts,
  }) {
    final buf = StringBuffer();
    buf.writeln(
        'Using ONLY the verified research materials below, write biography bullet points for $donorName.');
    buf.writeln();

    for (int i = 0; i < verifiedExcerpts.length; i++) {
      buf.writeln('--- SOURCE ${i + 1}: ${verifiedExcerpts[i].title} ---');
      buf.writeln(verifiedExcerpts[i].text);
      buf.writeln();
    }

    buf.writeln('Return ONLY valid JSON:');
    buf.writeln('{');
    buf.writeln('  "biography": ["bullet 1", "bullet 2"]');
    buf.writeln('}');
    buf.writeln();
    buf.writeln('''FORMATTING RULES:
- Each string is one bullet point — 1 to 2 sentences covering a single topic.
- Include meaningful detail (role, employer, key responsibilities or achievements, duration) but don't pad with filler.
- Do NOT include contact info (phone numbers, email addresses, office addresses).
- Do NOT include inline citation numbers like [1] or [2].
- Aim for 5-8 bullets total.

ORDER:
1st: Current position, employer, and primary responsibilities (include duration if known)
2nd to Nth: Previous notable positions with duration and key responsibilities
Then: Educational background — degrees, institutions, years
Then: Where they are currently based if available
Last: Personal notes if publicly available (e.g. married to, interests)

Do NOT include any text outside the JSON.''');

    return buf.toString();
  }

  /// Parses Step 3 output into biography bullet strings.
  static List<String> parseBioResult(String text) {
    final json = _parseJson(text);
    final raw = json['biography'] as List? ?? [];
    return raw.map((e) => e.toString()).toList();
  }

  // ── JSON parsing ────────────────────────────────────────────────────────

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
          'Could not parse JSON from LLM response. Preview: '
          '${cleaned.length > 200 ? cleaned.substring(0, 200) : cleaned}');
    }
  }
}
