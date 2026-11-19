import 'dart:math' as math;

import 'package:Kelivo/features/home/services/scientific/scientific_linear_algebra.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('complex arithmetic agrees with reference values', () {
    final a = ScientificComplex(3, 4);
    final b = ScientificComplex(1, -2);
    final product = a.multiply(b);
    expect(product.real, closeTo(11, 1e-12));
    expect(product.imaginary, closeTo(-2, 1e-12));
    final sum = a.add(b);
    expect(sum.real, 4);
    expect(sum.imaginary, 2);
    expect(a.conjugate.imaginary, -4);
    expect(a.magnitude, closeTo(5, 1e-12));
    final quotient = a.divide(b);
    expect(quotient.real, closeTo(-1, 1e-12));
    expect(quotient.imaginary, closeTo(2, 1e-12));
    expect(() => a.divide(ScientificComplex(0, 0)), throwsArgumentError);
  });

  test('vector addition and dot products agree with references', () {
    expect(ScientificLinearAlgebra.vectorAdd([1, 2], [3, -2]), [4, 0]);
    expect(ScientificLinearAlgebra.dot([1, 2, 3], [4, 5, 6]), 32);
    expect(() => ScientificLinearAlgebra.dot([1], [1, 2]), throwsArgumentError);
  });

  test('matrix product agrees with reference values', () {
    expect(
      ScientificLinearAlgebra.multiply(
        [
          [1, 2],
          [3, 4],
        ],
        [
          [2, 0],
          [1, 2],
        ],
      ),
      [
        [4, 4],
        [10, 8],
      ],
    );
  });

  test('determinant tracks swaps and singularity', () {
    expect(
      ScientificLinearAlgebra.determinant([
        [0, 2],
        [3, 4],
      ]),
      closeTo(-6, 1e-12),
    );
    expect(
      ScientificLinearAlgebra.determinant([
        [1, 2],
        [2, 4],
      ]),
      0,
    );
    expect(
      () => ScientificLinearAlgebra.determinant([
        [1, 2, 3],
        [4, 5, 6],
      ]),
      throwsArgumentError,
    );
  });

  test('rank handles rectangular and dependent matrices', () {
    expect(
      ScientificLinearAlgebra.rank([
        [1, 2, 3],
        [2, 4, 6],
      ]),
      1,
    );
    expect(
      ScientificLinearAlgebra.rank([
        [0, 1, 0],
        [1, 0, 0],
      ]),
      2,
    );
  });

  test('solve uses partial pivoting and returns reference answer', () {
    final result = ScientificLinearAlgebra.solve(
      [
        [0, 2],
        [3, 4],
      ],
      [4, 11],
    );
    expect(result[0], closeTo(1, 1e-12));
    expect(result[1], closeTo(2, 1e-12));
  });

  test('ill-posed and non-finite inputs reject deterministically', () {
    expect(
      () => ScientificLinearAlgebra.solve(
        [
          [1, 2],
          [2, 4],
        ],
        [1, 2],
      ),
      throwsStateError,
    );
    expect(
      () => ScientificLinearAlgebra.rank([
        [1, double.nan],
      ]),
      throwsArgumentError,
    );
    expect(
      () => ScientificLinearAlgebra.solve(
        [
          [1],
        ],
        [double.infinity],
      ),
      throwsArgumentError,
    );
    expect(
      () => ScientificLinearAlgebra.determinant([
        [1],
      ], tolerance: math.pi),
      throwsArgumentError,
    );
  });

  test('input matrices are not mutated', () {
    final rows = <List<num>>[
      [1, 2],
      [3, 4],
    ];
    ScientificLinearAlgebra.determinant(rows);
    expect(rows, [
      [1, 2],
      [3, 4],
    ]);
  });
}
