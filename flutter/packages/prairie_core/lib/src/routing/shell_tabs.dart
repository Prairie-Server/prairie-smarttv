import '../models/library.dart';

/// A top-bar tab, in no particular order; [visibleShellTabs] fixes the order.
enum ShellTab { search, home, movies, series, music, audiobooks, forYou, calendar, livetv }

/// A library content type that surfaces as a top-bar tab. Tabs are types,
/// not single libraries: a type's tab shows only while the profile can see a
/// library of that type. Mirrors Android's `TvLibraryTabType` / tvOS
/// `TVLibraryTabType`.
enum LibraryTabType {
  movies('Movies'),
  series('Series'),
  music('Music'),
  audiobooks('Audiobooks');

  const LibraryTabType(this.label);

  final String label;

  ShellTab get shellTab => switch (this) {
    LibraryTabType.movies => ShellTab.movies,
    LibraryTabType.series => ShellTab.series,
    LibraryTabType.music => ShellTab.music,
    LibraryTabType.audiobooks => ShellTab.audiobooks,
  };

  /// Whether [library] belongs under this tab. A mixed library shows under
  /// both Movies and Series.
  bool matches(Library library) {
    final type = library.type.trim().toLowerCase();
    return switch (this) {
      LibraryTabType.movies => _movieTypes.contains(type) || type == 'mixed',
      LibraryTabType.series => _seriesTypes.contains(type) || type == 'mixed',
      LibraryTabType.music => _musicTypes.contains(type),
      LibraryTabType.audiobooks => _audiobookTypes.contains(type),
    };
  }

  /// The tab a library opened from elsewhere belongs to (a mixed library
  /// lands on Movies), or null when no tab matches.
  static LibraryTabType? forLibrary(Library library) {
    for (final type in values) {
      if (type.matches(library)) return type;
    }
    return null;
  }
}

const _movieTypes = {'movie', 'movies', 'video'};
const _seriesTypes = {'series', 'show', 'shows', 'tv'};
const _musicTypes = {'music', 'album', 'albums', 'artist', 'artists', 'audio'};
const _audiobookTypes = {'audiobook', 'audiobooks'};

/// The top bar, in its fixed order: Search, Home, the library-type tabs
/// with a matching library, For You, Calendar, then Live TV while the server
/// has channels (a Prairie addition). Matches Android TV and tvOS; there is
/// no menu editor or library pinning.
///
/// [active] stays visible even before [libraries] has loaded, so the bar
/// does not drop the tab the viewer is on.
List<ShellTab> visibleShellTabs({
  required List<Library> libraries,
  required bool liveTv,
  ShellTab? active,
}) => [
  ShellTab.search,
  ShellTab.home,
  for (final type in LibraryTabType.values)
    if (type.shellTab == active || libraries.any(type.matches)) type.shellTab,
  ShellTab.forYou,
  ShellTab.calendar,
  if (liveTv || active == ShellTab.livetv) ShellTab.livetv,
];
