/// Cross-platform reminder data exchanged by storage and tool adapters.
library;

enum ReminderState { pending, completed, cancelled }

/// The last known outcome from the notification backend. A storage write alone
/// leaves a new reminder [unscheduled].
enum ReminderNotificationState { unscheduled, scheduled, delivered, failed }

enum ReminderPriority { none, low, medium, high }

enum ReminderFrequency { none, daily, weekly, monthly }

/// [code] is a stable wire value. [field] identifies the offending input.
final class ReminderContractException implements Exception {
  const ReminderContractException(this.code, this.field);

  final String code;
  final String field;

  @override
  String toString() => 'ReminderContractException($code, $field)';
}

final class ReminderRecurrence {
  const ReminderRecurrence.none()
    : frequency = ReminderFrequency.none,
      interval = 1;

  ReminderRecurrence(this.frequency, {this.interval = 1}) {
    if (interval < 1 ||
        (frequency == ReminderFrequency.none && interval != 1)) {
      throw const ReminderContractException('INVALID_INTERVAL', 'interval');
    }
  }

  final ReminderFrequency frequency;
  final int interval;

  factory ReminderRecurrence.fromJson(Map<String, Object?> json) {
    final interval = json['interval'];
    if (interval is! int) {
      throw const ReminderContractException('INVALID_INTERVAL', 'interval');
    }
    return ReminderRecurrence(
      _readEnum(ReminderFrequency.values, json['frequency'], 'frequency'),
      interval: interval,
    );
  }

  Map<String, Object?> toJson() => {
    'frequency': frequency.name,
    'interval': interval,
  };

  /// First occurrence strictly after [after], including [firstDueAt] if future.
  /// Intervals use the UTC calendar. Monthly occurrences keep the anchor day
  /// and clamp to the last day of shorter months. Returns null at series end.
  DateTime? nextOccurrence(DateTime firstDueAt, {required DateTime after}) {
    final anchor = _instant(firstDueAt, 'due_at');
    final cursor = after.toUtc();
    if (anchor.isAfter(cursor)) return anchor;
    if (frequency == ReminderFrequency.none ||
        cursor.year > _lastInstant.year) {
      return null;
    }

    if (frequency == ReminderFrequency.monthly) {
      final elapsed =
          (cursor.year - anchor.year) * 12 + cursor.month - anchor.month;
      final months = elapsed - elapsed % interval;
      final candidate = _monthAt(anchor, months);
      if (candidate.isAfter(cursor)) return candidate;
      final remaining =
          (_lastInstant.year - anchor.year) * 12 + 12 - anchor.month - months;
      return interval > remaining ? null : _monthAt(anchor, months + interval);
    }

    final daysPerUnit = frequency == ReminderFrequency.weekly ? 7 : 1;
    final elapsedDays = cursor.difference(anchor).inDays;
    final elapsedUnits = elapsedDays ~/ daysPerUnit;
    final lastUnit = elapsedUnits - elapsedUnits % interval;
    final availableUnits =
        _lastInstant.difference(anchor).inDays ~/ daysPerUnit;
    if (interval > availableUnits - lastUnit) return null;
    return anchor.add(Duration(days: (lastUnit + interval) * daysPerUnit));
  }

  static DateTime _monthAt(DateTime anchor, int months) {
    final month = anchor.month + months;
    final lastDay = DateTime.utc(anchor.year, month + 1, 0).day;
    return DateTime.utc(
      anchor.year,
      month,
      anchor.day.clamp(1, lastDay),
      anchor.hour,
      anchor.minute,
      anchor.second,
      anchor.millisecond,
      anchor.microsecond,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ReminderRecurrence &&
      frequency == other.frequency &&
      interval == other.interval;

  @override
  int get hashCode => Object.hash(frequency, interval);
}

/// The complete set of user-editable fields shared by create and update.
/// An undated inbox reminder has a null due time and a one-time rule.
final class ReminderDetails {
  ReminderDetails({
    required String title,
    DateTime? dueAt,
    this.priority = ReminderPriority.none,
    this.recurrence = const ReminderRecurrence.none(),
  }) : title = title.trim(),
       dueAt = dueAt == null ? null : _instant(dueAt, 'due_at') {
    if (this.title.isEmpty) {
      throw const ReminderContractException('INVALID_TITLE', 'title');
    }
    if (dueAt == null && recurrence.frequency != ReminderFrequency.none) {
      throw const ReminderContractException(
        'DUE_REQUIRED_FOR_RECURRENCE',
        'due_at',
      );
    }
  }

  final String title;
  final DateTime? dueAt;
  final ReminderPriority priority;
  final ReminderRecurrence recurrence;

  factory ReminderDetails.fromJson(Map<String, Object?> json) {
    final title = json['title'];
    if (title is! String) {
      throw const ReminderContractException('INVALID_TITLE', 'title');
    }
    return ReminderDetails(
      title: title,
      dueAt: json['due_at'] == null
          ? null
          : _readInstant(json['due_at'], 'due_at'),
      priority: _readEnum(
        ReminderPriority.values,
        json['priority'],
        'priority',
      ),
      recurrence: ReminderRecurrence.fromJson(
        _readObject(json['recurrence'], 'recurrence'),
      ),
    );
  }

  Map<String, Object?> toJson() => {
    'title': title,
    'due_at': dueAt?.toIso8601String(),
    'priority': priority.name,
    'recurrence': recurrence.toJson(),
  };
}

/// A stored reminder. Storage assigns the opaque ID once at creation.
/// Both lifecycle and notification state are serialized explicitly.
/// Readers ignore additional fields, including inside the recurrence object.
/// Wire timestamps use ISO 8601 with an explicit offset or Z, four-digit years
/// (0001–9999 in UTC), and at most six fractional second digits. Writes use UTC.
final class ReminderRecord {
  ReminderRecord({
    required this.reminderId,
    required this.details,
    required DateTime createdAt,
    required DateTime updatedAt,
    this.state = ReminderState.pending,
    this.notificationState = ReminderNotificationState.unscheduled,
  }) : createdAt = _instant(createdAt, 'created_at'),
       updatedAt = _instant(updatedAt, 'updated_at') {
    _readId(reminderId);
    if (this.updatedAt.isBefore(this.createdAt)) {
      throw const ReminderContractException(
        'UPDATED_BEFORE_CREATED',
        'updated_at',
      );
    }
  }

  final String reminderId;
  final ReminderDetails details;
  final ReminderState state;
  final ReminderNotificationState notificationState;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory ReminderRecord.fromJson(Map<String, Object?> json) => ReminderRecord(
    reminderId: _readId(json['reminder_id']),
    details: ReminderDetails.fromJson(json),
    state: _readEnum(ReminderState.values, json['state'], 'state'),
    notificationState: _readEnum(
      ReminderNotificationState.values,
      json['notification_state'],
      'notification_state',
    ),
    createdAt: _readInstant(json['created_at'], 'created_at'),
    updatedAt: _readInstant(json['updated_at'], 'updated_at'),
  );

  Map<String, Object?> toJson() => {
    'reminder_id': reminderId,
    ...details.toJson(),
    'state': state.name,
    'notification_state': notificationState.name,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
  };

  /// Detects repeated creations within an inclusive [window]. The key is the
  /// trimmed, case-insensitive title, exact due instant (both may be undated),
  /// and recurrence. Identity, priority and notification outcome are immaterial.
  bool isDuplicateOf(ReminderRecord other, {required Duration window}) {
    if (window.isNegative) {
      throw const ReminderContractException('INVALID_WINDOW', 'window');
    }
    return createdAt.difference(other.createdAt).abs() <= window &&
        details.title.toLowerCase() == other.details.title.toLowerCase() &&
        details.dueAt == other.details.dueAt &&
        details.recurrence == other.details.recurrence;
  }
}

/// Create returns the newly allocated record. List returns stored records, get
/// returns one by ID, and update replaces only the editable details. Complete
/// marks the record completed and delete cancels it. Both target the same ID.
enum ReminderOperation {
  create(
    requiresConfirmation: true,
    mayScheduleNotification: true,
    targetState: ReminderState.pending,
  ),
  list,
  get,
  update(requiresConfirmation: true, mayScheduleNotification: true),
  complete(targetState: ReminderState.completed),
  delete(requiresConfirmation: true, targetState: ReminderState.cancelled);

  const ReminderOperation({
    this.requiresConfirmation = false,
    this.mayScheduleNotification = false,
    this.targetState,
  });

  final bool requiresConfirmation;

  /// A backend may schedule after an approved create or update. Completing a
  /// recurring reminder must never schedule its next occurrence.
  final bool mayScheduleNotification;

  /// A null target preserves the stored lifecycle state.
  final ReminderState? targetState;
}

/// Requests carry an operation, a reminder_id for existing items, and nested
/// details for create/update. Confirmation comes from the caller's approval flow.
final class ReminderRequest {
  ReminderRequest(this.operation, {this.reminderId, this.details}) {
    final needsId =
        operation != ReminderOperation.create &&
        operation != ReminderOperation.list;
    if (needsId) {
      _readId(reminderId);
    } else if (reminderId != null) {
      throw const ReminderContractException('UNEXPECTED_FIELD', 'reminder_id');
    }
    final needsDetails =
        operation == ReminderOperation.create ||
        operation == ReminderOperation.update;
    if (needsDetails != (details != null)) {
      throw ReminderContractException(
        needsDetails ? 'MISSING_FIELD' : 'UNEXPECTED_FIELD',
        'details',
      );
    }
  }

  final ReminderOperation operation;
  final String? reminderId;
  final ReminderDetails? details;

  factory ReminderRequest.fromJson(Map<String, Object?> json) =>
      ReminderRequest(
        _readEnum(ReminderOperation.values, json['operation'], 'operation'),
        reminderId: json.containsKey('reminder_id')
            ? _readId(json['reminder_id'])
            : null,
        details: json.containsKey('details')
            ? ReminderDetails.fromJson(_readObject(json['details'], 'details'))
            : null,
      );

  Map<String, Object?> toJson() => {
    'operation': operation.name,
    if (reminderId != null) 'reminder_id': reminderId,
    if (details != null) 'details': details!.toJson(),
  };

  void validateConfirmation({required bool confirmed}) {
    if (operation.requiresConfirmation && !confirmed) {
      throw const ReminderContractException(
        'CONFIRMATION_REQUIRED',
        'operation',
      );
    }
  }
}

String _readId(Object? value) {
  if (value is! String || value.trim().isEmpty || value.trim() != value) {
    throw const ReminderContractException('INVALID_REMINDER_ID', 'reminder_id');
  }
  return value;
}

Map<String, Object?> _readObject(Object? value, String field) {
  if (value is Map<String, Object?>) return value;
  throw ReminderContractException('INVALID_OBJECT', field);
}

T _readEnum<T extends Enum>(List<T> values, Object? value, String field) {
  for (final entry in values) {
    if (entry.name == value) return entry;
  }
  throw ReminderContractException('INVALID_ENUM', field);
}

// Four-digit ISO years and microsecond precision round-trip across the wire.
final _lastInstant = DateTime.utc(9999, 12, 31, 23, 59, 59, 999, 999);
final _timestamp = RegExp(
  r'^(\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d)(?:\.\d{1,6})?(?:Z|[+-](?:[01]\d|2[0-3]):[0-5]\d)$',
);

DateTime _instant(DateTime value, String field) {
  final utc = value.toUtc();
  if (utc.year < 1 || utc.year > _lastInstant.year) {
    throw ReminderContractException('INVALID_TIMESTAMP', field);
  }
  return utc;
}

DateTime _readInstant(Object? value, String field) {
  if (value is String) {
    final wallTime = _timestamp.firstMatch(value)?.group(1);
    if (wallTime != null) {
      // DateTime.parse normalizes out-of-range components, e.g. February 30.
      final calendarTime = DateTime.tryParse('${wallTime}Z');
      if (calendarTime != null &&
          calendarTime.toIso8601String().startsWith('$wallTime.')) {
        return _instant(DateTime.parse(value), field);
      }
    }
  }
  throw ReminderContractException('INVALID_TIMESTAMP', field);
}
