part of 'scientific_operation_registry.dart';

const _scalar = {'x': ScientificArgumentShape.real};
const _pair = {
  'a': ScientificArgumentShape.real,
  'b': ScientificArgumentShape.real,
};
const _integerPair = {
  'a': ScientificArgumentShape.integer,
  'b': ScientificArgumentShape.integer,
};
const _sample = {'values': ScientificArgumentShape.array};
const _normal = {
  'x': ScientificArgumentShape.real,
  'mean': ScientificArgumentShape.real,
  'sigma': ScientificArgumentShape.real,
};
const _matrix = {'matrix': ScientificArgumentShape.matrix};
const _conversion = {
  'value': ScientificArgumentShape.real,
  'from': ScientificArgumentShape.text,
  'to': ScientificArgumentShape.text,
};
const _dimensions = {
  'a': ScientificArgumentShape.integerArray,
  'b': ScientificArgumentShape.integerArray,
};
const _complexPair = {
  'a': ScientificArgumentShape.complex,
  'b': ScientificArgumentShape.complex,
};
const _arrayPair = {
  'a': ScientificArgumentShape.array,
  'b': ScientificArgumentShape.array,
};

const _realInputs = 'Any finite real inputs.';
const _radians = 'Any finite real angle in radians.';
const _positiveX = 'x must be positive.';
const _nonemptyArray = 'A nonempty array of finite real values.';
const _complexInputs = 'The real and imaginary components must be finite.';
const _matchingArrays = 'Nonempty real arrays of identical length.';
const _normalX = 'Finite x and mean, and sigma > 0.';
const _rectangular = 'A nonempty rectangular matrix of real values.';
const _square = 'A nonempty square matrix of real values.';
const _fftInput =
    'A nonempty complex array with power-of-two length up to 4096.';

// Each ID describes one operation. The expression field records spellings
// already supported by the expression calculator.
const _catalog = <ScientificOperationSpec>[
  ScientificOperationSpec._(
    'basic.add',
    _pair,
    _realInputs,
    ScientificNumericRoute.exact,
    expression: 'a + b',
  ),
  ScientificOperationSpec._(
    'basic.subtract',
    _pair,
    _realInputs,
    ScientificNumericRoute.exact,
    expression: 'a - b',
  ),
  ScientificOperationSpec._(
    'basic.multiply',
    _pair,
    _realInputs,
    ScientificNumericRoute.exact,
    expression: 'a * b',
  ),
  ScientificOperationSpec._(
    'basic.divide',
    _pair,
    'b must be nonzero.',
    ScientificNumericRoute.exact,
    expression: 'a / b',
  ),
  ScientificOperationSpec._(
    'basic.modulo',
    _pair,
    'b must be nonzero. Returns a nonnegative Euclidean remainder.',
    ScientificNumericRoute.exact,
    expression: 'a % b',
  ),
  ScientificOperationSpec._(
    'basic.power',
    {
      'base': ScientificArgumentShape.real,
      'exponent': ScientificArgumentShape.real,
    },
    'A negative base requires an exact exponent with odd denominator. Zero requires a nonnegative exponent.',
    ScientificNumericRoute.mixed,
    expression: 'base ^ exponent',
  ),
  ScientificOperationSpec._(
    'basic.negate',
    _scalar,
    _realInputs,
    ScientificNumericRoute.exact,
    expression: '-x',
  ),
  ScientificOperationSpec._(
    'basic.absolute',
    _scalar,
    _realInputs,
    ScientificNumericRoute.exact,
    expression: 'abs(x)',
  ),
  ScientificOperationSpec._(
    'basic.sign',
    _scalar,
    _realInputs,
    ScientificNumericRoute.exact,
    expression: 'sgn(x)',
  ),
  ScientificOperationSpec._(
    'basic.floor',
    _scalar,
    _realInputs,
    ScientificNumericRoute.exact,
    expression: 'floor(x)',
  ),
  ScientificOperationSpec._(
    'basic.ceil',
    _scalar,
    _realInputs,
    ScientificNumericRoute.exact,
    expression: 'ceil(x)',
  ),
  ScientificOperationSpec._(
    'basic.round',
    _scalar,
    'Ties round away from zero.',
    ScientificNumericRoute.exact,
  ),
  ScientificOperationSpec._(
    'basic.clamp',
    {
      'x': ScientificArgumentShape.real,
      'lower': ScientificArgumentShape.real,
      'upper': ScientificArgumentShape.real,
    },
    'The lower bound must be at most the upper bound.',
    ScientificNumericRoute.exact,
    status: ScientificOperationStatus.implemented,
  ),
  ScientificOperationSpec._(
    'basic.hypot',
    {'x': ScientificArgumentShape.real, 'y': ScientificArgumentShape.real},
    'Any finite float64 inputs with a representable result.',
    ScientificNumericRoute.approximate,
    status: ScientificOperationStatus.implemented,
  ),
  ScientificOperationSpec._(
    'basic.minimum',
    _sample,
    _nonemptyArray,
    ScientificNumericRoute.exact,
  ),
  ScientificOperationSpec._(
    'basic.maximum',
    _sample,
    _nonemptyArray,
    ScientificNumericRoute.exact,
  ),

  ScientificOperationSpec._(
    'trigonometry.sin',
    _scalar,
    _radians,
    ScientificNumericRoute.approximate,
    expression: 'sin(x)',
  ),
  ScientificOperationSpec._(
    'trigonometry.cos',
    _scalar,
    _radians,
    ScientificNumericRoute.approximate,
    expression: 'cos(x)',
  ),
  ScientificOperationSpec._(
    'trigonometry.tan',
    _scalar,
    'Radians. Undefined when cos(x) is zero.',
    ScientificNumericRoute.approximate,
    expression: 'tan(x)',
  ),
  ScientificOperationSpec._(
    'trigonometry.asin',
    _scalar,
    'x must be in [-1, 1]. Returns radians.',
    ScientificNumericRoute.approximate,
    expression: 'arcsin(x)',
  ),
  ScientificOperationSpec._(
    'trigonometry.acos',
    _scalar,
    'x must be in [-1, 1]. Returns radians.',
    ScientificNumericRoute.approximate,
    expression: 'arccos(x)',
  ),
  ScientificOperationSpec._(
    'trigonometry.atan',
    _scalar,
    'Any finite real input. Returns radians.',
    ScientificNumericRoute.approximate,
    expression: 'arctan(x)',
  ),
  ScientificOperationSpec._(
    'trigonometry.atan2',
    {'y': ScientificArgumentShape.real, 'x': ScientificArgumentShape.real},
    'x and y cannot both be zero. Returns radians in [-pi, pi].',
    ScientificNumericRoute.approximate,
    status: ScientificOperationStatus.implemented,
  ),
  ScientificOperationSpec._(
    'trigonometry.sinh',
    _scalar,
    'Any real x with a finite float64 result.',
    ScientificNumericRoute.approximate,
  ),
  ScientificOperationSpec._(
    'trigonometry.cosh',
    _scalar,
    'Any real x with a finite float64 result.',
    ScientificNumericRoute.approximate,
  ),
  ScientificOperationSpec._(
    'trigonometry.tanh',
    _scalar,
    _realInputs,
    ScientificNumericRoute.approximate,
  ),
  ScientificOperationSpec._(
    'trigonometry.asinh',
    _scalar,
    _realInputs,
    ScientificNumericRoute.approximate,
  ),
  ScientificOperationSpec._(
    'trigonometry.acosh',
    _scalar,
    'x must be at least 1.',
    ScientificNumericRoute.approximate,
  ),
  ScientificOperationSpec._(
    'trigonometry.atanh',
    _scalar,
    'x must be strictly between -1 and 1.',
    ScientificNumericRoute.approximate,
  ),
  ScientificOperationSpec._(
    'trigonometry.sec',
    _scalar,
    'Radians. Undefined when cos(x) is zero.',
    ScientificNumericRoute.approximate,
  ),
  ScientificOperationSpec._(
    'trigonometry.csc',
    _scalar,
    'Radians. Undefined when sin(x) is zero.',
    ScientificNumericRoute.approximate,
  ),
  ScientificOperationSpec._(
    'trigonometry.cot',
    _scalar,
    'Radians. Undefined when sin(x) is zero.',
    ScientificNumericRoute.approximate,
  ),

  ScientificOperationSpec._(
    'transcendental.exp',
    _scalar,
    'Any real x with a finite float64 result.',
    ScientificNumericRoute.approximate,
    expression: 'e(x)',
  ),
  ScientificOperationSpec._(
    'transcendental.expm1',
    _scalar,
    'Any real x with a finite float64 result for exp(x) - 1.',
    ScientificNumericRoute.approximate,
  ),
  ScientificOperationSpec._(
    'transcendental.ln',
    _scalar,
    _positiveX,
    ScientificNumericRoute.approximate,
    expression: 'ln(x)',
  ),
  ScientificOperationSpec._(
    'transcendental.log10',
    _scalar,
    _positiveX,
    ScientificNumericRoute.approximate,
  ),
  ScientificOperationSpec._(
    'transcendental.log2',
    _scalar,
    _positiveX,
    ScientificNumericRoute.approximate,
  ),
  ScientificOperationSpec._(
    'transcendental.log1p',
    _scalar,
    'x must be greater than -1.',
    ScientificNumericRoute.approximate,
  ),
  ScientificOperationSpec._(
    'transcendental.sqrt',
    _scalar,
    'x must be nonnegative.',
    ScientificNumericRoute.approximate,
    expression: 'sqrt(x)',
  ),
  ScientificOperationSpec._(
    'transcendental.cbrt',
    _scalar,
    _realInputs,
    ScientificNumericRoute.mixed,
  ),
  ScientificOperationSpec._(
    'transcendental.nth_root',
    {'degree': ScientificArgumentShape.real, 'x': ScientificArgumentShape.real},
    'The degree must be nonzero. A negative radicand requires an exact reciprocal degree with odd denominator. Zero requires a positive degree.',
    ScientificNumericRoute.mixed,
    expression: 'nrt(degree, x)',
  ),
  ScientificOperationSpec._(
    'transcendental.log_base',
    {'base': ScientificArgumentShape.real, 'x': ScientificArgumentShape.real},
    'base and x must be positive, and base must differ from 1.',
    ScientificNumericRoute.approximate,
    expression: 'log(base, x)',
  ),
  ScientificOperationSpec._(
    'transcendental.gamma',
    _scalar,
    'x cannot be a nonpositive integer. The result must be finite.',
    ScientificNumericRoute.approximate,
  ),
  ScientificOperationSpec._(
    'transcendental.log_gamma',
    _scalar,
    'x must be positive.',
    ScientificNumericRoute.approximate,
  ),
  ScientificOperationSpec._(
    'transcendental.erf',
    _scalar,
    'Finite float64 x. Absolute error at most 1.6e-7.',
    ScientificNumericRoute.approximate,
    status: ScientificOperationStatus.implemented,
  ),
  ScientificOperationSpec._(
    'transcendental.erfc',
    _scalar,
    'Any finite float64 x.',
    ScientificNumericRoute.approximate,
  ),

  ScientificOperationSpec._(
    'number_theory.factorial',
    {'n': ScientificArgumentShape.integer},
    'n must be in [0, 1000].',
    ScientificNumericRoute.exact,
    expression: 'n!',
  ),
  ScientificOperationSpec._(
    'number_theory.permutation',
    {
      'n': ScientificArgumentShape.integer,
      'k': ScientificArgumentShape.integer,
    },
    '0 <= k <= n. Ordered selections without replacement.',
    ScientificNumericRoute.exact,
  ),
  ScientificOperationSpec._(
    'number_theory.combination',
    {
      'n': ScientificArgumentShape.integer,
      'k': ScientificArgumentShape.integer,
    },
    '0 <= k <= n <= 1000. Unordered selections without replacement.',
    ScientificNumericRoute.exact,
    status: ScientificOperationStatus.implemented,
  ),
  ScientificOperationSpec._(
    'number_theory.gcd',
    _integerPair,
    'Any integers. gcd(0, 0) is 0 by convention.',
    ScientificNumericRoute.exact,
    status: ScientificOperationStatus.implemented,
  ),
  ScientificOperationSpec._(
    'number_theory.lcm',
    _integerPair,
    'Any integers. Returns zero if either input is zero.',
    ScientificNumericRoute.exact,
  ),
  ScientificOperationSpec._(
    'number_theory.is_prime',
    {'n': ScientificArgumentShape.integer},
    'n must be in [0, 2147483647].',
    ScientificNumericRoute.exact,
    status: ScientificOperationStatus.implemented,
  ),
  ScientificOperationSpec._(
    'number_theory.next_prime',
    {'n': ScientificArgumentShape.integer},
    'n must be nonnegative. Returns the smallest prime strictly greater than n.',
    ScientificNumericRoute.exact,
  ),
  ScientificOperationSpec._(
    'number_theory.factorize',
    {'n': ScientificArgumentShape.integer},
    'n must be at least 2. Returns prime factors with multiplicity.',
    ScientificNumericRoute.exact,
  ),
  ScientificOperationSpec._(
    'number_theory.mod_inverse',
    {
      'a': ScientificArgumentShape.integer,
      'modulus': ScientificArgumentShape.integer,
    },
    'modulus must exceed 1 and a must be coprime to modulus.',
    ScientificNumericRoute.exact,
  ),
  ScientificOperationSpec._(
    'number_theory.mod_power',
    {
      'base': ScientificArgumentShape.integer,
      'exponent': ScientificArgumentShape.integer,
      'modulus': ScientificArgumentShape.integer,
    },
    'The exponent must be nonnegative and the modulus positive.',
    ScientificNumericRoute.exact,
  ),
  ScientificOperationSpec._(
    'number_theory.extended_gcd',
    _integerPair,
    'At least one input must be nonzero. Returns gcd and Bezout coefficients.',
    ScientificNumericRoute.exact,
  ),
  ScientificOperationSpec._(
    'number_theory.fibonacci',
    {'n': ScientificArgumentShape.integer},
    'n must be nonnegative. F(0) = 0 and F(1) = 1.',
    ScientificNumericRoute.exact,
  ),
  ScientificOperationSpec._(
    'number_theory.catalan',
    {'n': ScientificArgumentShape.integer},
    'n must be nonnegative. C(0) = 1.',
    ScientificNumericRoute.exact,
  ),
  ScientificOperationSpec._(
    'number_theory.partitions',
    {'n': ScientificArgumentShape.integer},
    'n must be nonnegative. The empty integer partition counts once.',
    ScientificNumericRoute.exact,
  ),
  ScientificOperationSpec._(
    'number_theory.stirling_second',
    {
      'n': ScientificArgumentShape.integer,
      'k': ScientificArgumentShape.integer,
    },
    '0 <= k <= n. Counts partitions into k nonempty subsets.',
    ScientificNumericRoute.exact,
  ),

  ScientificOperationSpec._(
    'complex.add',
    _complexPair,
    _complexInputs,
    ScientificNumericRoute.exact,
  ),
  ScientificOperationSpec._(
    'complex.subtract',
    _complexPair,
    _complexInputs,
    ScientificNumericRoute.exact,
  ),
  ScientificOperationSpec._(
    'complex.multiply',
    _complexPair,
    _complexInputs,
    ScientificNumericRoute.exact,
  ),
  ScientificOperationSpec._(
    'complex.divide',
    _complexPair,
    'At least one component of b must be nonzero.',
    ScientificNumericRoute.exact,
  ),
  ScientificOperationSpec._(
    'complex.conjugate',
    {'z': ScientificArgumentShape.complex},
    _complexInputs,
    ScientificNumericRoute.exact,
    status: ScientificOperationStatus.implemented,
  ),
  ScientificOperationSpec._(
    'complex.magnitude',
    {'z': ScientificArgumentShape.complex},
    'Any finite complex input with a finite float64 magnitude.',
    ScientificNumericRoute.approximate,
  ),
  ScientificOperationSpec._(
    'complex.argument',
    {'z': ScientificArgumentShape.complex},
    'z must be nonzero. Returns the principal argument in radians.',
    ScientificNumericRoute.approximate,
  ),
  ScientificOperationSpec._(
    'complex.exp',
    {'z': ScientificArgumentShape.complex},
    'Any finite complex input with finite float64 output components.',
    ScientificNumericRoute.approximate,
  ),
  ScientificOperationSpec._(
    'complex.log',
    {'z': ScientificArgumentShape.complex},
    'z must be nonzero. Returns the principal logarithm.',
    ScientificNumericRoute.approximate,
  ),
  ScientificOperationSpec._(
    'complex.power',
    {
      'base': ScientificArgumentShape.complex,
      'exponent': ScientificArgumentShape.complex,
    },
    'base must be nonzero. Uses the principal logarithm.',
    ScientificNumericRoute.approximate,
  ),
  ScientificOperationSpec._(
    'complex.sqrt',
    {'z': ScientificArgumentShape.complex},
    'Returns the principal square root for any finite complex input.',
    ScientificNumericRoute.approximate,
  ),

  ScientificOperationSpec._(
    'linear_algebra.dot',
    _arrayPair,
    _matchingArrays,
    ScientificNumericRoute.exact,
  ),
  ScientificOperationSpec._(
    'linear_algebra.cross',
    _arrayPair,
    'Both arrays must contain exactly three real entries.',
    ScientificNumericRoute.exact,
  ),
  ScientificOperationSpec._(
    'linear_algebra.norm',
    _sample,
    'Nonempty array. Uses the Euclidean norm.',
    ScientificNumericRoute.approximate,
  ),
  ScientificOperationSpec._(
    'linear_algebra.normalize',
    _sample,
    'Nonempty array with a nonzero Euclidean norm.',
    ScientificNumericRoute.approximate,
  ),
  ScientificOperationSpec._(
    'linear_algebra.matrix_add',
    {'a': ScientificArgumentShape.matrix, 'b': ScientificArgumentShape.matrix},
    'Nonempty rectangular matrices with identical dimensions.',
    ScientificNumericRoute.exact,
  ),
  ScientificOperationSpec._(
    'linear_algebra.matrix_multiply',
    {'a': ScientificArgumentShape.matrix, 'b': ScientificArgumentShape.matrix},
    'Nonempty rectangular matrices. Columns of a must equal rows of b.',
    ScientificNumericRoute.exact,
  ),
  ScientificOperationSpec._(
    'linear_algebra.transpose',
    _matrix,
    _rectangular,
    ScientificNumericRoute.exact,
  ),
  ScientificOperationSpec._(
    'linear_algebra.determinant',
    _matrix,
    _square,
    ScientificNumericRoute.mixed,
  ),
  ScientificOperationSpec._(
    'linear_algebra.inverse',
    _matrix,
    'A nonempty square matrix with nonzero determinant.',
    ScientificNumericRoute.mixed,
  ),
  ScientificOperationSpec._(
    'linear_algebra.rank',
    _matrix,
    _rectangular,
    ScientificNumericRoute.mixed,
  ),
  ScientificOperationSpec._(
    'linear_algebra.trace',
    _matrix,
    'A nonempty square matrix. All entries must be finite real values.',
    ScientificNumericRoute.exact,
    status: ScientificOperationStatus.implemented,
  ),
  ScientificOperationSpec._(
    'linear_algebra.eigenvalues',
    _matrix,
    'A nonempty square real matrix. Eigenvalues may be complex.',
    ScientificNumericRoute.approximate,
  ),
  ScientificOperationSpec._(
    'linear_algebra.solve_linear',
    {
      'matrix': ScientificArgumentShape.matrix,
      'rhs': ScientificArgumentShape.array,
    },
    'A nonsingular square matrix and a right-hand side matching its row count.',
    ScientificNumericRoute.mixed,
  ),
  ScientificOperationSpec._(
    'linear_algebra.qr_decompose',
    _matrix,
    _rectangular,
    ScientificNumericRoute.approximate,
  ),
  ScientificOperationSpec._(
    'linear_algebra.svd_decompose',
    _matrix,
    _rectangular,
    ScientificNumericRoute.approximate,
  ),

  ScientificOperationSpec._(
    'statistics.mean',
    _sample,
    _nonemptyArray,
    ScientificNumericRoute.exact,
    status: ScientificOperationStatus.implemented,
  ),
  ScientificOperationSpec._(
    'statistics.median',
    _sample,
    'Nonempty real array. Averages the middle pair for even lengths.',
    ScientificNumericRoute.exact,
  ),
  ScientificOperationSpec._(
    'statistics.mode',
    _sample,
    'Nonempty real array. Returns all values tied for greatest frequency.',
    ScientificNumericRoute.exact,
  ),
  ScientificOperationSpec._(
    'statistics.variance',
    {
      'values': ScientificArgumentShape.array,
      'sample': ScientificArgumentShape.boolean,
    },
    'Nonempty array. Sample variance requires at least two items.',
    ScientificNumericRoute.exact,
  ),
  ScientificOperationSpec._(
    'statistics.standard_deviation',
    {
      'values': ScientificArgumentShape.array,
      'sample': ScientificArgumentShape.boolean,
    },
    'Nonempty array. Sample standard deviation requires at least two items.',
    ScientificNumericRoute.approximate,
  ),
  ScientificOperationSpec._(
    'statistics.quantile',
    {
      'values': ScientificArgumentShape.array,
      'p': ScientificArgumentShape.real,
    },
    'Nonempty real array and p in [0, 1]. Uses linear interpolation between sorted values.',
    ScientificNumericRoute.exact,
  ),
  ScientificOperationSpec._(
    'statistics.weighted_mean',
    {
      'values': ScientificArgumentShape.array,
      'weights': ScientificArgumentShape.array,
    },
    'Nonempty arrays of equal length. Weights must be nonnegative with positive sum.',
    ScientificNumericRoute.exact,
  ),
  ScientificOperationSpec._(
    'statistics.covariance',
    {
      'x': ScientificArgumentShape.array,
      'y': ScientificArgumentShape.array,
      'sample': ScientificArgumentShape.boolean,
    },
    'Equal nonempty arrays. Sample covariance requires at least two pairs.',
    ScientificNumericRoute.exact,
  ),
  ScientificOperationSpec._(
    'statistics.correlation',
    {'x': ScientificArgumentShape.array, 'y': ScientificArgumentShape.array},
    'Equal-length arrays with at least two pairs and nonzero variance in both arrays.',
    ScientificNumericRoute.approximate,
  ),
  ScientificOperationSpec._(
    'statistics.linear_regression',
    {'x': ScientificArgumentShape.array, 'y': ScientificArgumentShape.array},
    'Equal-length arrays with at least two pairs and nonconstant x. Fits slope and intercept.',
    ScientificNumericRoute.exact,
  ),
  ScientificOperationSpec._(
    'statistics.geometric_mean',
    _sample,
    'Nonempty array of positive reals.',
    ScientificNumericRoute.approximate,
  ),
  ScientificOperationSpec._(
    'statistics.harmonic_mean',
    _sample,
    'Nonempty array of positive reals.',
    ScientificNumericRoute.exact,
  ),
  ScientificOperationSpec._(
    'statistics.skewness',
    _sample,
    'At least three real observations with nonzero variance.',
    ScientificNumericRoute.approximate,
  ),
  ScientificOperationSpec._(
    'statistics.kurtosis',
    _sample,
    'At least four real observations with nonzero variance. Returns excess kurtosis.',
    ScientificNumericRoute.exact,
  ),

  ScientificOperationSpec._(
    'probability.normal_pdf',
    _normal,
    _normalX,
    ScientificNumericRoute.approximate,
  ),
  ScientificOperationSpec._(
    'probability.normal_cdf',
    _normal,
    _normalX,
    ScientificNumericRoute.approximate,
  ),
  ScientificOperationSpec._(
    'probability.normal_quantile',
    {
      'p': ScientificArgumentShape.real,
      'mean': ScientificArgumentShape.real,
      'sigma': ScientificArgumentShape.real,
    },
    '0 < p < 1 and sigma > 0.',
    ScientificNumericRoute.approximate,
  ),
  ScientificOperationSpec._(
    'probability.binomial_pmf',
    {
      'k': ScientificArgumentShape.integer,
      'n': ScientificArgumentShape.integer,
      'p': ScientificArgumentShape.real,
    },
    '0 <= k <= n and 0 <= p <= 1.',
    ScientificNumericRoute.mixed,
  ),
  ScientificOperationSpec._(
    'probability.binomial_cdf',
    {
      'k': ScientificArgumentShape.integer,
      'n': ScientificArgumentShape.integer,
      'p': ScientificArgumentShape.real,
    },
    '0 <= k <= n and 0 <= p <= 1.',
    ScientificNumericRoute.mixed,
  ),
  ScientificOperationSpec._(
    'probability.poisson_pmf',
    {
      'k': ScientificArgumentShape.integer,
      'rate': ScientificArgumentShape.real,
    },
    'k must be nonnegative and rate must be positive.',
    ScientificNumericRoute.approximate,
  ),
  ScientificOperationSpec._(
    'probability.poisson_cdf',
    {
      'k': ScientificArgumentShape.integer,
      'rate': ScientificArgumentShape.real,
    },
    'k must be nonnegative and rate must be positive.',
    ScientificNumericRoute.approximate,
  ),
  ScientificOperationSpec._(
    'probability.exponential_pdf',
    {'x': ScientificArgumentShape.real, 'rate': ScientificArgumentShape.real},
    'rate must be positive. Density is zero for x < 0.',
    ScientificNumericRoute.approximate,
  ),
  ScientificOperationSpec._(
    'probability.exponential_cdf',
    {'x': ScientificArgumentShape.real, 'rate': ScientificArgumentShape.real},
    'rate must be positive. CDF is zero for x <= 0.',
    ScientificNumericRoute.approximate,
  ),
  ScientificOperationSpec._(
    'probability.beta_pdf',
    {
      'x': ScientificArgumentShape.real,
      'alpha': ScientificArgumentShape.real,
      'beta': ScientificArgumentShape.real,
    },
    '0 < x < 1, alpha > 0, and beta > 0.',
    ScientificNumericRoute.approximate,
  ),
  ScientificOperationSpec._(
    'probability.gamma_pdf',
    {
      'x': ScientificArgumentShape.real,
      'shape': ScientificArgumentShape.real,
      'scale': ScientificArgumentShape.real,
    },
    'x, shape and scale must all be positive.',
    ScientificNumericRoute.approximate,
  ),
  ScientificOperationSpec._(
    'probability.uniform_pdf',
    {
      'x': ScientificArgumentShape.real,
      'lower': ScientificArgumentShape.real,
      'upper': ScientificArgumentShape.real,
    },
    'lower must be less than upper. Density is zero outside the closed interval.',
    ScientificNumericRoute.exact,
  ),
  ScientificOperationSpec._(
    'probability.chi_square_cdf',
    {
      'x': ScientificArgumentShape.real,
      'degrees': ScientificArgumentShape.real,
    },
    'x must be nonnegative and degrees of freedom positive.',
    ScientificNumericRoute.approximate,
  ),
  ScientificOperationSpec._(
    'probability.sample_normal',
    {
      'mean': ScientificArgumentShape.real,
      'sigma': ScientificArgumentShape.real,
      'count': ScientificArgumentShape.integer,
      'seed': ScientificArgumentShape.integer,
    },
    'sigma and count must be positive. The seed selects a reproducible sample.',
    ScientificNumericRoute.approximate,
  ),

  ScientificOperationSpec._(
    'numerics.bisection_root',
    {
      'expression': ScientificArgumentShape.text,
      'lower': ScientificArgumentShape.real,
      'upper': ScientificArgumentShape.real,
      'tolerance': ScientificArgumentShape.real,
    },
    'lower < upper and 0 < tolerance < 1. A continuous function of x must bracket a root or have a zero endpoint.',
    ScientificNumericRoute.approximate,
  ),
  ScientificOperationSpec._(
    'numerics.newton_root',
    {
      'expression': ScientificArgumentShape.text,
      'derivative': ScientificArgumentShape.text,
      'start': ScientificArgumentShape.real,
      'tolerance': ScientificArgumentShape.real,
    },
    '0 < tolerance < 1. The function and derivative of x must remain finite during iteration with nonzero derivatives before convergence.',
    ScientificNumericRoute.approximate,
  ),
  ScientificOperationSpec._(
    'numerics.secant_root',
    {
      'expression': ScientificArgumentShape.text,
      'first': ScientificArgumentShape.real,
      'second': ScientificArgumentShape.real,
      'tolerance': ScientificArgumentShape.real,
    },
    'Distinct starting points and 0 < tolerance < 1. Iteration requires finite, distinct function values until convergence.',
    ScientificNumericRoute.approximate,
  ),
  ScientificOperationSpec._(
    'numerics.trapezoid_integral',
    {
      'values': ScientificArgumentShape.array,
      'step': ScientificArgumentShape.real,
    },
    'At least two equally spaced samples and a positive step.',
    ScientificNumericRoute.exact,
  ),
  ScientificOperationSpec._(
    'numerics.simpson_integral',
    {
      'values': ScientificArgumentShape.array,
      'step': ScientificArgumentShape.real,
    },
    'An odd number of at least three equally spaced samples and a positive step.',
    ScientificNumericRoute.exact,
  ),
  ScientificOperationSpec._(
    'numerics.finite_difference',
    {
      'values': ScientificArgumentShape.array,
      'step': ScientificArgumentShape.real,
    },
    'Exactly two adjacent samples and a positive step. Computes the forward first derivative.',
    ScientificNumericRoute.exact,
  ),
  ScientificOperationSpec._(
    'numerics.linear_interpolation',
    {
      'x0': ScientificArgumentShape.real,
      'y0': ScientificArgumentShape.real,
      'x1': ScientificArgumentShape.real,
      'y1': ScientificArgumentShape.real,
      'x': ScientificArgumentShape.real,
    },
    'x0 < x1 and x in [x0, x1].',
    ScientificNumericRoute.exact,
  ),
  ScientificOperationSpec._(
    'numerics.polynomial_interpolation',
    {
      'nodes': ScientificArgumentShape.array,
      'values': ScientificArgumentShape.array,
      'x': ScientificArgumentShape.real,
    },
    'Equal nonempty arrays with distinct nodes.',
    ScientificNumericRoute.exact,
  ),
  ScientificOperationSpec._(
    'numerics.fft',
    {'values': ScientificArgumentShape.complexArray},
    _fftInput,
    ScientificNumericRoute.approximate,
  ),
  ScientificOperationSpec._(
    'numerics.ifft',
    {'values': ScientificArgumentShape.complexArray},
    _fftInput,
    ScientificNumericRoute.approximate,
  ),
  ScientificOperationSpec._(
    'numerics.convolution',
    _arrayPair,
    'Two nonempty real arrays. Computes the full linear convolution.',
    ScientificNumericRoute.exact,
  ),
  ScientificOperationSpec._(
    'numerics.moving_average',
    {
      'values': ScientificArgumentShape.array,
      'window': ScientificArgumentShape.integer,
    },
    '1 <= window <= the number of values. Returns complete windows only.',
    ScientificNumericRoute.exact,
  ),

  ScientificOperationSpec._(
    'units.convert_length',
    _conversion,
    'from and to must be supported length units.',
    ScientificNumericRoute.mixed,
  ),
  ScientificOperationSpec._(
    'units.convert_mass',
    _conversion,
    'from and to must be supported mass units.',
    ScientificNumericRoute.mixed,
  ),
  ScientificOperationSpec._(
    'units.convert_time',
    _conversion,
    'from and to must be supported fixed-duration time units.',
    ScientificNumericRoute.mixed,
  ),
  ScientificOperationSpec._(
    'units.convert_temperature',
    _conversion,
    'Supported absolute temperature scales. Input must be at or above absolute zero.',
    ScientificNumericRoute.exact,
  ),
  ScientificOperationSpec._(
    'units.convert_pressure',
    _conversion,
    'from and to must be supported pressure units.',
    ScientificNumericRoute.mixed,
  ),
  ScientificOperationSpec._(
    'units.convert_energy',
    _conversion,
    'from and to must be supported energy units.',
    ScientificNumericRoute.mixed,
  ),
  ScientificOperationSpec._(
    'units.convert_power',
    _conversion,
    'from and to must be supported power units.',
    ScientificNumericRoute.mixed,
  ),
  ScientificOperationSpec._(
    'units.convert_angle',
    _conversion,
    'Supported angle units. Conversion involving pi may be approximate.',
    ScientificNumericRoute.mixed,
  ),
  ScientificOperationSpec._(
    'units.convert_frequency',
    _conversion,
    'from and to must be supported frequency units.',
    ScientificNumericRoute.mixed,
  ),
  ScientificOperationSpec._(
    'units.convert_data_size',
    _conversion,
    'Supported decimal or binary data-size units. Input must be nonnegative.',
    ScientificNumericRoute.exact,
  ),
  ScientificOperationSpec._(
    'units.dimension_multiply',
    _dimensions,
    'Two seven-entry SI exponent vectors. Adds corresponding exponents.',
    ScientificNumericRoute.exact,
  ),
  ScientificOperationSpec._(
    'units.dimension_divide',
    _dimensions,
    'Two seven-entry SI exponent vectors. Subtracts corresponding exponents.',
    ScientificNumericRoute.exact,
  ),
  ScientificOperationSpec._(
    'units.dimension_check',
    _dimensions,
    'Two seven-entry SI exponent vectors. Tests dimensional equality.',
    ScientificNumericRoute.exact,
  ),

  ScientificOperationSpec._(
    'random.seeded_uniform',
    {
      'seed': ScientificArgumentShape.integer,
      'count': ScientificArgumentShape.integer,
    },
    'A nonzero 32-bit unsigned seed and a positive count. Returns samples in [0, 1).',
    ScientificNumericRoute.exact,
  ),
  ScientificOperationSpec._(
    'random.secure_integer',
    {'upper_exclusive': ScientificArgumentShape.integer},
    '1 <= upper_exclusive <= 2147483647. Draws uniformly from [0, upper_exclusive).',
    ScientificNumericRoute.exact,
  ),
  ScientificOperationSpec._(
    'random.sample_without_replacement',
    {
      'values': ScientificArgumentShape.array,
      'count': ScientificArgumentShape.integer,
      'seed': ScientificArgumentShape.integer,
    },
    '0 <= count <= the number of values. Selects distinct positions.',
    ScientificNumericRoute.exact,
  ),
  ScientificOperationSpec._(
    'random.shuffle_with_seed',
    {
      'values': ScientificArgumentShape.array,
      'seed': ScientificArgumentShape.integer,
    },
    'Any real array and integer seed. Returns a reproducible permutation.',
    ScientificNumericRoute.exact,
  ),
  ScientificOperationSpec._(
    'random.poisson_sample',
    {
      'rate': ScientificArgumentShape.real,
      'count': ScientificArgumentShape.integer,
      'seed': ScientificArgumentShape.integer,
    },
    'rate and count must be positive. Uses float64 sampling to generate integer draws.',
    ScientificNumericRoute.approximate,
  ),
  ScientificOperationSpec._(
    'random.weighted_choice',
    {
      'values': ScientificArgumentShape.array,
      'weights': ScientificArgumentShape.array,
      'seed': ScientificArgumentShape.integer,
    },
    'Equal nonempty arrays. Weights must be nonnegative with positive sum.',
    ScientificNumericRoute.mixed,
  ),
];
