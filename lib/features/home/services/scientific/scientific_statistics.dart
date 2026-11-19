// Bounded numerical primitives, independent from the existing calculator.
// This backend does not mark any Operation Registry entry executable.
import 'dart:math' as math;

final class ScientificStatistics {
  const ScientificStatistics._();

  static List<double> _values(Iterable<num> values) {
    final items = values.map((v) => v.toDouble()).toList();
    if (items.isEmpty ||
        items.length > 100000 ||
        items.any((v) => !v.isFinite)) {
      throw ArgumentError('Finite nonempty sample under 100000 required');
    }
    return items;
  }

  static double mean(Iterable<num> values) {
    final sample = _values(values);
    // Compensated summation reduces error for mixed scales.
    var sum = 0.0;
    var compensation = 0.0;
    for (final x in sample) {
      final y = x - compensation;
      final next = sum + y;
      compensation = (next - sum) - y;
      sum = next;
    }
    return sum / sample.length;
  }

  static double median(Iterable<num> values) {
    final sample = _values(values)..sort();
    final middle = sample.length ~/ 2;
    if (sample.length.isOdd) return sample[middle];
    return sample[middle - 1] / 2 + sample[middle] / 2;
  }

  static double variance(Iterable<num> values, {bool sample = false}) {
    final data = _values(values);
    if (sample && data.length < 2) throw ArgumentError('Sample needs n >= 2');
    var n = 0;
    var mean = 0.0;
    var m2 = 0.0;
    for (final x in data) {
      n++;
      final delta = x - mean;
      mean += delta / n;
      m2 += delta * (x - mean);
    }
    return m2 / (sample ? n - 1 : n);
  }

  static double normalPdf(double x, {double mean = 0, double sigma = 1}) {
    if (!x.isFinite || !mean.isFinite || !sigma.isFinite || sigma <= 0) {
      throw ArgumentError('Invalid normal distribution parameter');
    }
    final z = (x - mean) / sigma;
    return math.exp(-0.5 * z * z) / (sigma * math.sqrt(2 * math.pi));
  }

  static double exponentialCdf(double x, {required double rate}) {
    if (!x.isFinite || !rate.isFinite || rate <= 0) {
      throw ArgumentError('Invalid exponential distribution parameter');
    }
    return x <= 0 ? 0 : 1 - math.exp(-rate * x);
  }

  static double binomialPmf(int k, {required int n, required double p}) {
    if (n < 0 ||
        n > 100000 ||
        k < 0 ||
        k > n ||
        !p.isFinite ||
        p < 0 ||
        p > 1) {
      throw ArgumentError('Invalid binomial parameters');
    }
    if (p == 0) return k == 0 ? 1 : 0;
    if (p == 1) return k == n ? 1 : 0;
    final m = math.min(k, n - k);
    var logChoose = 0.0;
    for (var i = 1; i <= m; i++) {
      logChoose += math.log((n - m + i) / i);
    }
    return math.exp(logChoose + k * math.log(p) + (n - k) * math.log(1 - p));
  }

  static int secureInteger(int upperExclusive) {
    if (upperExclusive <= 0 || upperExclusive > 0x7fffffff) {
      throw ArgumentError('Invalid secure random bound');
    }
    return math.Random.secure().nextInt(upperExclusive);
  }
}

/// Deterministic Xorshift32 for simulations. Never use for secrets.
final class SeededStatisticsRandom {
  SeededStatisticsRandom(int seed) : _state = seed & 0xffffffff {
    if (_state == 0) throw ArgumentError('Seed must be nonzero');
  }
  int _state;

  int nextUint32() {
    var x = _state;
    x ^= (x << 13) & 0xffffffff;
    x ^= x >> 17;
    x ^= (x << 5) & 0xffffffff;
    return _state = x & 0xffffffff;
  }

  double nextDouble() => nextUint32() / 4294967296.0;
}
