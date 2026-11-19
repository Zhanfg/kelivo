import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:Kelivo/features/home/services/scientific/scientific_statistics.dart';

void main() {
  test('descriptive statistics known vectors', () {
    expect(ScientificStatistics.mean([1, 2, 3, 4]), 2.5);
    expect(ScientificStatistics.median([4, 1, 3, 2]), 2.5);
    expect(ScientificStatistics.variance([1, 2, 3]), closeTo(2 / 3, 1e-12));
    expect(ScientificStatistics.variance([1, 2, 3], sample: true), 1);
    expect(() => ScientificStatistics.mean([]), throwsArgumentError);
    expect(() => ScientificStatistics.mean([double.nan]), throwsArgumentError);
    expect(
      () => ScientificStatistics.variance([1], sample: true),
      throwsArgumentError,
    );
  });

  test('probability known vectors and invalid parameters', () {
    expect(
      ScientificStatistics.normalPdf(0),
      closeTo(1 / math.sqrt(2 * math.pi), 1e-12),
    );
    expect(ScientificStatistics.exponentialCdf(0, rate: 2), 0);
    expect(
      ScientificStatistics.exponentialCdf(1, rate: 1),
      closeTo(1 - math.exp(-1), 1e-12),
    );
    expect(
      ScientificStatistics.binomialPmf(2, n: 4, p: 0.5),
      closeTo(0.375, 1e-12),
    );
    expect(ScientificStatistics.binomialPmf(0, n: 3, p: 0), 1);
    expect(
      () => ScientificStatistics.normalPdf(0, sigma: -1),
      throwsArgumentError,
    );
    expect(
      () => ScientificStatistics.binomialPmf(1, n: 4, p: 2),
      throwsArgumentError,
    );
  });

  test('seeded generator deterministic, bounded secure random', () {
    final a = SeededStatisticsRandom(42);
    final b = SeededStatisticsRandom(42);
    final seqA = [a.nextUint32(), a.nextUint32(), a.nextUint32()];
    final seqB = [b.nextUint32(), b.nextUint32(), b.nextUint32()];
    expect(seqA, seqB);
    expect(seqA.first, 11355432);
    final secure = ScientificStatistics.secureInteger(17);
    expect(secure, inInclusiveRange(0, 16));
    expect(() => ScientificStatistics.secureInteger(0), throwsArgumentError);
    expect(() => SeededStatisticsRandom(0), throwsArgumentError);
  });
}
