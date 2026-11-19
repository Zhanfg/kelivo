import 'dart:math' as math;

import 'package:Kelivo/features/home/services/scientific/scientific_linear_algebra.dart';
import 'package:Kelivo/features/home/services/scientific/scientific_numerics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('bisection finds sqrt(2) within target tolerance', () {
    final root = ScientificNumerics.bisection(
      (x) => x * x - 2,
      lower: 0,
      upper: 2,
    );
    expect(root, closeTo(math.sqrt2, 1e-9));
  });

  test('root finding rejects unbracketed or nonfinite input', () {
    expect(
      () => ScientificNumerics.bisection((x) => x * x + 1, lower: -1, upper: 1),
      throwsArgumentError,
    );
    expect(
      () => ScientificNumerics.bisection((x) => double.nan, lower: 0, upper: 1),
      throwsArgumentError,
    );
  });

  test('root iteration budget rejects nonconvergence', () {
    expect(
      () => ScientificNumerics.bisection(
        (x) => x - 0.3,
        lower: 0,
        upper: 1,
        tolerance: 1e-14,
        maxIterations: 1,
      ),
      throwsStateError,
    );
    expect(
      () => ScientificNumerics.bisection((x) => x, lower: 1, upper: 0),
      throwsArgumentError,
    );
  });

  test('BigInt gcd covers negative and large operands', () {
    expect(
      ScientificNumerics.gcd(BigInt.from(-54), BigInt.from(24)),
      BigInt.from(6),
    );
    expect(
      ScientificNumerics.gcd(BigInt.one << 120, BigInt.one << 96),
      BigInt.one << 96,
    );
    expect(ScientificNumerics.gcd(BigInt.zero, BigInt.zero), BigInt.zero);
  });

  test('bounded prime check matches known vectors', () {
    for (final value in [2, 3, 5, 97, 65537, 2147483647]) {
      expect(ScientificNumerics.isPrime(value), isTrue);
    }
    for (final value in [0, 1, 4, 9, 221, 65535]) {
      expect(ScientificNumerics.isPrime(value), isFalse);
    }
    expect(() => ScientificNumerics.isPrime(-1), throwsArgumentError);
  });

  test('FFT impulse reference has constant transform', () {
    final result = ScientificNumerics.fft([
      ScientificComplex(1, 0),
      ScientificComplex(0, 0),
      ScientificComplex(0, 0),
      ScientificComplex(0, 0),
    ]);
    for (final value in result) {
      expect(value.real, closeTo(1, 1e-12));
      expect(value.imaginary, closeTo(0, 1e-12));
    }
  });

  test('FFT inverse roundtrip preserves bounded complex vectors', () {
    final sample = List.generate(
      32,
      (i) => ScientificComplex(math.sin(i * 0.3), math.cos(i * 0.7)),
    );
    final transformed = ScientificNumerics.fft(sample);
    final restored = ScientificNumerics.fft(transformed, inverse: true);
    for (var i = 0; i < sample.length; i++) {
      expect(restored[i].real, closeTo(sample[i].real, 1e-10));
      expect(restored[i].imaginary, closeTo(sample[i].imaginary, 1e-10));
    }
    expect(() => restored.clear(), throwsUnsupportedError);
  });

  test('FFT rejects invalid dimensions and excessive work budget', () {
    expect(() => ScientificNumerics.fft([]), throwsArgumentError);
    expect(
      () => ScientificNumerics.fft(
        List.generate(3, (_) => ScientificComplex(0, 0)),
      ),
      throwsArgumentError,
    );
    expect(
      () => ScientificNumerics.fft(
        List.generate(8192, (_) => ScientificComplex(0, 0)),
      ),
      throwsArgumentError,
    );
  });
}
