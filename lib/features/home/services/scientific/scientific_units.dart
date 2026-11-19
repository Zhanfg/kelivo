import 'dart:math' as math;

/// Exponents for the seven SI base dimensions, ordered L, M, T, I, Θ, N, J.
final class SiDimension {
  SiDimension(List<int> powers) : powers = List.unmodifiable(powers) {
    if (powers.length != 7 || powers.any((power) => power.abs() > 32)) {
      throw ArgumentError('Invalid seven-dimensional SI exponent vector');
    }
  }

  final List<int> powers;

  static final dimensionless = SiDimension(List.filled(7, 0));
  static final length = SiDimension([1, 0, 0, 0, 0, 0, 0]);
  static final mass = SiDimension([0, 1, 0, 0, 0, 0, 0]);
  static final time = SiDimension([0, 0, 1, 0, 0, 0, 0]);

  SiDimension multiply(SiDimension other) =>
      SiDimension([for (var i = 0; i < 7; i++) powers[i] + other.powers[i]]);

  SiDimension divide(SiDimension other) =>
      SiDimension([for (var i = 0; i < 7; i++) powers[i] - other.powers[i]]);

  @override
  bool operator ==(Object other) =>
      other is SiDimension &&
      List.generate(7, (i) => powers[i] == other.powers[i]).every((e) => e);

  @override
  int get hashCode => Object.hashAll(powers);
}

/// Only multiplicative SI conversions are allowed. Offset scales (e.g.
/// Celsius) must use an explicit dedicated conversion interface.
final class SiUnit {
  SiUnit({required this.symbol, required this.dimension, required this.toSi}) {
    if (!RegExp(r'^[a-zA-Z0-9_.]{1,32}$').hasMatch(symbol) ||
        !toSi.isFinite ||
        toSi <= 0) {
      throw ArgumentError('Invalid SI unit definition');
    }
  }

  final String symbol;
  final SiDimension dimension;
  final double toSi;

  double convertTo(double value, SiUnit target) {
    if (dimension != target.dimension) {
      throw ArgumentError('Cannot convert between different dimensions');
    }
    if (!value.isFinite) throw ArgumentError('Nonfinite quantity');
    final result = value * toSi / target.toSi;
    if (!result.isFinite) throw StateError('Quantity conversion overflow');
    return result;
  }
}

final class SiQuantity {
  SiQuantity(this.value, this.unit) {
    if (!value.isFinite) throw ArgumentError('Nonfinite quantity');
  }

  final double value;
  final SiUnit unit;

  SiQuantity to(SiUnit target) =>
      SiQuantity(unit.convertTo(value, target), target);

  SiQuantity add(SiQuantity other) =>
      SiQuantity(value + other.unit.convertTo(other.value, unit), unit);

  SiQuantity multiply(SiQuantity other) => SiQuantity(
    value * other.value,
    SiUnit(
      symbol: 'derived',
      dimension: unit.dimension.multiply(other.unit.dimension),
      toSi: unit.toSi * other.unit.toSi,
    ),
  );
}

final class SiUnits {
  const SiUnits._();

  static final meter = SiUnit(
    symbol: 'm',
    dimension: SiDimension.length,
    toSi: 1,
  );
  static final kilometer = SiUnit(
    symbol: 'km',
    dimension: SiDimension.length,
    toSi: 1000,
  );
  static final centimeter = SiUnit(
    symbol: 'cm',
    dimension: SiDimension.length,
    toSi: 0.01,
  );
  static final second = SiUnit(
    symbol: 's',
    dimension: SiDimension.time,
    toSi: 1,
  );
  static final hour = SiUnit(
    symbol: 'h',
    dimension: SiDimension.time,
    toSi: 3600,
  );
  static final kilogram = SiUnit(
    symbol: 'kg',
    dimension: SiDimension.mass,
    toSi: 1,
  );
  static final gram = SiUnit(
    symbol: 'g',
    dimension: SiDimension.mass,
    toSi: 0.001,
  );
}

/// Values are pinned to a specific CODATA release and have recorded units.
final class SiPhysicalConstant {
  const SiPhysicalConstant({
    required this.name,
    required this.value,
    required this.unit,
    required this.sourceVersion,
    required this.exact,
  });

  final String name;
  final double value;
  final String unit;
  final String sourceVersion;
  final bool exact;
}

final class SiConstants {
  const SiConstants._();

  static const speedOfLight = SiPhysicalConstant(
    name: 'speed_of_light',
    value: 299792458,
    unit: 'm/s',
    sourceVersion: 'SI2019',
    exact: true,
  );

  static const planck = SiPhysicalConstant(
    name: 'planck_constant',
    value: 6.62607015e-34,
    unit: 'J.s',
    sourceVersion: 'SI2019',
    exact: true,
  );

  static const avogadro = SiPhysicalConstant(
    name: 'avogadro_constant',
    value: 6.02214076e23,
    unit: 'mol^-1',
    sourceVersion: 'SI2019',
    exact: true,
  );

  static bool approximatelyEqual(
    double a,
    double b, {
    double tolerance = 1e-12,
  }) {
    if (!a.isFinite || !b.isFinite || tolerance <= 0 || !tolerance.isFinite) {
      throw ArgumentError('Invalid numeric comparison');
    }
    return (a - b).abs() <= tolerance * math.max(1, math.max(a.abs(), b.abs()));
  }
}
