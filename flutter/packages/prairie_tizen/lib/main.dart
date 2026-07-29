import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prairie_core/prairie_core.dart';

import 'platform/avplay_video_backend.dart';

void main() {
  runApp(
    ProviderScope(
      overrides: [videoBackendFactoryProvider.overrideWithValue(() => AvplayVideoBackend())],
      child: const PrairieApp(),
    ),
  );
}
