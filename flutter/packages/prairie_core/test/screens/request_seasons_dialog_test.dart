import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prairie_core/prairie_core.dart';
import 'package:prairie_core/src/widgets/request_seasons_dialog.dart';

final _now = DateTime(2026, 11, 3);

const _series = RequestTitle(
  tmdbId: 1399,
  mediaType: 'series',
  title: 'Show',
  request: RequestState(requestable: true),
  seasons: [
    RequestSeason(seasonNumber: 1, episodeCount: 10, availability: 'available', airDate: '2011-04-17'),
    RequestSeason(seasonNumber: 2, episodeCount: 10, airDate: '2012-04-01'),
    RequestSeason(seasonNumber: 3, episodeCount: 10, airDate: '2013-03-31'),
    RequestSeason(seasonNumber: 4, episodeCount: 10, airDate: '2027-04-01'),
  ],
);

/// Opens the picker over a button; [answers] collects what it answers.
Future<void> _open(WidgetTester tester, List<RequestSeasonsPick?> answers) async {
  // A TV screen, so every season fits.
  tester.view.physicalSize = const Size(1920, 1080);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async =>
                answers.add(await showRequestSeasonsDialog(context, title: _series, confirmLabel: 'Request', now: _now)),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('kept as offered, the server picks the aired missing seasons', (tester) async {
    final answers = <RequestSeasonsPick?>[];
    await _open(tester, answers);
    expect(find.text('Request seasons'), findsOneWidget);
    expect(find.text('All seasons'), findsOneWidget);
    expect(find.text('2011 · 10 episodes · In library'), findsOneWidget);
    expect(find.text('2027 · 10 episodes · Not aired yet'), findsOneWidget);
    await tester.tap(find.widgetWithText(ElevatedButton, 'Request'));
    await tester.pumpAndSettle();
    expect(answers, hasLength(1));
    expect(answers.single!.seasons, isNull);
  });

  testWidgets('a changed pick names its seasons', (tester) async {
    final answers = <RequestSeasonsPick?>[];
    await _open(tester, answers);
    // Season 2 starts picked; drop it and add the upcoming season 4.
    await tester.tap(find.text('Season 2'));
    await tester.tap(find.text('Season 4'));
    await tester.pump();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Request'));
    await tester.pumpAndSettle();
    expect(answers.single!.seasons, [3, 4]);
  });

  testWidgets('backing out answers nothing', (tester) async {
    final answers = <RequestSeasonsPick?>[];
    await _open(tester, answers);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Request seasons'), findsNothing);
    expect(answers, [null]);
  });
}
