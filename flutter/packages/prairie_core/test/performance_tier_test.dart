import 'package:flutter_test/flutter_test.dart';
import 'package:prairie_core/prairie_core.dart';

void main() {
  group('detectHardwareTier', () {
    test('low RAM forces low tier regardless of platform version', () {
      final tier = detectHardwareTier(
        platform: TvPlatform.tizen,
        platformVersion: 9.0,
        physicalRamMb: 1024,
      );
      expect(tier, PerformanceTier.low);
    });

    test('2 or fewer CPU cores forces low tier', () {
      final tier = detectHardwareTier(platform: TvPlatform.tizen, platformVersion: 9.0, cpuCores: 2);
      expect(tier, PerformanceTier.low);
    });

    test('Tizen below 6.0 is low', () {
      expect(detectHardwareTier(platform: TvPlatform.tizen, platformVersion: 5.5), PerformanceTier.low);
    });

    test('Tizen 6.x is balanced', () {
      expect(detectHardwareTier(platform: TvPlatform.tizen, platformVersion: 6.5), PerformanceTier.balanced);
    });

    test('Tizen 7.0+ is high', () {
      expect(detectHardwareTier(platform: TvPlatform.tizen, platformVersion: 8.0), PerformanceTier.high);
    });

    test('webOS <= 4 is low, <= 5 is balanced, above is high', () {
      expect(detectHardwareTier(platform: TvPlatform.webos, platformVersion: 4), PerformanceTier.low);
      expect(detectHardwareTier(platform: TvPlatform.webos, platformVersion: 5), PerformanceTier.balanced);
      expect(detectHardwareTier(platform: TvPlatform.webos, platformVersion: 6), PerformanceTier.high);
    });
  });

  group('resolvePerformanceTier', () {
    test('auto defers to the detected tier', () {
      expect(resolvePerformanceTier(PerformanceMode.auto, PerformanceTier.low), PerformanceTier.low);
    });

    test('an explicit mode overrides detection', () {
      expect(resolvePerformanceTier(PerformanceMode.high, PerformanceTier.low), PerformanceTier.high);
    });
  });

  test('prefersReducedEffects is true for low/balanced, false for high', () {
    expect(prefersReducedEffects(PerformanceTier.low), true);
    expect(prefersReducedEffects(PerformanceTier.balanced), true);
    expect(prefersReducedEffects(PerformanceTier.high), false);
  });

  group('preferredRasterFormatsForTier', () {
    const detected = [RasterFormat.avif, RasterFormat.webp, RasterFormat.png];

    test('high tier keeps AVIF', () {
      expect(preferredRasterFormatsForTier(PerformanceTier.high, detected), detected);
    });

    test('non-high tiers drop AVIF', () {
      expect(preferredRasterFormatsForTier(PerformanceTier.balanced, detected), [
        RasterFormat.webp,
        RasterFormat.png,
      ]);
    });
  });

  test('cyclePerformanceMode cycles auto -> high -> balanced -> low -> auto', () {
    expect(cyclePerformanceMode(PerformanceMode.auto), PerformanceMode.high);
    expect(cyclePerformanceMode(PerformanceMode.high), PerformanceMode.balanced);
    expect(cyclePerformanceMode(PerformanceMode.balanced), PerformanceMode.low);
    expect(cyclePerformanceMode(PerformanceMode.low), PerformanceMode.auto);
  });

  test('compareTiers orders low < balanced < high', () {
    expect(compareTiers(PerformanceTier.low, PerformanceTier.high), lessThan(0));
    expect(compareTiers(PerformanceTier.high, PerformanceTier.low), greaterThan(0));
    expect(compareTiers(PerformanceTier.balanced, PerformanceTier.balanced), 0);
  });
}
