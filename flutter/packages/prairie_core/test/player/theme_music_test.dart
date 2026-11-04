import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:prairie_core/prairie_core.dart';

class _FakeOutput implements ThemeAudioOutput {
  _FakeOutput(this.grant);

  final ThemeMusicGrant grant;
  final _ended = StreamController<void>.broadcast(sync: true);
  final _failed = StreamController<void>.broadcast(sync: true);
  bool started = false;
  bool disposed = false;
  int replays = 0;
  final volumes = <double>[];

  void end() => _ended.add(null);
  void fail() => _failed.add(null);

  @override
  Future<void> start() async => started = true;

  @override
  bool get supportsVolume => true;

  @override
  Future<void> setVolume(double volume) async => volumes.add(volume);

  @override
  Future<void> replay() async => replays++;

  @override
  Stream<void> get ended => _ended.stream;

  @override
  Stream<void> get failed => _failed.stream;

  @override
  Future<void> dispose() async => disposed = true;
}

ThemeSongSet _set(String owner, [String theme = 't1']) =>
    ThemeSongSet(ownerId: owner, items: [ThemeSong(id: theme, title: theme)]);

void main() {
  late List<(String, String)> grants;
  late List<_FakeOutput> outputs;
  late bool converted;
  late ThemeMusicController controller;

  setUp(() {
    grants = [];
    outputs = [];
    converted = false;
    controller = ThemeMusicController(
      fadeStep: Duration.zero,
      grant: (owner, theme) async {
        grants.add((owner, theme));
        return ThemeMusicGrant(url: 'https://s/$owner/$theme', converted: converted, contentType: 'audio/mpeg');
      },
      makeOutput: (grant) {
        final output = _FakeOutput(grant);
        outputs.add(output);
        return output;
      },
    );
  });

  Future<void> settle() => pumpEventQueue();

  test('plays the first theme and keeps it across pages of the same owner', () async {
    controller.select(_set('series-1'), loop: false);
    await settle();
    expect(grants, [('series-1', 't1')]);
    expect(outputs.single.started, isTrue);

    controller.select(_set('series-1'), loop: false);
    await settle();
    expect(grants, hasLength(1));
    expect(outputs.single.disposed, isFalse);
  });

  test('fades in to the background level', () async {
    controller.select(_set('m1'), loop: false);
    await settle();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(outputs.single.volumes.first, lessThan(outputs.single.volumes.last));
    expect(outputs.single.volumes.last, closeTo(ThemeMusicController.themeVolume, 1e-9));
  });

  test('another title switches themes; a page without one stops', () async {
    controller.select(_set('m1'), loop: false);
    await settle();
    controller.select(_set('m2'), loop: false);
    await settle();
    expect(outputs.first.disposed, isTrue);
    expect(outputs.last.grant.url, 'https://s/m2/t1');

    controller.select(null, loop: false);
    await settle();
    expect(outputs.last.disposed, isTrue);
    expect(controller.active, isFalse);
  });

  test('stop frees the player before a video starts', () async {
    controller.select(_set('m1'), loop: false);
    await settle();
    await controller.stop();
    expect(outputs.single.disposed, isTrue);
  });

  test('a grant that arrives after a stop is dropped', () async {
    final pending = Completer<ThemeMusicGrant>();
    final slow = ThemeMusicController(
      fadeStep: Duration.zero,
      grant: (_, _) => pending.future,
      makeOutput: (grant) {
        final output = _FakeOutput(grant);
        outputs.add(output);
        return output;
      },
    );
    slow.select(_set('m1'), loop: false);
    await slow.stop();
    pending.complete(const ThemeMusicGrant(url: 'u', converted: false, contentType: ''));
    await settle();
    expect(outputs, isEmpty);
  });

  test('loops original audio in place and converted audio with a new grant', () async {
    controller.select(_set('m1'), loop: true);
    await settle();
    outputs.single.end();
    await settle();
    expect(outputs.single.replays, 1);
    expect(grants, hasLength(1));

    await controller.stop();
    converted = true;
    controller.select(_set('m2'), loop: true);
    await settle();
    outputs.last.end();
    await settle();
    expect(grants.last, ('m2', 't1'));
    expect(grants.where((g) => g.$1 == 'm2'), hasLength(2));
  });

  test('without repeat a finished theme does not start again on the same owner', () async {
    controller.select(_set('m1'), loop: false);
    await settle();
    outputs.single.end();
    await settle();
    expect(outputs.single.disposed, isTrue);
    controller.select(_set('m1'), loop: false);
    await settle();
    expect(grants, hasLength(1));
  });

  test('a failed stream retries once with a fresh grant', () async {
    controller.select(_set('m1'), loop: false);
    await settle();
    outputs.last.fail();
    await settle();
    expect(grants, hasLength(2));
    outputs.last.fail();
    await settle();
    expect(grants, hasLength(2));
  });
}
