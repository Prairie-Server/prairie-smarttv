import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../platform/video_backend.dart';

/// Platform apps must override this in their `main()`'s `ProviderScope`,
/// e.g. `videoBackendFactoryProvider.overrideWithValue(() => VideoholeVideoBackend())`.
/// `prairie_core` never imports a concrete backend — see `VideoBackend`.
final videoBackendFactoryProvider = Provider<VideoBackendFactory>(
  (ref) => throw UnimplementedError('videoBackendFactoryProvider must be overridden by the platform app'),
);
