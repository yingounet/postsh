class CompletionService {
  const CompletionService._();

  static List<String> buildSuggestions({
    required String input,
    required List<String> history,
    required List<String> staticCommands,
    int limit = 8,
  }) {
    final query = _lastToken(input).toLowerCase();
    if (query.isEmpty) return [];

    final results = <String>[];
    void addMatches(Iterable<String> source) {
      for (final item in source) {
        if (results.length >= limit) return;
        if (item.toLowerCase().startsWith(query)) {
          if (!results.contains(item)) {
            results.add(item);
          }
        }
      }
    }

    addMatches(history);
    addMatches(staticCommands);
    return results;
  }

  static String applySuggestion(String input, String suggestion) {
    final token = _lastToken(input);
    if (token.isEmpty) return input;
    final idx = input.lastIndexOf(token);
    if (idx < 0) return input;
    return '${input.substring(0, idx)}$suggestion';
  }

  static String _lastToken(String input) {
    final trimmedRight = input.replaceAll(RegExp(r'\s+$'), '');
    if (trimmedRight.isEmpty) return '';
    final parts = trimmedRight.split(RegExp(r'\s+'));
    return parts.isEmpty ? '' : parts.last;
  }
}
