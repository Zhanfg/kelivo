import 'package:flutter_test/flutter_test.dart';
import 'package:Kelivo/features/home/services/scientific/scientific_operation_registry.dart';

void main() {
  test('catalog includes 120+ unique planned operations', () {
    final operations = ScientificOperationRegistry.operations;
    expect(operations.length, greaterThanOrEqualTo(120));
    expect(operations.map((e) => e.id).toSet().length, operations.length);
    expect(
      operations.every((op) => op.status == ScientificOperationStatus.planned),
      isTrue,
    );
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

  test('catalog is metadata, not an executable scientific function', () {
    final info = ScientificOperationRegistry.lookup('basic.add')!;
    expect(info.toJson(), {
      'id': 'basic.add',
      'domain': 'basic',
      'status': 'planned',
    });
  });

  test('scientific request supports structured data roundtrip', () {
    final request = ScientificRequest(
      operationId: 'linear_algebra.matrix_multiply',
      arguments: {
        'matrix': [
          [1.0, 2.0],
          [3.0, 4.0],
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

  test('rejects malformed schema, precision and unsupported operation', () {
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
      () => ScientificRequest.fromJson({...good, 'operationId': 'shell.exec'}),
      throwsFormatException,
    );
    expect(
      () => ScientificRequest(operationId: 'unknown', arguments: {}),
      throwsArgumentError,
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
