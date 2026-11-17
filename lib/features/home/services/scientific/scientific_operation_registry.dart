/// Protocol-only scientific calculation operation catalog.
///
/// Every entry below is a proposed future operation, NOT an implemented
/// function. The existing CalculatorService.evaluate API is untouched.
/// Operators need independent implementations, reference vectors and
/// numerical error policies before they may be marked executable.
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

final class ScientificOperationSpec {
  ScientificOperationSpec({
    required this.id,
    required this.domain,
    this.status = ScientificOperationStatus.planned,
  }) {
    if (!RegExp(r'^[a-z][a-z0-9_]*\.[a-z][a-z0-9_]*$').hasMatch(id) ||
        !id.startsWith(domain + '.') ||
        id.length > 90) {
      throw ArgumentError.value(id, 'id', 'Invalid scientific operation ID');
    }
  }

  final String id;
  final String domain;
  final ScientificOperationStatus status;

  Map<String, Object?> toJson() => {
    'id': id,
    'domain': domain,
    'status': status.wireName,
  };
}

/// A data-only, typed and bounded request envelope.
///
/// Calling this constructor does not evaluate any scientific operation. The
/// execution layer must check per-operation signatures and error budgets.
final class ScientificRequest {
  ScientificRequest({
    required this.operationId,
    required Map<String, Object?> arguments,
    this.precision = ScientificPrecision.float64,
    this.maxOperations = 100000,
  }) : arguments = Map.unmodifiable(_copyJsonMap(arguments, 0)) {
    if (!ScientificOperationRegistry.contains(operationId)) {
      throw ArgumentError.value(
        operationId,
        'operationId',
        'Unknown operation',
      );
    }
    if (maxOperations < 1 || maxOperations > 1000000) {
      throw ArgumentError('Invalid computation budget');
    }
  }

  static const schemaVersion = 1;
  final String operationId;
  final Map<String, Object?> arguments;
  final ScientificPrecision precision;
  final int maxOperations;

  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'operationId': operationId,
    'precision': precision.wireName,
    'maxOperations': maxOperations,
    'arguments': _copyJsonMap(arguments, 0),
  };

  factory ScientificRequest.fromJson(Map<String, Object?> json) {
    const keys = {
      'schemaVersion',
      'operationId',
      'precision',
      'maxOperations',
      'arguments',
    };
    if (json.keys.toSet().difference(keys).isNotEmpty ||
        keys.difference(json.keys.toSet()).isNotEmpty ||
        json['schemaVersion'] != schemaVersion) {
      throw const FormatException('Invalid scientific request schema');
    }
    final id = json['operationId'];
    final budget = json['maxOperations'];
    final precision = json['precision'];
    final arguments = json['arguments'];
    if (id is! String ||
        budget is! int ||
        precision is! String ||
        arguments is! Map) {
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
      throw FormatException('Invalid scientific request: ' + e.toString());
    }
  }
}

/// Declarative operation IDs. Alias names are intentionally not enumerated.
///
/// Any operation found here is *planned*, with no evaluation or numeric
/// validity promised. Concrete signatures and verified algorithms are tracked
/// in follow-up Issues #81–#84 before enabling a function in the tool layer.
abstract final class ScientificOperationRegistry {
  static const Map<String, String> _namesByDomain = {
    'basic':
        'add subtract multiply divide modulo power negate absolute sign '
        'floor ceil round clamp hypot minimum maximum',
    'trigonometry':
        'sin cos tan asin acos atan atan2 sinh cosh tanh asinh acosh atanh '
        'sec csc cot',
    'transcendental':
        'exp expm1 ln log10 log2 log1p sqrt cbrt nth_root log_base '
        'gamma log_gamma erf erfc',
    'number_theory':
        'factorial permutation combination gcd lcm is_prime next_prime '
        'factorize mod_inverse mod_power extended_gcd fibonacci catalan '
        'partitions stirling_second',
    'complex':
        'add subtract multiply divide conjugate magnitude argument exp log '
        'power sqrt',
    'linear_algebra':
        'dot cross norm normalize matrix_add matrix_multiply transpose '
        'determinant inverse rank trace eigenvalues solve_linear '
        'qr_decompose svd_decompose',
    'statistics':
        'mean median mode variance standard_deviation quantile percentile '
        'weighted_mean covariance correlation linear_regression '
        'geometric_mean harmonic_mean skewness kurtosis',
    'probability':
        'normal_pdf normal_cdf normal_quantile binomial_pmf binomial_cdf '
        'poisson_pmf poisson_cdf exponential_pdf exponential_cdf '
        'beta_pdf gamma_pdf uniform_pdf chi_square_cdf sample_normal',
    'numerics':
        'bisection_root newton_root secant_root trapezoid_integral '
        'simpson_integral finite_difference linear_interpolation '
        'polynomial_interpolation fft ifft convolution moving_average',
    'units':
        'convert_length convert_mass convert_time convert_temperature '
        'convert_pressure convert_energy convert_power convert_angle '
        'convert_frequency convert_data_size dimension_multiply '
        'dimension_divide dimension_check',
    'random':
        'seeded_uniform secure_integer sample_without_replacement '
        'shuffle_with_seed random_normal poisson_sample weighted_choice',
  };

  static final List<ScientificOperationSpec> operations = List.unmodifiable(
    _build(),
  );

  static final Map<String, ScientificOperationSpec> _index = Map.unmodifiable({
    for (final entry in operations) entry.id: entry,
  });

  static List<ScientificOperationSpec> _build() {
    final result = <ScientificOperationSpec>[];
    for (final domain in _namesByDomain.keys) {
      for (final name in _namesByDomain[domain]!.split(' ')) {
        if (name.isEmpty) continue;
        result.add(
          ScientificOperationSpec(id: domain + '.' + name, domain: domain),
        );
      }
    }
    final ids = result.map((e) => e.id).toSet();
    if (ids.length != result.length) {
      throw StateError('Duplicate scientific operation identifier');
    }
    return result;
  }

  static bool contains(String id) => _index.containsKey(id);
  static ScientificOperationSpec? lookup(String id) => _index[id];
}

/// Copy only JSON primitives, arrays and maps. Reject callable/non-finite
/// values, deep recursion and excessive input sizes before any execution.
Map<String, Object?> _copyJsonMap(Map<String, Object?> map, int depth) {
  if (depth > 6 || map.length > 64) {
    throw ArgumentError('Scientific argument nesting/budget exceeded');
  }
  final out = <String, Object?>{};
  for (final entry in map.entries) {
    if (!RegExp(r'^[a-zA-Z][a-zA-Z0-9_]{0,63}$').hasMatch(entry.key)) {
      throw ArgumentError('Invalid scientific argument key');
    }
    out[entry.key] = _copyValue(entry.value, depth + 1);
  }
  return out;
}

Object? _copyValue(Object? value, int depth) {
  if (depth > 6) throw ArgumentError('Scientific value nested too deeply');
  if (value == null || value is bool || value is int) return value;
  if (value is double) {
    if (!value.isFinite) throw ArgumentError('Nonfinite numeric argument');
    return value;
  }
  if (value is String) {
    if (value.length > 4096) throw ArgumentError('Oversized string argument');
    return value;
  }
  if (value is List) {
    if (value.length > 4096) throw ArgumentError('Oversized vector argument');
    return List<Object?>.unmodifiable(
      value.map((item) => _copyValue(item, depth + 1)),
    );
  }
  if (value is Map) {
    if (value.keys.any((key) => key is! String)) {
      throw ArgumentError('Non-string JSON object key');
    }
    return Map<String, Object?>.unmodifiable(
      _copyJsonMap(Map<String, Object?>.from(value), depth),
    );
  }
  throw ArgumentError('Unsupported scientific argument type');
}
