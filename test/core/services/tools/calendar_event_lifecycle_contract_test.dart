import 'package:Kelivo/core/services/tools/calendar_event_lifecycle_contract.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const policy = CalendarEventLifecycleContract();
  final begin = DateTime.utc(2026, 11, 1, 6);
  final end = DateTime.utc(2026, 11, 1, 7);

  CalendarEventMutation mutation({
    CalendarOperation operation = CalendarOperation.update,
    String zone = 'America/New_York',
    bool confirmed = true,
    String? revision = 'etag-123',
    CalendarRecurrenceScope? scope = CalendarRecurrenceScope.entireSeries,
    DateTime? occurrence,
    DateTime? start,
    DateTime? finish,
  }) => CalendarEventMutation(
    operation: operation,
    eventId: 'cal/event-123',
    calendarId: 'calendar-primary',
    timeZone: zone,
    utcStart: start ?? begin,
    utcEnd: finish ?? end,
    confirmed: confirmed,
    expectedRevision: revision,
    recurrenceScope: scope,
    occurrenceStartUtc: occurrence,
  );

  test('confirmed versioned update with explicit series scope passes', () {
    expect(
      policy
          .validate(
            mutation(),
            platform: CalendarPlatform.android,
            calendarPermission: true,
          )
          .allowed,
      isTrue,
    );
  });

  test('cancel without confirmation or revision is denied', () {
    final result = policy.validate(
      mutation(
        operation: CalendarOperation.cancel,
        confirmed: false,
        revision: null,
        scope: null,
      ),
      platform: CalendarPlatform.ios,
      calendarPermission: true,
    );
    expect(result.allowed, isFalse);
    expect(result.reasons, contains('explicit mutation confirmation required'));
    expect(result.reasons, contains('optimistic revision required'));
    expect(result.reasons, contains('recurrence scope must be explicit'));
  });

  test('DST overlap requires UTC occurrence identity and IANA zone', () {
    final result = policy.validate(
      mutation(
        scope: CalendarRecurrenceScope.singleOccurrence,
        zone: 'UTC-04:00',
      ),
      platform: CalendarPlatform.android,
      calendarPermission: true,
    );
    expect(result.allowed, isFalse);
    expect(result.reasons, contains('UTC occurrence identity required'));
    expect(result.reasons.join(' '), contains('IANA time zone'));
    final accepted = policy.validate(
      mutation(
        scope: CalendarRecurrenceScope.singleOccurrence,
        occurrence: begin,
      ),
      platform: CalendarPlatform.android,
      calendarPermission: true,
    );
    expect(accepted.allowed, isTrue);
  });

  test('non-UTC intervals and missing permission are denied', () {
    final result = policy.validate(
      mutation(start: DateTime(2026, 11, 1, 1)),
      platform: CalendarPlatform.android,
      calendarPermission: false,
    );
    expect(result.allowed, isFalse);
    expect(result.reasons, contains('calendar permission required'));
    expect(result.reasons, contains('unambiguous UTC interval required'));
  });

  test('other platforms advertise no unimplemented calendar support', () {
    expect(
      CalendarEventLifecycleContract.supportedPlatforms[CalendarPlatform.other],
      isEmpty,
    );
    expect(
      policy
          .validate(
            mutation(operation: CalendarOperation.detail),
            platform: CalendarPlatform.other,
            calendarPermission: true,
          )
          .allowed,
      isFalse,
    );
  });
}
