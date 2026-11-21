import 'dart:math' as math;

import 'package:rational/rational.dart';

import 'scientific_numerics.dart';
import 'scientific_operation_registry.dart';

abstract final class ScientificCalculatorService {
  /// Executes a scientific_calculate request described by
  /// [ScientificRequest.jsonSchema] and the operation's registry entry.
  ///
  /// Success contains operationId, result and approximate. Exact scalars are
  /// strings containing a reduced fraction or integer. Complex results use
  /// real and imaginary fields, predicates return booleans, and approximate
  /// scalars are finite JSON numbers. Float64 operations require their input
  /// values to fit in that format without overflow or underflow to zero.
  ///
  /// Failures contain error.code and error.message, with operationId when the
  /// request envelope is valid. Codes are invalid_request, unknown_operation,
  /// not_implemented, invalid_arguments, domain_violation,
  /// precision_unavailable and calculation_limit.
  static Map<String, Object?> scientificCalculate(Map<String, Object?> json) {
    final ScientificRequest request;
    try {
      request = ScientificRequest.fromJson(json);
    } on FormatException catch (error) {
      return _error('invalid_request', error.message);
    }

    final id = request.operationId;
    final spec = ScientificOperationRegistry.lookup(id);
    if (spec == null) {
      return _error('unknown_operation', 'Unknown operation.', id);
    }
    if (spec.status == ScientificOperationStatus.planned) {
      return _error('not_implemented', 'Operation is planned.', id);
    }

    final arguments = request.arguments;
    final shapes = spec.argumentShapes;
    if (arguments.length != shapes.length ||
        shapes.entries.any(
          (entry) => !entry.value.accepts(arguments[entry.key]),
        )) {
      return _error(
        'invalid_arguments',
        'Expected arguments ${shapes.keys.join(', ')} with the shapes in the catalog.',
        id,
      );
    }
    final approximate = spec.route == ScientificNumericRoute.approximate;
    if (approximate && request.precision == ScientificPrecision.exact) {
      return _error(
        'precision_unavailable',
        'Operation requires float64 precision.',
        id,
      );
    }

    try {
      final calculation = _ScientificCalculation(request);
      final result = calculation.evaluate();
      return {'operationId': id, 'result': result, 'approximate': approximate};
    } on _CalculationError catch (error) {
      return _error(error.code, error.message, id);
    }
  }

  static Map<String, Object?> _error(
    String code,
    String message, [
    String? id,
  ]) => {
    if (id != null) 'operationId': id,
    'error': {'code': code, 'message': message},
  };
}

final class _ScientificCalculation {
  _ScientificCalculation(this.request) : _remaining = request.maxOperations - 1;

  final ScientificRequest request;
  int _remaining;

  Object evaluate() {
    final arguments = request.arguments;
    switch (request.operationId) {
      case 'basic.clamp':
        final x = _readReal(arguments['x']);
        final lower = _readReal(arguments['lower']);
        final upper = _readReal(arguments['upper']);
        if (lower > upper) {
          _domain('The lower bound must be at most the upper bound.');
        }
        return _exact(x.clamp(lower, upper));
      case 'basic.hypot':
        return _finite(
          _hypot(
            _float(_readReal(arguments['x'])),
            _float(_readReal(arguments['y'])),
          ),
        );
      case 'trigonometry.atan2':
        final y = _readReal(arguments['y']);
        final x = _readReal(arguments['x']);
        if (x == Rational.zero && y == Rational.zero) {
          _domain('x and y cannot both be zero.');
        }
        return _finite(math.atan2(_float(y), _float(x)));
      case 'transcendental.erf':
        return _finite(_erf(_float(_readReal(arguments['x']))));
      case 'number_theory.gcd':
        final a = _readReal(arguments['a']).numerator;
        final b = _readReal(arguments['b']).numerator;
        // The Euclidean algorithm halves the smaller operand every two steps.
        _consume(2 * math.min(a.abs().bitLength, b.abs().bitLength));
        return ScientificNumerics.gcd(a, b).toString();
      case 'number_theory.is_prime':
        final n = _readReal(arguments['n']).numerator;
        if (n.isNegative || n > BigInt.from(2147483647)) {
          _domain('n must be in [0, 2147483647].');
        }
        final candidate = n.toInt();
        if (candidate > 2 && candidate.isOdd) {
          _consume(math.sqrt(candidate).floor() ~/ 2);
        }
        return ScientificNumerics.isPrime(candidate);
      case 'number_theory.combination':
        return _combination(
          _readReal(arguments['n']).numerator,
          _readReal(arguments['k']).numerator,
        );
      case 'statistics.mean':
        final values = arguments['values'] as List<Object?>;
        if (values.isEmpty) _domain('Expected a nonempty array.');
        _consume(values.length);
        final sum = _sum(values);
        return _exact(sum / Rational.fromInt(values.length));
      case 'linear_algebra.trace':
        final matrix = (arguments['matrix'] as List<Object?>)
            .cast<List<Object?>>();
        if (matrix.isEmpty ||
            matrix.any((row) => row.length != matrix.length)) {
          _domain('Expected a nonempty square matrix.');
        }
        _consume(matrix.length * matrix.length);
        var trace = Rational.zero;
        for (var i = 0; i < matrix.length; i++) {
          for (var j = 0; j < matrix.length; j++) {
            final value = _readReal(matrix[i][j]);
            if (i == j) trace = _bounded(trace + value);
          }
        }
        return _exact(trace);
      case 'complex.conjugate':
        final z = arguments['z'] as Map<String, Object?>;
        return {
          'real': _exact(_readReal(z['real'])),
          'imaginary': _exact(-_readReal(z['imaginary'])),
        };
      default:
        throw StateError('Missing implementation for ${request.operationId}');
    }
  }

  String _combination(BigInt n, BigInt k) {
    if (k.isNegative || k > n || n > BigInt.from(1000)) {
      _domain('Expected 0 <= k <= n <= 1000.');
    }
    final count = n.toInt();
    final selected = math.min(k.toInt(), count - k.toInt());
    _consume(selected);
    var result = BigInt.one;
    for (var i = 1; i <= selected; i++) {
      result = result * BigInt.from(count - selected + i) ~/ BigInt.from(i);
    }
    return result.toString();
  }

  void _consume(int operations) {
    _remaining -= operations;
    if (_remaining < 0) {
      throw const _CalculationError(
        'calculation_limit',
        'Operation exceeds the computation budget.',
      );
    }
  }
}

Rational _readReal(Object? value) {
  final text = value.toString();
  final fraction = text.split('/');
  if (fraction.length == 2) {
    return _bounded(
      Rational(BigInt.parse(fraction[0]), BigInt.parse(fraction[1])),
    );
  }
  final decimal = text.toLowerCase().split('e');
  if (decimal.length == 2 &&
      BigInt.parse(decimal[1]).abs() > BigInt.from(1000)) {
    throw const _CalculationError(
      'calculation_limit',
      'Decimal exponent exceeds 1000.',
    );
  }
  return _bounded(Rational.parse(text));
}

Rational _sum(Iterable<Object?> values) {
  var sum = Rational.zero;
  for (final value in values) {
    sum = _bounded(sum + _readReal(value));
  }
  return sum;
}

Rational _bounded(Rational value) {
  if (value.numerator.abs().bitLength > 16384 ||
      value.denominator.bitLength > 16384) {
    throw const _CalculationError(
      'calculation_limit',
      'Rational value exceeds 16384 bits.',
    );
  }
  return value;
}

String _exact(Rational value) => _bounded(value).toString();

double _float(Rational value) {
  if (value == Rational.zero) return 0;
  // Scale and round the ratio in rational arithmetic. Converting the two
  // BigInts to doubles individually can overflow even for a small ratio.
  final digits =
      value.numerator.abs().toString().length -
      value.denominator.toString().length;
  final shift = 17 - digits;
  final scaled = (value * Rational.fromInt(10).pow(shift)).round();
  final result = double.parse('${scaled}e${-shift}');
  if (result == 0 || !result.isFinite) {
    _domain('Argument is outside the range of float64.');
  }
  return result;
}

double _finite(double result) {
  if (!result.isFinite) _domain('Result is outside the range of float64.');
  return result;
}

double _hypot(double x, double y) {
  final largest = math.max(x.abs(), y.abs());
  if (largest == 0) return 0;
  final ratio = math.min(x.abs(), y.abs()) / largest;
  return largest * math.sqrt(1 + ratio * ratio);
}

double _erf(double x) {
  final magnitude = x.abs();
  // Use the leading Taylor term near zero to avoid cancellation.
  if (magnitude < 0.0001) return x * (2 / math.sqrt(math.pi));

  // Abramowitz and Stegun, Handbook of Mathematical Functions, 7.1.26.
  // The approximation has a maximum absolute error of 1.5e-7.
  final t = 1 / (1 + 0.3275911 * magnitude);
  final polynomial =
      ((((1.061405429 * t - 1.453152027) * t + 1.421413741) * t - 0.284496736) *
              t +
          0.254829592) *
      t;
  final result = 1 - polynomial * math.exp(-magnitude * magnitude);
  return x.isNegative ? -result : result;
}

Never _domain(String message) =>
    throw _CalculationError('domain_violation', message);

final class _CalculationError implements Exception {
  const _CalculationError(this.code, this.message);

  final String code;
  final String message;
}
