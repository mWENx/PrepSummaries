import 'dart:convert';
import 'bio_result.dart';

/// Three-step prompt pipeline: search → verify → write.
class BioPrompt {
  // ── Step 1: Web search ──────────────────────────────────────────────────

  /// Builds the character profile + identity block reused across search prompts.
  static String _buildCharacterBlock({
    required String donorName,
    required String employer,
    required String jobTitle,
    required String affiliation,
    Map<String, dynamic>? linkedInIdentity,
  }) {
    final buf = StringBuffer();
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
    return buf.toString();
  }

  /// Common JSON schema + rules appended to every search prompt.
  static String _buildSearchRules() {
    final buf = StringBuffer();
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
    buf.writeln('- ONLY include excerpts where the person\'s name appears explicitly in the page text. Do not include pages that are merely related to their employer or school but do not mention them by name.');
    buf.writeln('- Copy the actual text you find — do not paraphrase or summarize.');
    buf.writeln('- Each excerpt should focus on one source page.');
    buf.writeln('- Include the full relevant passage, not just a single sentence.');
    buf.writeln('- Do NOT include the same source/URL more than once. Each excerpt must be from a distinct page.');
    buf.writeln('- If a search returns no new results, that is fine — do not pad with duplicates.');
    buf.writeln('- Do NOT include any text outside the JSON.');
    return buf.toString();
  }

  /// Extracts employer and school lists from the LinkedIn identity.
  static ({List<String> employers, List<String> schools}) _extractProfileLists(
      Map<String, dynamic>? linkedInIdentity) {
    final employers = <String>[];
    final schools = <String>[];
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
            schools.add(edu['school'].toString());
          }
        }
      }
    }
    return (employers: employers, schools: schools);
  }

  /// Search prompt 1/3: Career — LinkedIn profile, employers, job roles.
  static String buildSearchPromptCareer({
    required String donorName,
    required String employer,
    required String jobTitle,
    required String affiliation,
    Map<String, dynamic>? linkedInIdentity,
  }) {
    final buf = StringBuffer();
    buf.writeln('Search the web for "$donorName" — focus on CAREER and PROFESSIONAL life.');
    buf.writeln();
    buf.writeln(_buildCharacterBlock(
      donorName: donorName, employer: employer,
      jobTitle: jobTitle, affiliation: affiliation,
      linkedInIdentity: linkedInIdentity,
    ));

    final profile = _extractProfileLists(linkedInIdentity);

    buf.writeln();
    buf.writeln('REQUIRED SEARCHES:');
    buf.writeln('1. LinkedIn profile (search "site:linkedin.com $donorName")');

    int n = 2;
    if (profile.employers.isNotEmpty) {
      for (final emp in profile.employers) {
        buf.writeln('$n. "$donorName $emp" — employer website, leadership page, team bio, press releases');
        n++;
      }
    } else {
      buf.writeln('$n. "$donorName $employer" — employer website, leadership page');
      n++;
    }
    buf.writeln('$n. News articles or press releases mentioning "$donorName" in a professional context');

    buf.writeln();
    buf.writeln('Perform a SEPARATE web search for EACH item. Do not skip any.');
    buf.writeln('Only return excerpts relevant to career, employment, and professional achievements.');
    buf.writeln();
    buf.writeln(_buildSearchRules());
    // LinkedIn-specific rule only in this prompt
    buf.writeln('- You MUST include a LinkedIn excerpt if one exists. If you cannot find their LinkedIn, note that in a separate excerpt with url "none" and title "LinkedIn — not found".');
    return buf.toString();
  }

  /// Search prompt 2/3: Education — schools, alumni pages, dean's lists.
  static String buildSearchPromptEducation({
    required String donorName,
    required String employer,
    required String jobTitle,
    required String affiliation,
    Map<String, dynamic>? linkedInIdentity,
  }) {
    final buf = StringBuffer();
    buf.writeln('Search the web for "$donorName" — focus on EDUCATION and ACADEMIC life.');
    buf.writeln();
    buf.writeln(_buildCharacterBlock(
      donorName: donorName, employer: employer,
      jobTitle: jobTitle, affiliation: affiliation,
      linkedInIdentity: linkedInIdentity,
    ));

    final profile = _extractProfileLists(linkedInIdentity);

    buf.writeln();
    buf.writeln('REQUIRED SEARCHES:');
    int n = 1;
    for (final school in profile.schools) {
      buf.writeln('$n. "$donorName $school" — alumni pages, dean\'s lists, commencement programs, class notes, campus news');
      n++;
    }
    if (!profile.schools.any((s) => s.toLowerCase().contains('northwestern'))) {
      buf.writeln('$n. "$donorName Northwestern University" — alumni pages, donor recognition, event mentions');
      n++;
    }
    if (n == 1) {
      // No schools known — do a general education search
      buf.writeln('1. "$donorName university OR college OR alumni" — any educational background');
      buf.writeln('2. "$donorName Northwestern University" — alumni pages, donor recognition');
    }

    buf.writeln();
    buf.writeln('Perform a SEPARATE web search for EACH item. Do not skip any.');
    buf.writeln('Only return excerpts relevant to education, academic achievements, and alumni activities.');
    buf.writeln();
    buf.writeln(_buildSearchRules());
    return buf.toString();
  }

  /// Search prompt 3/3: Personal — philanthropy, boards, hobbies, community.
  static String buildSearchPromptPersonal({
    required String donorName,
    required String employer,
    required String jobTitle,
    required String affiliation,
    Map<String, dynamic>? linkedInIdentity,
  }) {
    final buf = StringBuffer();
    buf.writeln('Search the web for "$donorName" — focus on PERSONAL life, PHILANTHROPY, and COMMUNITY involvement.');
    buf.writeln();
    buf.writeln(_buildCharacterBlock(
      donorName: donorName, employer: employer,
      jobTitle: jobTitle, affiliation: affiliation,
      linkedInIdentity: linkedInIdentity,
    ));

    buf.writeln();
    buf.writeln('REQUIRED SEARCHES:');
    buf.writeln('1. Board memberships, nonprofit involvement, or industry affiliations for "$donorName"');
    buf.writeln('2. Personal interests, hobbies, community involvement, social mentions for "$donorName"');
    buf.writeln('3. Any other pages with substantive biographical information about "$donorName"');

    buf.writeln();
    buf.writeln('Perform a SEPARATE web search for EACH item. Do not skip any.');
    buf.writeln('Only return excerpts relevant to philanthropy, boards, personal interests, community, and hobbies.');
    buf.writeln('Do NOT return career/employer or education results — those are covered separately.');
    buf.writeln();
    buf.writeln(_buildSearchRules());
    return buf.toString();
  }

  /// Parses Step 1 output into a list of raw excerpts, deduplicated by URL.
  static List<SearchExcerpt> parseSearchResult(String text) {
    final json = _parseJson(text);
    final found = json['found'];
    if (found == false) return [];

    final raw = json['excerpts'] as List? ?? [];
    final seen = <String>{};
    final results = <SearchExcerpt>[];
    for (final e in raw.whereType<Map<String, dynamic>>()) {
      final url = (e['url']?.toString() ?? '').trim();
      final txt = (e['text']?.toString() ?? '').trim();
      if (url.isEmpty || txt.isEmpty) continue;
      // Normalise URL for dedup: strip trailing slashes, fragments, query strings
      final normUrl = url.split('?').first.split('#').first.replaceAll(RegExp(r'/+$'), '').toLowerCase();
      // Also dedup by title to catch same page with slightly different URLs
      final normTitle = (e['title'] ?? '').toString().trim().toLowerCase();
      if (seen.contains(normUrl) || (normTitle.isNotEmpty && seen.contains('t:$normTitle'))) continue;
      seen.add(normUrl);
      if (normTitle.isNotEmpty) seen.add('t:$normTitle');
      results.add(SearchExcerpt(
        url: url,
        title: (e['title'] ?? url).toString(),
        text: txt,
      ));
    }
    return results;
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
    buf.writeln('- "This says U of I but our profile says University of Iowa, so it must be University of Illinois." ← WRONG — resolve ambiguous abbreviations (U of I, UMich, NU, etc.) in FAVOR of the character profile. If the profile shows University of Iowa, then "U of I" almost certainly means University of Iowa, not Illinois.');
    buf.writeln('- "This says Communications but the profile says Communication Studies." ← WRONG — treat near-synonym field names (Communications / Communication Studies / Media Studies, etc.) as matching.');
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
