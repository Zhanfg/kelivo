import 'package:flutter_test/flutter_test.dart';
import 'package:Kelivo/features/home/services/scientific/scientific_operation_registry.dart';

void main() {
  test('catalog has at least 120 unique operations beyond expressions', () {
    final operations = ScientificOperationRegistry.operations;
    final ids = operations.map((op) => op.id).toSet();
    expect(ids.length, operations.length);
    expect(
      operations.where((op) => op.expression == null).length,
      greaterThanOrEqualTo(120),
    );
    expect(operations.where((op) => op.expression != null).length, 23);
    expect(
      operations
          .where((op) => op.status == ScientificOperationStatus.implemented)
          .length,
      10,
    );
    expect(ids, isNot(contains('statistics.percentile')));
    expect(ids, isNot(contains('random.random_normal')));
    expect(ids, isNot(contains('trigonometry.arcsin')));
    for (final id in [
      'basic.add',
      'trigonometry.sin',
      'complex.conjugate',
      'linear_algebra.matrix_multiply',
      'probability.normal_cdf',
      'statistics.quantile',
      'numerics.fft',
      'units.convert_pressure',
      'random.seeded_uniform',
    ]) {
      expect(ScientificOperationRegistry.contains(id), isTrue);
    }
    expect(ScientificOperationRegistry.contains('curl.exec'), isFalse);
    expect(ScientificOperationRegistry.lookup('unknown'), isNull);
    expect(
      () => ScientificOperationRegistry.operations.clear(),
      throwsUnsupportedError,
    );
  });

  test('each catalog entry publishes an argument schema, domain and route', () {
    for (final operation in ScientificOperationRegistry.operations) {
      final metadata = operation.toJson();
      final arguments = metadata['arguments'] as Map<String, Object?>;
      final properties = arguments['properties'] as Map<String, Object?>;
      expect(metadata['id'], startsWith('${metadata['domain']}.'));
      expect(metadata['domainRules'], isNotEmpty, reason: operation.id);
      expect(metadata['route'], isIn(['exact', 'approximate', 'mixed']));
      expect(metadata['status'], isIn(['planned', 'implemented']));
      expect(properties, isNotEmpty, reason: operation.id);
      expect(arguments['required'], unorderedEquals(properties.keys));
      expect(arguments['additionalProperties'], isFalse);
      expect(ScientificOperationRegistry.lookup(operation.id), same(operation));
    }
    final add = ScientificOperationRegistry.lookup('basic.add')!;
    expect(add.expression, 'a + b');
    expect(add.status, ScientificOperationStatus.planned);
    expect(add.route, ScientificNumericRoute.exact);
  });

  test('array, matrix and complex shapes publish their nested types', () {
    final scalar = ScientificArgumentShape.real.toJsonSchema();
    final array = ScientificArgumentShape.array.toJsonSchema();
    final matrix = ScientificArgumentShape.matrix.toJsonSchema();
    final complex = ScientificArgumentShape.complex.toJsonSchema();
    expect(array['type'], 'array');
    expect(array['items'], scalar);
    expect(matrix['type'], 'array');
    expect(matrix['items'], array);
    expect(complex['type'], 'object');
    expect(complex['properties'], {'real': scalar, 'imaginary': scalar});
    expect(complex['required'], unorderedEquals(['real', 'imaginary']));
    expect(complex['additionalProperties'], isFalse);
  });

  test('scientific request supports structured data roundtrip', () {
    final request = ScientificRequest(
      operationId: 'linear_algebra.matrix_multiply',
      arguments: {
        'a': [
          [1.0, 2.0],
          [3.0, 4.0],
        ],
        'b': [
          [1],
          [2],
        ],
      },
      precision: ScientificPrecision.float64,
    );
    final data = request.toJson();
    expect(data['schemaVersion'], 1);
    expect(ScientificRequest.fromJson(data).toJson(), data);
    expect(request.maxOperations, 100000);
  });

  test('arguments are detached, including nested objects', () {
    final numbers = <Object?>[1, 2, 3];
    final input = <String, Object?>{
      'vector': numbers,
      'meta': {'unit': 'm'},
    };
    final request = ScientificRequest(
      operationId: 'linear_algebra.norm',
      arguments: input,
    );
    numbers.add(4);
    input.clear();
    expect(request.arguments['vector'], [1, 2, 3]);
    expect(() => request.arguments.clear(), throwsUnsupportedError);
    expect(
      () => (request.arguments['vector'] as List).add(7),
      throwsUnsupportedError,
    );
    expect(
      () => (request.arguments['meta'] as Map)['unit'] = 'cm',
      throwsUnsupportedError,
    );
  });

  test(
    'requires operation and arguments and defaults the remaining fields',
    () {
      final request = ScientificRequest.fromJson({
        'operationId': 'basic.add',
        'arguments': {'a': 1, 'b': 2},
      });
      expect(request.precision, ScientificPrecision.float64);
      expect(request.maxOperations, 100000);
      expect(ScientificRequest.jsonSchema['required'], [
        'operationId',
        'arguments',
      ]);
    },
  );

  test('rejects malformed schema, precision and operation ID', () {
    final good = ScientificRequest(
      operationId: 'basic.add',
      arguments: {'a': 1, 'b': 2},
    ).toJson();
    expect(
      () => ScientificRequest.fromJson({...good, 'schemaVersion': 2}),
      throwsFormatException,
    );
    expect(
      () => ScientificRequest.fromJson({...good, 'precision': 'infinite'}),
      throwsFormatException,
    );
    expect(
      () => ScientificRequest.fromJson({...good, 'operationId': 'invalid id'}),
      throwsFormatException,
    );
    expect(
      () => ScientificRequest.fromJson({
        ...good,
        'arguments': {1: 'wrong key'},
      }),
      throwsFormatException,
    );
  });

  test('rejects nonfinite values, unbounded data and invalid budgets', () {
    expect(
      () => ScientificRequest(
        operationId: 'basic.add',
        arguments: {'a': double.nan},
      ),
      throwsArgumentError,
    );
    expect(
      () => ScientificRequest(
        operationId: 'basic.add',
        arguments: {'vector': List.filled(100, '0' * 4096)},
      ),
      throwsArgumentError,
    );
    expect(
      () => ScientificRequest(
        operationId: 'basic.add',
        arguments: {'a': double.infinity},
      ),
      throwsArgumentError,
    );
    expect(
      () => ScientificRequest(
        operationId: 'basic.add',
        arguments: {'vector': List.filled(4097, 0)},
      ),
      throwsArgumentError,
    );
    expect(
      () => ScientificRequest(
        operationId: 'basic.add',
        arguments: {'a': 1},
        maxOperations: 0,
      ),
      throwsArgumentError,
    );
    expect(
      () => ScientificRequest(
        operationId: 'basic.add',
        arguments: {'../../secret': 1},
      ),
      throwsArgumentError,
    );
  });

  test('precision wire values are strictly defined', () {
    expect(ScientificPrecision.fromWire('exact'), ScientificPrecision.exact);
    expect(
      ScientificPrecision.fromWire('float64'),
      ScientificPrecision.float64,
    );
    expect(
      () => ScientificPrecision.fromWire('arbitrary'),
      throwsFormatException,
    );
  });
}
