import 'dart:math' as math;

import 'scientific_linear_algebra.dart';

/// Deterministic, explicitly bounded numerical primitives.
/// Independent of the shared scientific Operation Registry.
final class ScientificNumerics {
  const ScientificNumerics._();

  static double bisection(
    double Function(double) function, {
    required double lower,
    required double upper,
    double tolerance = 1e-10,
    int maxIterations = 128,
  }) {
    if (!lower.isFinite ||
        !upper.isFinite ||
        lower >= upper ||
        !tolerance.isFinite ||
        tolerance <= 0 ||
        tolerance >= 1 ||
        maxIterations < 1 ||
        maxIterations > 1024) {
      throw ArgumentError('Invalid root finding budget or interval');
    }
    var low = lower;
    var high = upper;
    var lowValue = function(low);
    var highValue = function(high);
    if (!lowValue.isFinite || !highValue.isFinite) {
      throw ArgumentError('Non-finite boundary function value');
    }
    if (lowValue == 0) return low;
    if (highValue == 0) return high;
    if ((lowValue.isNegative) == (highValue.isNegative)) {
      throw ArgumentError('Root must be bracketed');
    }
    for (var iteration = 0; iteration < maxIterations; iteration++) {
      final mid = low + (high - low) / 2;
      if (!mid.isFinite) throw StateError('Numeric overflow');
      final value = function(mid);
      if (!value.isFinite) throw StateError('Non-finite function evaluation');
      if (value == 0 || (high - low).abs() <= tolerance) return mid;
      if (value.isNegative == lowValue.isNegative) {
        low = mid;
        lowValue = value;
      } else {
        high = mid;
        highValue = value;
      }
    }
    throw StateError('Bisection iteration limit exceeded');
  }

  /// Euclidean algorithm on unbounded integers, no lossy float conversions.
  static BigInt gcd(BigInt left, BigInt right) {
    var a = left.abs();
    var b = right.abs();
    while (b != BigInt.zero) {
      final remainder = a % b;
      a = b;
      b = remainder;
    }
    return a;
  }

  /// Deterministic trial division for 32-bit candidates.
  static bool isPrime(int value) {
    if (value < 0 || value > 2147483647) {
      throw ArgumentError('Candidate outside supported 32-bit range');
    }
    if (value < 2) return false;
    if (value == 2) return true;
    if (value.isEven) return false;
    for (var divisor = 3; divisor <= value ~/ divisor; divisor += 2) {
      if (value % divisor == 0) return false;
    }
    return true;
  }

  /// In-place radix-2 Cooley-Tukey implementation, returning a fresh list.
  /// Maximum N=4096 prevents runaway CPU or memory use.
  static List<ScientificComplex> fft(
    List<ScientificComplex> input, {
    bool inverse = false,
  }) {
    final n = input.length;
    if (n == 0 || n > 4096 || (n & (n - 1)) != 0) {
      throw ArgumentError('FFT requires power-of-two input of length <=4096');
    }
    final data = input
        .map((value) => ScientificComplex(value.real, value.imaginary))
        .toList();
    for (var i = 1, j = 0; i < n; i++) {
      var bit = n >> 1;
      while ((j & bit) != 0) {
        j ^= bit;
        bit >>= 1;
      }
      j ^= bit;
      if (i < j) {
        final previous = data[i];
        data[i] = data[j];
        data[j] = previous;
      }
    }
    for (var block = 2; block <= n; block <<= 1) {
      final angle = (inverse ? 2 : -2) * math.pi / block;
      final phase = ScientificComplex(math.cos(angle), math.sin(angle));
      for (var start = 0; start < n; start += block) {
        var twiddle = ScientificComplex(1, 0);
        for (var k = 0; k < block ~/ 2; k++) {
          final first = data[start + k];
          final second = data[start + k + block ~/ 2].multiply(twiddle);
          data[start + k] = first.add(second);
          data[start + k + block ~/ 2] = first.add(
            ScientificComplex(-second.real, -second.imaginary),
          );
          twiddle = twiddle.multiply(phase);
        }
      }
    }
    if (inverse) {
      for (var i = 0; i < n; i++) {
        data[i] = ScientificComplex(data[i].real / n, data[i].imaginary / n);
      }
    }
    return List.unmodifiable(data);
  }
}
