import 'dart:math' as math;

/// Deterministic float64 arithmetic. Inputs and results must remain finite.
final class ScientificComplex {
  ScientificComplex(this.real, this.imaginary) {
    if (!real.isFinite || !imaginary.isFinite) {
      throw ArgumentError('Complex components must be finite');
    }
  }

  final double real;
  final double imaginary;

  ScientificComplex add(ScientificComplex other) =>
      ScientificComplex(real + other.real, imaginary + other.imaginary);

  ScientificComplex multiply(ScientificComplex other) => ScientificComplex(
    real * other.real - imaginary * other.imaginary,
    real * other.imaginary + imaginary * other.real,
  );

  ScientificComplex get conjugate => ScientificComplex(real, -imaginary);
  double get magnitude => math.sqrt(real * real + imaginary * imaginary);

  ScientificComplex divide(ScientificComplex other) {
    final scale = math.max(other.real.abs(), other.imaginary.abs());
    if (scale == 0) throw ArgumentError('Division by zero complex number');
    final a = other.real / scale;
    final b = other.imaginary / scale;
    final denominator = a * a + b * b;
    return ScientificComplex(
      (real * a + imaginary * b) / denominator / scale,
      (imaginary * a - real * b) / denominator / scale,
    );
  }
}

/// Bounded matrix utilities. Independent of CalculatorService and its registry.
///
/// All calculations use double precision with scaled partial pivoting.
/// Near-singular matrices may be rejected rather than returning unstable answers.
final class ScientificLinearAlgebra {
  const ScientificLinearAlgebra._();

  static const int maxDimension = 32;
  static const double defaultTolerance = 1e-12;

  static List<List<double>> _matrix(List<List<num>> matrix) {
    if (matrix.isEmpty || matrix.length > maxDimension) {
      throw ArgumentError('Invalid matrix row count');
    }
    final width = matrix.first.length;
    if (width == 0 || width > maxDimension) {
      throw ArgumentError('Invalid matrix column count');
    }
    if (matrix.any((row) => row.length != width)) {
      throw ArgumentError('Ragged matrix');
    }
    final result = matrix
        .map((row) => row.map((value) => value.toDouble()).toList())
        .toList();
    if (result.any((row) => row.any((value) => !value.isFinite))) {
      throw ArgumentError('Non-finite matrix entry');
    }
    return result;
  }

  static void _tolerance(double tolerance) {
    if (!tolerance.isFinite || tolerance <= 0 || tolerance >= 1) {
      throw ArgumentError('Invalid numerical tolerance');
    }
  }

  static List<double> vectorAdd(List<num> first, List<num> second) {
    if (first.isEmpty ||
        first.length > maxDimension ||
        first.length != second.length) {
      throw ArgumentError('Vector dimensions must match');
    }
    final result = <double>[];
    for (var i = 0; i < first.length; i++) {
      final value = first[i].toDouble() + second[i].toDouble();
      if (!value.isFinite) throw ArgumentError('Non-finite vector result');
      result.add(value);
    }
    return List.unmodifiable(result);
  }

  static double dot(List<num> first, List<num> second) {
    if (first.isEmpty ||
        first.length > maxDimension ||
        first.length != second.length ||
        first.any((x) => !x.toDouble().isFinite) ||
        second.any((x) => !x.toDouble().isFinite)) {
      throw ArgumentError('Invalid vectors');
    }
    var sum = 0.0;
    for (var i = 0; i < first.length; i++) {
      sum += first[i].toDouble() * second[i].toDouble();
    }
    if (!sum.isFinite) throw ArgumentError('Non-finite dot product');
    return sum;
  }

  static List<List<double>> multiply(
    List<List<num>> left,
    List<List<num>> right,
  ) {
    final a = _matrix(left);
    final b = _matrix(right);
    if (a.first.length != b.length) {
      throw ArgumentError('Matrix dimensions do not match');
    }
    return List.unmodifiable(
      List.generate(a.length, (i) {
        return List<double>.unmodifiable(
          List.generate(b.first.length, (j) {
            var sum = 0.0;
            for (var k = 0; k < b.length; k++) {
              sum += a[i][k] * b[k][j];
            }
            if (!sum.isFinite) throw ArgumentError('Non-finite result');
            return sum;
          }),
        );
      }),
    );
  }

  static double determinant(
    List<List<num>> matrix, {
    double tolerance = defaultTolerance,
  }) {
    _tolerance(tolerance);
    final a = _matrix(matrix);
    final n = a.length;
    if (a.first.length != n) throw ArgumentError('Square matrix required');
    var determinant = 1.0;
    for (var column = 0; column < n; column++) {
      final pivot = _pivot(a, column, column);
      final norm = _columnMax(a, column, column);
      if (norm == 0) return 0;
      final value = a[pivot][column];
      if (value.abs() <= tolerance * norm) return 0;
      if (pivot != column) {
        final temp = a[column];
        a[column] = a[pivot];
        a[pivot] = temp;
        determinant = -determinant;
      }
      final diagonal = a[column][column];
      determinant *= diagonal;
      if (!determinant.isFinite) {
        throw ArgumentError('Determinant overflow');
      }
      for (var row = column + 1; row < n; row++) {
        final factor = a[row][column] / diagonal;
        for (var k = column + 1; k < n; k++) {
          a[row][k] -= factor * a[column][k];
        }
        a[row][column] = 0;
      }
    }
    return determinant;
  }

  static int rank(
    List<List<num>> matrix, {
    double tolerance = defaultTolerance,
  }) {
    _tolerance(tolerance);
    final a = _matrix(matrix);
    var row = 0;
    for (var column = 0; column < a.first.length && row < a.length; column++) {
      final pivot = _pivot(a, row, column);
      final norm = _columnMax(a, row, column);
      if (norm == 0 || a[pivot][column].abs() <= tolerance * norm) {
        continue;
      }
      final temp = a[row];
      a[row] = a[pivot];
      a[pivot] = temp;
      final diagonal = a[row][column];
      for (var r = row + 1; r < a.length; r++) {
        final factor = a[r][column] / diagonal;
        for (var c = column + 1; c < a.first.length; c++) {
          a[r][c] -= factor * a[row][c];
        }
        a[r][column] = 0;
      }
      row++;
    }
    return row;
  }

  /// Solves A*x=b with pivoting, rejecting singular/unstable systems.
  static List<double> solve(
    List<List<num>> matrix,
    List<num> right, {
    double tolerance = defaultTolerance,
  }) {
    _tolerance(tolerance);
    final a = _matrix(matrix);
    final n = a.length;
    if (a.first.length != n || right.length != n) {
      throw ArgumentError('Invalid equation dimensions');
    }
    final b = right.map((v) => v.toDouble()).toList();
    if (b.any((v) => !v.isFinite)) {
      throw ArgumentError('Non-finite equation value');
    }
    for (var col = 0; col < n; col++) {
      final pivot = _pivot(a, col, col);
      final norm = _columnMax(a, col, col);
      if (norm == 0 || a[pivot][col].abs() <= tolerance * norm) {
        throw StateError('Singular or ill-conditioned system');
      }
      final temp = a[col];
      a[col] = a[pivot];
      a[pivot] = temp;
      final rhs = b[col];
      b[col] = b[pivot];
      b[pivot] = rhs;
      final diagonal = a[col][col];
      for (var row = col + 1; row < n; row++) {
        final factor = a[row][col] / diagonal;
        for (var j = col + 1; j < n; j++) {
          a[row][j] -= factor * a[col][j];
        }
        b[row] -= factor * b[col];
        a[row][col] = 0;
      }
    }
    final answer = List<double>.filled(n, 0);
    for (var i = n - 1; i >= 0; i--) {
      var remainder = b[i];
      for (var j = i + 1; j < n; j++) {
        remainder -= a[i][j] * answer[j];
      }
      answer[i] = remainder / a[i][i];
      if (!answer[i].isFinite) throw StateError('Unstable solution');
    }
    return List.unmodifiable(answer);
  }

  static int _pivot(List<List<double>> a, int start, int column) {
    var best = start;
    for (var row = start + 1; row < a.length; row++) {
      if (a[row][column].abs() > a[best][column].abs()) best = row;
    }
    return best;
  }

  static double _columnMax(List<List<double>> a, int start, int column) {
    var max = 0.0;
    for (var row = start; row < a.length; row++) {
      max = math.max(max, a[row][column].abs());
    }
    return max;
  }
}
