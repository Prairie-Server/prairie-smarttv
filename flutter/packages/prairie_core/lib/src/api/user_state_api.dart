import '../models/auth.dart';
import 'api_client.dart';

ApiClientOptions _sessionOptions(PrairieSession session) => ApiClientOptions(
  serverUrl: session.serverUrl,
  accessToken: session.accessToken,
  refreshToken: session.refreshToken,
  profileId: session.profileId,
  profileToken: session.profileToken,
);

// Request-cache invalidation (`invalidateItem` in src/api/requestCache.ts)
// isn't ported yet — no response cache exists on the Dart side to
// invalidate. Revisit together when caching is ported.

/// Mirrors `setFavorite` from src/api/userState.ts.
Future<void> setFavorite(ApiClient client, PrairieSession session, String contentId, bool favorite) => client
    .request<dynamic>(
      _sessionOptions(session),
      '/api/v1/favorites/${Uri.encodeComponent(contentId)}',
      method: favorite ? 'PUT' : 'DELETE',
    );

/// Mirrors `setWatchlist` from src/api/userState.ts.
Future<void> setWatchlist(ApiClient client, PrairieSession session, String contentId, bool inWatchlist) => client
    .request<dynamic>(
      _sessionOptions(session),
      '/api/v1/watchlist/${Uri.encodeComponent(contentId)}',
      method: inWatchlist ? 'PUT' : 'DELETE',
    );

/// Mirrors `setWatched` from src/api/userState.ts.
Future<void> setWatched(ApiClient client, PrairieSession session, String contentId, bool played) => client
    .request<dynamic>(
      _sessionOptions(session),
      '/api/v1/watched/${Uri.encodeComponent(contentId)}',
      method: played ? 'POST' : 'DELETE',
    );
