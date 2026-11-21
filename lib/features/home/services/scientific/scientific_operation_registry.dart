part 'scientific_operation_catalog.dart';

enum ScientificPrecision {
  exact('exact'),
  float64('float64');

  const ScientificPrecision(this.wireName);
  final String wireName;

  static ScientificPrecision fromWire(String raw) {
    for (final value in values) {
      if (value.wireName == raw) return value;
    }
    throw FormatException('Unsupported scientific precision');
  }
}

enum ScientificOperationStatus {
  planned('planned'),
  implemented('implemented');

  const ScientificOperationStatus(this.wireName);
  final String wireName;
}

enum ScientificNumericRoute { exact, approximate, mixed }

const _decimalPattern = r'[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?';
const _fractionPattern = r'[+-]?\d+/[1-9]\d*';
const _integerPattern = r'[+-]?\d+';
const _realPattern = '^(?:$_decimalPattern|$_fractionPattern)\$';

enum ScientificArgumentShape {
  real,
  integer,
  array,
  matrix,
  complex,
  complexArray,
  integerArray,
  text,
  boolean;

  static const maxArrayLength = 4096;
  static final _realLiteral = RegExp(_realPattern);
  static final _integerLiteral = RegExp('^$_integerPattern\$');

  bool accepts(Object? value) => switch (this) {
    real =>
      value is num && value.isFinite ||
          value is String && _realLiteral.hasMatch(value),
    integer =>
      value is int ||
          value is double &&
              value.isFinite &&
              value.truncateToDouble() == value ||
          value is String && _integerLiteral.hasMatch(value),
    array => value is List && value.every(real.accepts),
    matrix => value is List && value.every(array.accepts),
    complex =>
      value is Map &&
          value.length == 2 &&
          real.accepts(value['real']) &&
          real.accepts(value['imaginary']),
    complexArray => value is List && value.every(complex.accepts),
    integerArray => value is List && value.every(integer.accepts),
    text => value is String,
    boolean => value is bool,
  };

  Map<String, Object?> toJsonSchema() => switch (this) {
    real => _numericSchema('number', _realPattern),
    integer => _numericSchema('integer', '^$_integerPattern\$'),
    array => _arraySchema(real),
    matrix => _arraySchema(array),
    complex => _objectSchema({'real': real, 'imaginary': real}),
    complexArray => _arraySchema(complex),
    integerArray => _arraySchema(integer),
    text => {'type': 'string', 'maxLength': 4096},
    boolean => {'type': 'boolean'},
  };

  static Map<String, Object?> _numericSchema(String type, String pattern) => {
    'anyOf': [
      {'type': type},
      {'type': 'string', 'pattern': pattern, 'maxLength': 4096},
    ],
  };

  static Map<String, Object?> _arraySchema(ScientificArgumentShape items) => {
    'type': 'array',
    'items': items.toJsonSchema(),
    'maxItems': maxArrayLength,
  };
}

Map<String, Object?> _objectSchema(
  Map<String, ScientificArgumentShape> shapes,
) => {
  'type': 'object',
  'properties': {
    for (final entry in shapes.entries) entry.key: entry.value.toJsonSchema(),
  },
  'required': shapes.keys.toList(),
  'additionalProperties': false,
};

final class ScientificOperationSpec {
  const ScientificOperationSpec._(
    this.id,
    this.argumentShapes,
    this.domainRules,
    this.route, {
    this.status = ScientificOperationStatus.planned,
    this.expression,
  });

  final String id;
  String get domain => id.substring(0, id.indexOf('.'));
  final Map<String, ScientificArgumentShape> argumentShapes;
  final String domainRules;
  final ScientificNumericRoute route;

  /// Availability through the structured interface.
  final ScientificOperationStatus status;

  /// Syntax already available through the expression calculator, if any.
  final String? expression;

  Map<String, Object?> toJson() => {
    'id': id,
    'domain': domain,
    'arguments': _objectSchema(argumentShapes),
    'domainRules': domainRules,
    'route': route.name,
    'status': status.wireName,
    if (expression != null) 'expression': expression,
  };
}

abstract final class ScientificOperationRegistry {
  static final List<ScientificOperationSpec> operations = List.unmodifiable(
    _catalog,
  );

  static final Map<String, ScientificOperationSpec> _index = {
    for (final operation in operations) operation.id: operation,
  };

  static bool contains(String id) => _index.containsKey(id);
  static ScientificOperationSpec? lookup(String id) => _index[id];
}

/// The scientific_calculate request. The operation ID and named arguments are
/// required. Version, precision and computation budget have defaults.
///
/// The exact precision setting requires an exact route. Float64 permits an
/// approximate route while preserving exact results from exact operations.
final class ScientificRequest {
  ScientificRequest({
    required this.operationId,
    required Map<String, Object?> arguments,
    this.precision = ScientificPrecision.float64,
    this.maxOperations = _defaultBudget,
  }) : arguments = Map.unmodifiable(_copyJsonMap(arguments, 0, _JsonBudget())) {
    if (operationId.length > 90 || !_operationIdPattern.hasMatch(operationId)) {
      throw ArgumentError('Invalid scientific operation ID');
    }
    if (maxOperations < 1 || maxOperations > _maxBudget) {
      throw ArgumentError('Invalid computation budget');
    }
  }

  static const schemaVersion = 1;
  static const _defaultBudget = 100000;
  static const _maxBudget = 1000000;
  static const _idPattern = r'^[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)?$';
  static final _operationIdPattern = RegExp(_idPattern);

  /// Envelope schema. The registry supplies each operation's arguments schema.
  static const Map<String, Object?> jsonSchema = {
    'type': 'object',
    'properties': {
      'schemaVersion': {'const': schemaVersion, 'default': schemaVersion},
      'operationId': {'type': 'string', 'pattern': _idPattern, 'maxLength': 90},
      'arguments': {'type': 'object', 'maxProperties': 64},
      'precision': {
        'enum': ['exact', 'float64'],
        'default': 'float64',
      },
      'maxOperations': {
        'type': 'integer',
        'minimum': 1,
        'maximum': _maxBudget,
        'default': _defaultBudget,
      },
    },
    'required': ['operationId', 'arguments'],
    'additionalProperties': false,
  };

  final String operationId;
  final Map<String, Object?> arguments;
  final ScientificPrecision precision;
  final int maxOperations;

  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'operationId': operationId,
    'precision': precision.wireName,
    'maxOperations': maxOperations,
    'arguments': _copyJsonMap(arguments, 0, _JsonBudget()),
  };

  factory ScientificRequest.fromJson(Map<String, Object?> json) {
    const keys = {
      'schemaVersion',
      'operationId',
      'precision',
      'maxOperations',
      'arguments',
    };
    if (json.keys.any((key) => !keys.contains(key)) ||
        (json.containsKey('schemaVersion') &&
            json['schemaVersion'] != schemaVersion)) {
      throw const FormatException('Invalid scientific request schema');
    }
    final id = json['operationId'];
    final budget = json.containsKey('maxOperations')
        ? json['maxOperations']
        : _defaultBudget;
    final precision = json.containsKey('precision')
        ? json['precision']
        : 'float64';
    final arguments = json['arguments'];
    if (id is! String ||
        budget is! int ||
        precision is! String ||
        arguments is! Map ||
        arguments.keys.any((key) => key is! String)) {
      throw const FormatException('Scientific request field type mismatch');
    }
    try {
      return ScientificRequest(
        operationId: id,
        maxOperations: budget,
        precision: ScientificPrecision.fromWire(precision),
        arguments: Map<String, Object?>.from(arguments),
      );
    } on ArgumentError catch (e) {
      throw FormatException('Invalid scientific request: $e');
    }
  }
}

final class _JsonBudget {
  var remaining = 131072;

  void consume(int size) {
    remaining -= size;
    if (remaining < 0) {
      throw ArgumentError('Scientific arguments exceed the total size limit');
    }
  }
}

/// Copy only JSON primitives, arrays and maps. Reject callable/non-finite
/// values, deep recursion and excessive input sizes before any execution.
Map<String, Object?> _copyJsonMap(
  Map<String, Object?> map,
  int depth,
  _JsonBudget budget,
) {
  if (depth > 6 || map.length > 64) {
    throw ArgumentError('Scientific argument nesting/budget exceeded');
  }
  final out = <String, Object?>{};
  for (final entry in map.entries) {
    if (!RegExp(r'^[a-zA-Z][a-zA-Z0-9_]{0,63}$').hasMatch(entry.key)) {
      throw ArgumentError('Invalid scientific argument key');
    }
    budget.consume(entry.key.length);
    out[entry.key] = _copyValue(entry.value, depth + 1, budget);
  }
  return out;
}

Object? _copyValue(Object? value, int depth, _JsonBudget budget) {
  budget.consume(1);
  if (depth > 6) throw ArgumentError('Scientific value nested too deeply');
  if (value == null || value is bool || value is int) return value;
  if (value is double) {
    if (!value.isFinite) throw ArgumentError('Nonfinite numeric argument');
    return value;
  }
  if (value is String) {
    if (value.length > 4096) throw ArgumentError('Oversized string argument');
    budget.consume(value.length);
    return value;
  }
  if (value is List) {
    if (value.length > ScientificArgumentShape.maxArrayLength) {
      throw ArgumentError('Oversized array argument');
    }
    return List<Object?>.unmodifiable(
      value.map((item) => _copyValue(item, depth + 1, budget)),
    );
  }
  if (value is Map) {
    if (value.keys.any((key) => key is! String)) {
      throw ArgumentError('Non-string JSON object key');
    }
    return Map<String, Object?>.unmodifiable(
      _copyJsonMap(Map<String, Object?>.from(value), depth, budget),
    );
  }
  throw ArgumentError('Unsupported scientific argument type');
}
