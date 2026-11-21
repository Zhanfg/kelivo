import 'dart:math' as math;

/// Describes the raw value of one ask_user answer.
sealed class AskUserInput {
  const AskUserInput();
}

enum AskUserChoiceKind { single, multi }

/// Options are suggestions. A single question with no options takes free text.
final class AskUserChoiceInput extends AskUserInput {
  AskUserChoiceInput(this.kind, {List<String> options = const []})
    : options = List.unmodifiable(options);

  final AskUserChoiceKind kind;
  final List<String> options;
}

/// A finite JSON number. Bounds are inclusive. A precision of zero requires
/// a whole number. Precision applies to the value, ignoring trailing zeros.
final class AskUserNumberInput extends AskUserInput {
  AskUserNumberInput({this.min, this.max, this.maxDecimalPlaces}) {
    if (min?.isFinite == false ||
        max?.isFinite == false ||
        (min != null && max != null && min! > max!) ||
        (maxDecimalPlaces != null && maxDecimalPlaces! < 0)) {
      throw ArgumentError('Invalid number constraints');
    }
  }

  final num? min;
  final num? max;
  final int? maxDecimalPlaces;
}

/// An ISO 8601 calendar date (YYYY-MM-DD) with inclusive date-only bounds.
final class AskUserDateInput extends AskUserInput {
  AskUserDateInput({this.min, this.max}) {
    if ((min != null && !_isCalendarDate(min!)) ||
        (max != null && !_isCalendarDate(max!)) ||
        (min != null && max != null && min!.compareTo(max!) > 0)) {
      throw ArgumentError('Invalid date constraints');
    }
  }

  final String? min;
  final String? max;
}

bool _isCalendarDate(String value) =>
    value.length == 10 &&
    DateTime.tryParse('${value}T00:00:00Z')?.toIso8601String() ==
        '${value}T00:00:00.000Z';

/// File metadata has a basename `name` and a non-negative integer `sizeBytes`.
/// Supply final extensions without dots. Matching is case-insensitive and an
/// empty set permits any extension.
final class AskUserFileInput extends AskUserInput {
  AskUserFileInput({
    this.maxSizeBytes,
    Set<String> allowedExtensions = const {},
  }) : allowedExtensions = Set.unmodifiable(
         allowedExtensions.map((extension) => extension.toLowerCase()),
       ) {
    if ((maxSizeBytes != null && maxSizeBytes! < 0) ||
        this.allowedExtensions.any(
          (ext) => ext.isEmpty || ext.contains(RegExp(r'[./\\\s\x00]')),
        )) {
      throw ArgumentError('Invalid file constraints');
    }
  }

  final int? maxSizeBytes;
  final Set<String> allowedExtensions;
}

/// Error codes are part of the contract and can be mapped to UI messages.
enum AskUserValidation {
  valid(null),
  invalidText('invalid_text'),
  invalidSelection('invalid_selection'),
  invalidNumber('invalid_number'),
  belowMinimum('below_minimum'),
  aboveMaximum('above_maximum'),
  tooManyDecimalPlaces('too_many_decimal_places'),
  invalidDate('invalid_date'),
  invalidFile('invalid_file'),
  fileTooLarge('file_too_large'),
  extensionNotAllowed('extension_not_allowed');

  const AskUserValidation(this.errorCode);
  final String? errorCode;
  bool get isValid => this == valid;
}

AskUserValidation validateAskUserAnswer(AskUserInput input, Object? value) {
  switch (input) {
    case AskUserChoiceInput(kind: AskUserChoiceKind.single):
      return _hasText(value)
          ? AskUserValidation.valid
          : AskUserValidation.invalidText;
    case AskUserChoiceInput(kind: AskUserChoiceKind.multi):
      return value is List &&
              value.isNotEmpty &&
              value.every(_hasText) &&
              value.toSet().length == value.length
          ? AskUserValidation.valid
          : AskUserValidation.invalidSelection;
    case AskUserNumberInput(:final min, :final max, :final maxDecimalPlaces):
      if (value is! num || !value.isFinite) {
        return AskUserValidation.invalidNumber;
      }
      if (min != null && value < min) return AskUserValidation.belowMinimum;
      if (max != null && value > max) return AskUserValidation.aboveMaximum;
      if (maxDecimalPlaces != null &&
          _decimalPlaces(value) > maxDecimalPlaces) {
        return AskUserValidation.tooManyDecimalPlaces;
      }
      return AskUserValidation.valid;
    case AskUserDateInput(:final min, :final max):
      if (value is! String || !_isCalendarDate(value)) {
        return AskUserValidation.invalidDate;
      }
      if (min != null && value.compareTo(min) < 0) {
        return AskUserValidation.belowMinimum;
      }
      if (max != null && value.compareTo(max) > 0) {
        return AskUserValidation.aboveMaximum;
      }
      return AskUserValidation.valid;
    case AskUserFileInput(:final maxSizeBytes, :final allowedExtensions):
      if (value case {'name': String name, 'sizeBytes': int size}) {
        if (!_hasText(name) ||
            name == '.' ||
            name == '..' ||
            name.contains(RegExp(r'[/\\\x00]')) ||
            size < 0) {
          return AskUserValidation.invalidFile;
        }
        if (maxSizeBytes != null && size > maxSizeBytes) {
          return AskUserValidation.fileTooLarge;
        }
        if (allowedExtensions.isNotEmpty) {
          final dot = name.lastIndexOf('.');
          if (dot <= 0 ||
              !allowedExtensions.contains(
                name.substring(dot + 1).toLowerCase(),
              )) {
            return AskUserValidation.extensionNotAllowed;
          }
        }
        return AskUserValidation.valid;
      }
      return AskUserValidation.invalidFile;
  }
}

bool _hasText(Object? value) => value is String && value.trim().isNotEmpty;

int _decimalPlaces(num value) {
  if (value is int) return 0;
  // The shortest decimal representation also covers scientific notation.
  final parts = value.toString().split('e');
  final fraction = parts.first.split('.').elementAtOrNull(1) ?? '';
  final digits = fraction.replaceFirst(RegExp(r'0+$'), '').length;
  final exponent = parts.length == 2 ? int.parse(parts.last) : 0;
  return math.max(0, digits - exponent);
}

enum AskUserRequestClass {
  form,
  approval;

  /// The host supplies both risk flags for the underlying operation.
  static AskUserRequestClass classify({
    required bool hasSideEffects,
    required bool isHighRisk,
    bool requestsApproval = false,
  }) => hasSideEffects || isHighRisk || requestsApproval ? approval : form;

  bool get requiresExplicitAnswer => this == approval;
  bool get canAutoSubmit => this == form;
  bool get canUseDefaultAnswer => this == form;
}

enum PendingApprovalState { pending, answered, expired }

/// Persisted identity and status. The caller supplies the request payload hash
/// and the expiry duration for its approvals. Answered includes a user denial.
final class PendingApprovalRecord {
  PendingApprovalRecord({
    required this.id,
    required DateTime createdAt,
    required this.requestPayloadHash,
    this.state = PendingApprovalState.pending,
  }) : createdAt = createdAt.toUtc() {
    if (id.trim().isEmpty || requestPayloadHash.trim().isEmpty) {
      throw ArgumentError('Approval ID and request payload hash are required');
    }
  }

  final String id;
  final DateTime createdAt;
  final String requestPayloadHash;
  final PendingApprovalState state;

  /// Returns an expired snapshot at or after the deadline, including on resume.
  PendingApprovalRecord expireIfDue({
    required DateTime now,
    required Duration ttl,
  }) {
    if (ttl.isNegative) throw ArgumentError.value(ttl, 'ttl');
    if (state != PendingApprovalState.pending ||
        now.difference(createdAt) < ttl) {
      return this;
    }
    return PendingApprovalRecord(
      id: id,
      createdAt: createdAt,
      requestPayloadHash: requestPayloadHash,
      state: PendingApprovalState.expired,
    );
  }

  Map<String, Object> toJson() => {
    'id': id,
    'createdAt': createdAt.toIso8601String(),
    'requestPayloadHash': requestPayloadHash,
    'state': state.name,
  };

  /// Reads the UTC timestamp format emitted by [toJson].
  factory PendingApprovalRecord.fromJson(Map<String, dynamic> json) {
    if (json case {
      'id': String id,
      'createdAt': String timestamp,
      'requestPayloadHash': String hash,
      'state': String stateName,
    }) {
      final state = PendingApprovalState.values.asNameMap()[stateName];
      final createdAt = DateTime.tryParse(timestamp);
      if (id.trim().isNotEmpty &&
          hash.trim().isNotEmpty &&
          state != null &&
          createdAt != null &&
          createdAt.isUtc &&
          createdAt.toIso8601String() == timestamp) {
        return PendingApprovalRecord(
          id: id,
          createdAt: createdAt,
          requestPayloadHash: hash,
          state: state,
        );
      }
    }
    throw const FormatException('Invalid pending approval record');
  }
}
