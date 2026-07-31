/// Mirrors `Library` from src/api/libraries.ts.
class Library {
  const Library({
    required this.id,
    required this.name,
    required this.type,
    this.sortOrder,
    this.posterUrl,
  });

  final int id;
  final String name;
  final String type;
  final int? sortOrder;
  final String? posterUrl;
}
