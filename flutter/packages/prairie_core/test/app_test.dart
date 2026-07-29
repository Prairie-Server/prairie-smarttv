import 'package:flutter/material.dart' hide Route;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prairie_core/prairie_core.dart';

// `PrairieApp`/`_StartupGate` isn't exercised here: it awaits
// SessionStore.load(), which needs shared_preferences/flutter_secure_storage
// platform channels this widget-test environment doesn't provide. These
// tests drive `AppRoot` directly instead, with a `ProviderContainer` seeded
// past the startup gate. Revisit once there's a fake storage backend to mock
// those plugins with.
void main() {
  testWidgets('boots on the servers screen when no session is active', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    // autoScan starts a real network scan on initState — off here since
    // widget tests have no network/dart:io NetworkInterface access.
    container.read(routeProvider.notifier).go(const ServersRoute(autoScan: false));

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const MaterialApp(home: AppRoot())),
    );

    expect(find.text('Find your Prairie server'), findsOneWidget);
  });

  testWidgets('AppRoot re-renders when the route changes', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(routeProvider.notifier).go(const ServersRoute(autoScan: false));

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const MaterialApp(home: AppRoot())),
    );
    expect(find.text('Find your Prairie server'), findsOneWidget);

    container.read(routeProvider.notifier).go(const ManualServerRoute());
    await tester.pump();

    expect(find.text('Add server'), findsOneWidget);
  });
}
