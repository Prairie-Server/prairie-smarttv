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

  testWidgets('Quick Connect does not auto-start on ConnectScreen mount', (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: ConnectScreen(serverUrl: 'https://prairie.example.com', serverName: 'Living Room'),
        ),
      ),
    );
    await tester.pump();

    // Opt-in button is visible; no "Generating code…" from an auto-start.
    expect(find.text('Show QR code'), findsOneWidget);
    expect(find.text('Generating code…'), findsNothing);
    expect(find.text('QUICK CONNECT'), findsOneWidget);
  });

  testWidgets('Show QR code starts Quick Connect (calls device/start)', (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // Fail immediately without a real network timer so the test can assert
    // we left idle after an explicit tap (not on mount).
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
    expect(find.text('Show QR code'), findsOneWidget);

    await tester.tap(find.text('Show QR code'));
    await tester.pump();
    // Leave idle immediately after the tap — starting or failed both count.
    expect(find.text('Show QR code'), findsNothing);
    await tester.pump(const Duration(seconds: 1));
  });
}
