/// A single excerpt found during web research.
class SearchExcerpt {
  /// Source page URL.
  final String url;

  /// Source page title.
  final String title;

  /// Relevant text extracted from the page.
  final String text;

  /// Whether this excerpt was verified as being about the correct person.
  final bool verified;

  /// Reason for exclusion (if not verified).
  final String reason;

  const SearchExcerpt({
    required this.url,
    required this.title,
    required this.text,
    this.verified = true,
    this.reason = '',
  });

  SearchExcerpt copyWith({bool? verified, String? reason}) => SearchExcerpt(
        url: url,
        title: title,
        text: text,
        verified: verified ?? this.verified,
        reason: reason ?? this.reason,
      );
}

/// Final output: clean bio bullets + the research trail.
class BioResult {
  /// Biography bullet strings (no inline citation numbers).
  final List<String> biography;

  /// All excerpts found (both verified and excluded).
  final List<SearchExcerpt> sources;

  const BioResult({required this.biography, required this.sources});
}
