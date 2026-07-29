import 'package:dio/dio.dart';
import 'package:flutter/material.dart' hide Route;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prairie_core/prairie_core.dart';

import 'api/fake_http_adapter.dart';
import 'test_shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    installInMemorySharedPreferences();
  });

  testWidgets('Quick Connect auto-starts on ConnectScreen mount', (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final dio = Dio()
      ..httpClientAdapter = FakeHttpAdapter(
        (_) => jsonResponse('{"message":"offline","code":"unavailable"}', 503),
      );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(ApiClient(dio: dio)),
        ],
        child: const MaterialApp(
          home: ConnectScreen(serverUrl: 'https://prairie.example.com', serverName: 'Living Room'),
        ),
      ),
    );
    await tester.pump();
    // Post-frame auto-start leaves idle immediately.
    await tester.pump();

    expect(find.text('Show QR code'), findsNothing);
    expect(find.text('QUICK CONNECT'), findsOneWidget);
    // Starting or failed both count as having left the idle gate.
    final generating = find.text('Generating code…');
    final tryAgain = find.text('Try again');
    expect(generating.evaluate().isNotEmpty || tryAgain.evaluate().isNotEmpty, isTrue);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('Try again restarts Quick Connect after failure', (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final dio = Dio()
      ..httpClientAdapter = FakeHttpAdapter(
        (_) => jsonResponse('{"message":"offline","code":"unavailable"}', 503),
      );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(ApiClient(dio: dio)),
        ],
        child: const MaterialApp(
          home: ConnectScreen(serverUrl: 'https://prairie.example.com'),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Try again'), findsOneWidget);
    await tester.tap(find.text('Try again'));
    await tester.pump();
    expect(find.text('Show QR code'), findsNothing);
    await tester.pump(const Duration(seconds: 1));
  });
}
