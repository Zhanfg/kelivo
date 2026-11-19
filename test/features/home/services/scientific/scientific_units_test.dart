import 'package:Kelivo/features/home/services/scientific/scientific_units.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('SI conversions are exact for decimal and time scale', () {
    expect(SiUnits.kilometer.convertTo(1.5, SiUnits.meter), 1500);
    expect(SiUnits.meter.convertTo(100, SiUnits.centimeter), 10000);
    expect(SiUnits.hour.convertTo(2, SiUnits.second), 7200);
  });

  test('dimension mismatch is always rejected', () {
    expect(() => SiUnits.hour.convertTo(1, SiUnits.meter), throwsArgumentError);
    expect(
      () => SiQuantity(1, SiUnits.meter).add(SiQuantity(1, SiUnits.second)),
      throwsArgumentError,
    );
  });

  test('quantity addition canonicalizes target unit', () {
    final sum = SiQuantity(
      1,
      SiUnits.kilometer,
    ).add(SiQuantity(500, SiUnits.meter));
    expect(sum.value, 1.5);
    expect(sum.unit, same(SiUnits.kilometer));
  });

  test('multiplication combines seven base dimensions', () {
    final velocity = SiQuantity(
      100,
      SiUnits.meter,
    ).multiply(SiQuantity(2, SiUnits.second));
    expect(velocity.unit.dimension.powers, [1, 0, 1, 0, 0, 0, 0]);
    expect(SiDimension.length.divide(SiDimension.time).powers, [
      1,
      0,
      -1,
      0,
      0,
      0,
      0,
    ]);
  });

  test('invalid dimensions and definitions fail closed', () {
    expect(() => SiDimension([1]), throwsArgumentError);
    expect(
      () => SiUnit(
        symbol: 'invalid',
        dimension: SiDimension.dimensionless,
        toSi: -1,
      ),
      throwsArgumentError,
    );
    expect(
      () => SiUnits.meter.convertTo(double.nan, SiUnits.kilometer),
      throwsArgumentError,
    );
  });

  test('source versions, symbols and exact constants are pinned', () {
    expect(SiConstants.speedOfLight.value, 299792458);
    expect(SiConstants.speedOfLight.sourceVersion, 'SI2019');
    expect(SiConstants.planck.exact, isTrue);
    expect(SiConstants.avogadro.unit, 'mol^-1');
  });

  test('numerical tolerance is explicit and bounded', () {
    expect(SiConstants.approximatelyEqual(100, 100 + 1e-11), isTrue);
    expect(SiConstants.approximatelyEqual(1, 2), isFalse);
    expect(
      () => SiConstants.approximatelyEqual(1, 2, tolerance: 0),
      throwsArgumentError,
    );
  });
}
