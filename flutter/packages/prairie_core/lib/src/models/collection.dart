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
    this.creatorProfileId,
    this.collectionType,
    this.contains,
  });

  final String id;
  final String? title;
  final String? name;
  final String? posterUrl;
  final int? itemCount;
  final bool? featured;
  final int? libraryId;

  /// Personal collections only: the profile that may edit it. Collections
  /// shared from other profiles on the login are read-only.
  final String? creatorProfileId;

  /// Personal collections only: `manual`, `smart` or an import source. Only
  /// manual collections take hand-picked titles.
  final String? collectionType;

  /// Set when the list was fetched with `contains_item`: whether this
  /// collection already holds that title.
  final bool? contains;

  /// Mirrors the display-title fallback (`title ?? name ?? "Collection"`) used
  /// wherever a card is opened (e.g. src/App.tsx's collection route).
  String get displayTitle => title ?? name ?? 'Collection';

  /// Whether [profileId] may rename/delete this collection. Mirrors the
  /// server's creator check; a card without creator info (older servers) is
  /// treated as the acting profile's own.
  bool isOwnedBy(String? profileId) => creatorProfileId == null || profileId == null || creatorProfileId == profileId;

  bool get isManual => collectionType == null || collectionType == 'manual';
}

/// The fields of `GET /api/v2/collections/capabilities` the TV acts on.
class CollectionCapabilities {
  const CollectionCapabilities({required this.allowed, this.containsItem = false});

  factory CollectionCapabilities.fromJson(Map<String, dynamic> json) => CollectionCapabilities(
    allowed: json['allowed'] == true,
    containsItem: json['contains_item'] == true,
  );

  /// Whether the acting profile may create and edit personal collections.
  final bool allowed;

  /// `listCollections` accepts `contains_item` and marks collections that
  /// already hold that title.
  final bool containsItem;
}

/// Whether [card] gets Rename/Delete (and, when manual, title removal) for
/// [profileId]. Hidden while capabilities are unknown, for library
/// collections, and for collections shared from another profile.
bool canEditCollection(CollectionCapabilities? capabilities, CollectionCard card, String? profileId) =>
    (capabilities?.allowed ?? false) && card.libraryId == null && card.isOwnedBy(profileId);
