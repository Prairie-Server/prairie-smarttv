/// Mirrors `Library` from src/api/libraries.ts.
class Library {
  const Library({
    required this.id,
    required this.name,
    required this.type,
    this.sortOrder,
    this.posterUrl,
    this.boxSetsEnabled = false,
  });

  final int id;
  final String name;
  final String type;
  final int? sortOrder;
  final String? posterUrl;

  /// The library gathers the movies of one TMDB collection into a box set,
  /// shown on movie pages and in search.
  final bool boxSetsEnabled;
}
