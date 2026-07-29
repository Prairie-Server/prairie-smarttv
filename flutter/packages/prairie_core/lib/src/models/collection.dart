/// Mirrors `CollectionCard` from src/api/collections.ts.
class CollectionCard {
  const CollectionCard({
    required this.id,
    this.title,
    this.name,
    this.posterUrl,
    this.itemCount,
    this.featured,
    this.libraryId,
  });

  final String id;
  final String? title;
  final String? name;
  final String? posterUrl;
  final int? itemCount;
  final bool? featured;
  final int? libraryId;

  /// Mirrors the display-title fallback (`title ?? name ?? "Collection"`) used
  /// wherever a card is opened (e.g. src/App.tsx's collection route).
  String get displayTitle => title ?? name ?? 'Collection';
}
