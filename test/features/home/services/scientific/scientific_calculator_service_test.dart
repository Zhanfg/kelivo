import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:Kelivo/features/home/services/calculator_service.dart';
import 'package:Kelivo/features/home/services/scientific/scientific_calculator_service.dart';
import 'package:Kelivo/features/home/services/scientific/scientific_operation_registry.dart';

Map<String, Object?> _calculate(
  String id,
  Map<String, Object?> arguments, {
  String? precision,
  int? maxOperations,
}) => ScientificCalculatorService.scientificCalculate({
  'operationId': id,
  'arguments': arguments,
  if (precision != null) 'precision': precision,
  if (maxOperations != null) 'maxOperations': maxOperations,
});

void _expectError(Map<String, Object?> response, String code, {String? id}) {
  expect(
    response.keys,
    unorderedEquals([if (id != null) 'operationId', 'error']),
  );
  if (id != null) expect(response['operationId'], id);
  final error = response['error'] as Map<String, Object?>;
  expect(error.keys, unorderedEquals(['code', 'message']));
  expect(error['code'], code);
  expect(error['message'], isNotEmpty);
  expect(jsonDecode(jsonEncode(response)), response);
}

void main() {
  group('structured scientific operations', () {
    final cases = <String, ({Map<String, Object?> arguments, Object result})>{
      'basic.clamp': (
        arguments: {'x': 9, 'lower': 0, 'upper': '1/3'},
        result: '1/3',
      ),
      'basic.hypot': (
        arguments: {'x': '3e200', 'y': '4e200'},
        result: closeTo(5e200, 1e186),
      ),
      'trigonometry.atan2': (
        arguments: {'y': 1, 'x': -1},
        result: closeTo(3 * math.pi / 4, 1e-15),
      ),
      'transcendental.erf': (
        arguments: {'x': -1},
        result: closeTo(-0.8427007929497149, 1.6e-7),
      ),
      'number_theory.gcd': (
        arguments: {'a': '-9007199254740993', 'b': 3},
        result: '3',
      ),
      'number_theory.is_prime': (arguments: {'n': 2147483647}, result: true),
      'number_theory.combination': (
        arguments: {'n': 100, 'k': 50},
        result: '100891344545564193334812497256',
      ),
      'statistics.mean': (
        arguments: {
          'values': ['1/3', '2/3', 0],
        },
        result: '1/3',
      ),
      'linear_algebra.trace': (
        arguments: {
          'matrix': [
            ['.1', 9007199254740993],
            [0, '1/3'],
          ],
        },
        result: '13/30',
      ),
      'complex.conjugate': (
        arguments: {
          'z': {'real': '9007199254740993', 'imaginary': '-2/6'},
        },
        result: {'real': '9007199254740993', 'imaginary': '1/3'},
      ),
    };

    test('every implemented catalog operation has a reference case', () {
      final implemented = ScientificOperationRegistry.operations
          .where((spec) => spec.status == ScientificOperationStatus.implemented)
          .map((spec) => spec.id);
      expect(implemented, unorderedEquals(cases.keys));
    });

    const approximateOperations = {
      'basic.hypot',
      'trigonometry.atan2',
      'transcendental.erf',
    };
    for (final entry in cases.entries) {
      test(entry.key, () {
        final response = _calculate(entry.key, entry.value.arguments);
        expect(
          response.keys,
          unorderedEquals(['operationId', 'result', 'approximate']),
        );
        expect(response['operationId'], entry.key);
        expect(response['result'], entry.value.result);
        expect(
          response['approximate'],
          approximateOperations.contains(entry.key),
        );
        expect(jsonDecode(jsonEncode(response)), response);
      });
    }

    test('exact routes preserve zero, identity and large integer inputs', () {
      expect(
        _calculate('basic.clamp', {'x': 0, 'lower': 2, 'upper': 2})['result'],
        '2',
      );
      expect(
        _calculate('number_theory.gcd', {
          'a': 0,
          'b': 9007199254740993,
        })['result'],
        '9007199254740993',
      );
      expect(_calculate('number_theory.gcd', {'a': 0, 'b': 0})['result'], '0');
      expect(_calculate('number_theory.is_prime', {'n': 1})['result'], false);
      expect(_calculate('number_theory.is_prime', {'n': 49})['result'], false);
      expect(
        _calculate('number_theory.combination', {'n': 0, 'k': 0})['result'],
        '1',
      );
      expect(
        _calculate('number_theory.combination', {
          'n': 1000,
          'k': 999,
        })['result'],
        '1000',
      );
      expect(
        _calculate('statistics.mean', {
          'values': ['1e1000', '-1e1000', '1/7'],
        }, precision: 'exact')['result'],
        '1/21',
      );
      expect(
        _calculate('linear_algebra.trace', {
          'matrix': [
            ['-3/6'],
          ],
        })['result'],
        '-1/2',
      );
      expect(
        _calculate('complex.conjugate', {
          'z': {'real': '0.5', 'imaginary': '-0'},
        })['result'],
        {'real': '1/2', 'imaginary': '0'},
      );
    });

    test('float64 operations cover axes, extreme and tiny values', () {
      expect(
        _calculate('trigonometry.atan2', {'y': -1, 'x': 0})['result'],
        -math.pi / 2,
      );
      expect(
        _calculate('basic.hypot', {'x': '5e-324', 'y': 0})['result'],
        5e-324,
      );
      expect(_calculate('basic.hypot', {'x': 0, 'y': 0})['result'], 0);
      expect(_calculate('transcendental.erf', {'x': 0})['result'], 0);
      expect(
        _calculate('transcendental.erf', {'x': '1e-12'})['result'],
        closeTo(1.1283791670955126e-12, 1e-26),
      );
      expect(_calculate('transcendental.erf', {'x': '1e308'})['result'], 1);
      expect(
        _calculate('trigonometry.atan2', {
          'y': '1${'0' * 400}/${'9' * 400}',
          'x': 1,
        })['result'],
        closeTo(math.pi / 4, 1e-15),
      );
    });
  });

  group('structured scientific errors', () {
    test('distinguishes unknown IDs from planned operations', () {
      for (final id in ['unknown', 'statistics.no_such_operation']) {
        _expectError(_calculate(id, {}), 'unknown_operation', id: id);
      }
      _expectError(
        _calculate('basic.add', {'a': 1, 'b': 2}),
        'not_implemented',
        id: 'basic.add',
      );
      _expectError(
        _calculate('linear_algebra.matrix_multiply', {
          'a': [
            [1, 2],
          ],
          'b': [
            [3],
            [4],
          ],
        }),
        'not_implemented',
        id: 'linear_algebra.matrix_multiply',
      );
    });

    test('rejects malformed arguments and request envelopes', () {
      for (final args in [
        {'a': 2, 'b': '1.2'},
        {'a': '1+2', 'b': 2},
        {'a': 1, 'c': 2},
      ]) {
        _expectError(
          _calculate('number_theory.gcd', args),
          'invalid_arguments',
          id: 'number_theory.gcd',
        );
      }
      _expectError(
        _calculate('complex.conjugate', {
          'z': {'real': 1},
        }),
        'invalid_arguments',
        id: 'complex.conjugate',
      );
      _expectError(
        _calculate('basic.hypot', {'x': double.nan, 'y': 1}),
        'invalid_request',
      );
      _expectError(
        ScientificCalculatorService.scientificCalculate({
          'operationId': 'basic.hypot',
        }),
        'invalid_request',
      );
    });

    final domainCases = [
      ('basic.clamp', <String, Object?>{'x': 0, 'lower': 2, 'upper': 1}),
      ('basic.hypot', <String, Object?>{'x': '1.7e308', 'y': '1.7e308'}),
      ('trigonometry.atan2', <String, Object?>{'x': 0, 'y': 0}),
      ('transcendental.erf', <String, Object?>{'x': '1e400'}),
      ('number_theory.is_prime', <String, Object?>{'n': 2147483648}),
      ('number_theory.is_prime', <String, Object?>{'n': -1}),
      ('number_theory.combination', <String, Object?>{'n': 3, 'k': 4}),
      ('statistics.mean', <String, Object?>{'values': []}),
      (
        'linear_algebra.trace',
        <String, Object?>{
          'matrix': [
            [1, 2],
            [3],
          ],
        },
      ),
    ];
    for (final (id, arguments) in domainCases) {
      test('rejects out-of-domain arguments for $id $arguments', () {
        _expectError(_calculate(id, arguments), 'domain_violation', id: id);
      });
    }

    test('checks precision, arithmetic limits and the computation budget', () {
      _expectError(
        _calculate('transcendental.erf', {'x': 1}, precision: 'exact'),
        'precision_unavailable',
        id: 'transcendental.erf',
      );
      _expectError(
        _calculate('basic.clamp', {'x': '1e1001', 'lower': 0, 'upper': 1}),
        'calculation_limit',
        id: 'basic.clamp',
      );
      _expectError(
        _calculate('number_theory.combination', {
          'n': 100,
          'k': 50,
        }, maxOperations: 5),
        'calculation_limit',
        id: 'number_theory.combination',
      );
    });
  });

  test(
    'expression calculator keeps exact, repeating and approximate results',
    () {
      expect(CalculatorService.evaluate('0.1 + 0.2'), {
        'result': '0.3',
        'approximate': false,
      });
      expect(CalculatorService.evaluate('(-2)^3 + 5!'), {
        'result': '112',
        'approximate': false,
      });
      expect(CalculatorService.evaluate('1/3'), {
        'result': '0.333333333333333',
        'approximate': true,
        'note': 'Repeating decimal rounded to 15 significant digits.',
      });
      expect(CalculatorService.evaluate('sqrt(144) + sin(pi/2) + log(2,8)'), {
        'result': '16',
        'approximate': true,
        'note':
            'Uses double-precision approximations for functions/constants. '
            'Rounded to 15 significant digits; numerical error may accumulate.',
      });
      expect(
        () => CalculatorService.evaluate('1/0'),
        throwsA(isA<CalculatorException>()),
      );
      expect(
        () => CalculatorService.evaluate('atan2(1,2)'),
        throwsFormatException,
      );
    },
  );
}
