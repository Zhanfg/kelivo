/// A validation-only calendar lifecycle contract. No provider mutation occurs.
enum CalendarOperation { detail, update, cancel, freeBusy }

enum CalendarRecurrenceScope { singleOccurrence, entireSeries }

enum CalendarPlatform { android, ios, other }

class CalendarEventMutation {
  const CalendarEventMutation({
    required this.operation,
    required this.eventId,
    required this.calendarId,
    required this.timeZone,
    required this.utcStart,
    required this.utcEnd,
    this.expectedRevision,
    this.confirmed = false,
    this.recurrenceScope,
    this.occurrenceStartUtc,
  });

  final CalendarOperation operation;
  final String eventId;
  final String calendarId;
  final String timeZone;
  final DateTime utcStart;
  final DateTime utcEnd;
  final String? expectedRevision;
  final bool confirmed;
  final CalendarRecurrenceScope? recurrenceScope;
  final DateTime? occurrenceStartUtc;
}

class CalendarAdmission {
  const CalendarAdmission(this.allowed, this.reasons);

  final bool allowed;
  final List<String> reasons;
}

class CalendarEventLifecycleContract {
  const CalendarEventLifecycleContract();

  static const supportedPlatforms = <CalendarPlatform, Set<CalendarOperation>>{
    CalendarPlatform.android: {
      CalendarOperation.detail,
      CalendarOperation.update,
      CalendarOperation.cancel,
      CalendarOperation.freeBusy,
    },
    CalendarPlatform.ios: {
      CalendarOperation.detail,
      CalendarOperation.update,
      CalendarOperation.cancel,
      CalendarOperation.freeBusy,
    },
    CalendarPlatform.other: {},
  };

  CalendarAdmission validate(
    CalendarEventMutation request, {
    required CalendarPlatform platform,
    required bool calendarPermission,
  }) {
    final reasons = <String>[];
    if (!calendarPermission) reasons.add('calendar permission required');
    if (!supportedPlatforms[platform]!.contains(request.operation)) {
      reasons.add('unsupported platform operation');
    }
    if (request.calendarId.trim().isEmpty ||
        (request.operation != CalendarOperation.freeBusy &&
            request.eventId.trim().isEmpty)) {
      reasons.add('stable calendar and event identifiers required');
    }
    if (request.timeZone.trim().isEmpty ||
        !request.timeZone.contains('/') ||
        request.timeZone.contains('..')) {
      reasons.add('IANA time zone required; UTC offset alone is insufficient');
    }
    if (!request.utcStart.isUtc ||
        !request.utcEnd.isUtc ||
        !request.utcEnd.isAfter(request.utcStart)) {
      reasons.add('unambiguous UTC interval required');
    }
    final mutation =
        request.operation == CalendarOperation.update ||
        request.operation == CalendarOperation.cancel;
    if (mutation) {
      if (!request.confirmed) {
        reasons.add('explicit mutation confirmation required');
      }
      if (request.expectedRevision == null ||
          request.expectedRevision!.trim().isEmpty) {
        reasons.add('optimistic revision required');
      }
      if (request.recurrenceScope == null) {
        reasons.add('recurrence scope must be explicit');
      }
      if (request.recurrenceScope == CalendarRecurrenceScope.singleOccurrence &&
          (request.occurrenceStartUtc == null ||
              !request.occurrenceStartUtc!.isUtc)) {
        reasons.add('UTC occurrence identity required');
      }
    }
    return CalendarAdmission(reasons.isEmpty, List.unmodifiable(reasons));
  }
}
