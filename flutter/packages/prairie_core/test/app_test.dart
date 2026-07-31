import 'package:flutter/material.dart' hide Route;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prairie_core/prairie_core.dart';

import 'test_shared_preferences.dart';

// `PrairieApp`/`_StartupGate` isn't exercised here: it awaits
// SessionStore.load(), which needs flutter_secure_storage platform channels
// this widget-test environment doesn't provide. These tests drive `AppRoot`
// directly instead, with a `ProviderContainer` seeded past the startup gate.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    installInMemorySharedPreferences();
  });

  testWidgets('boots on the servers screen when no session is active', (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final container = ProviderContainer();
    addTearDown(container.dispose);
    // autoScan starts a real network scan on initState — off here since
    // widget tests have no network/dart:io NetworkInterface access.
    container.read(routeProvider.notifier).go(const ServersRoute(autoScan: false));

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const MaterialApp(home: AppRoot())),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Choose a saved server, one found nearby, or add an address.'), findsOneWidget);
  });

  testWidgets('AppRoot re-renders when the route changes', (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(routeProvider.notifier).go(const ServersRoute(autoScan: false));

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const MaterialApp(home: AppRoot())),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Choose a saved server, one found nearby, or add an address.'), findsOneWidget);

    container.read(routeProvider.notifier).go(const ManualServerRoute());
    await tester.pump();

    expect(find.text('Add server'), findsOneWidget);
  });
}
