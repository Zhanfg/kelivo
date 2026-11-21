import 'dart:convert';

import 'package:Kelivo/core/services/tools/reminder_contract.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> _wireRecord() => {
  'reminder_id': 'inbox/r-17',
  'title': 'Pay rent',
  'due_at': '2028-01-31T09:30:00.123456Z',
  'priority': 'high',
  'recurrence': {'frequency': 'monthly', 'interval': 2},
  'state': 'pending',
  'notification_state': 'failed',
  'created_at': '2028-01-01T00:00:00.000Z',
  'updated_at': '2028-01-02T11:00:00.000Z',
};

void _expectError(String code, String field, void Function() action) {
  try {
    action();
  } on ReminderContractException catch (error) {
    expect(error.code, code);
    expect(error.field, field);
    return;
  }
  fail('Expected $code for $field');
}

void main() {
  test('record decodes the wire fields and round-trips through JSON', () {
    final wire = _wireRecord();
    final record = ReminderRecord.fromJson(jsonDecode(jsonEncode(wire)));
    expect(record.reminderId, 'inbox/r-17');
    expect(record.details.title, 'Pay rent');
    expect(record.details.dueAt, DateTime.utc(2028, 1, 31, 9, 30, 0, 123, 456));
    expect(record.details.priority, ReminderPriority.high);
    expect(record.details.recurrence.frequency, ReminderFrequency.monthly);
    expect(record.details.recurrence.interval, 2);
    expect(record.state, ReminderState.pending);
    expect(record.notificationState, ReminderNotificationState.failed);
    expect(record.createdAt, DateTime.utc(2028));
    expect(record.updatedAt, DateTime.utc(2028, 1, 2, 11));
    expect(record.toJson(), wire);
  });

  test('unknown record and recurrence fields do not affect known data', () {
    final record = ReminderRecord.fromJson({
      ..._wireRecord(),
      'future_provider': ['new value'],
      'recurrence': {'frequency': 'monthly', 'interval': 2, 'future_option': 3},
    });
    expect(record.toJson(), _wireRecord());
  });

  test('input offsets canonicalize to the same UTC instant', () {
    final record = ReminderRecord.fromJson({
      ..._wireRecord(),
      'due_at': '2028-01-31T10:30:00.123456+01:00',
      'created_at': '2027-12-31T19:00:00-05:00',
    });
    expect(record.toJson(), _wireRecord());
  });

  test('a new undated inbox item is stored pending and unscheduled', () {
    final record = ReminderRecord(
      reminderId: 'inbox/r-18',
      details: ReminderDetails(title: '  Get milk  '),
      createdAt: DateTime.utc(2028),
      updatedAt: DateTime.utc(2028),
    );
    final saved = ReminderRecord.fromJson(record.toJson());
    expect(saved.details.title, 'Get milk');
    expect(saved.details.dueAt, null);
    expect(saved.details.priority, ReminderPriority.none);
    expect(saved.details.recurrence, const ReminderRecurrence.none());
    expect(saved.state, ReminderState.pending);
    expect(saved.notificationState, ReminderNotificationState.unscheduled);
  });

  for (final state in ReminderState.values) {
    test(
      'a ${state.name} record retains each independent delivery outcome',
      () {
        for (final delivery in ReminderNotificationState.values) {
          final saved = ReminderRecord.fromJson({
            ..._wireRecord(),
            'state': state.name,
            'notification_state': delivery.name,
          });
          expect(saved.state, state);
          expect(saved.notificationState, delivery);
          expect(saved.toJson()['state'], state.name);
          expect(saved.toJson()['notification_state'], delivery.name);
        }
      },
    );
  }

  const invalidFields = <(String, Object?, String)>[
    ('reminder_id', ' ', 'INVALID_REMINDER_ID'),
    ('reminder_id', 17, 'INVALID_REMINDER_ID'),
    ('title', ' \t', 'INVALID_TITLE'),
    ('title', null, 'INVALID_TITLE'),
    ('priority', 'urgent', 'INVALID_ENUM'),
    ('state', 'scheduled', 'INVALID_ENUM'),
    ('notification_state', 'completed', 'INVALID_ENUM'),
    ('recurrence', [], 'INVALID_OBJECT'),
    ('due_at', 123, 'INVALID_TIMESTAMP'),
    ('due_at', '2028-02-30T12:00:00Z', 'INVALID_TIMESTAMP'),
    ('due_at', '2028-02-01T12:00:00', 'INVALID_TIMESTAMP'),
    ('due_at', '2028-02-01T12:00:00+01:75', 'INVALID_TIMESTAMP'),
    ('created_at', null, 'INVALID_TIMESTAMP'),
    ('updated_at', 'yesterday', 'INVALID_TIMESTAMP'),
    ('updated_at', '2027-12-31T23:59:59Z', 'UPDATED_BEFORE_CREATED'),
    ('due_at', null, 'DUE_REQUIRED_FOR_RECURRENCE'),
  ];
  for (final (field, value, code) in invalidFields) {
    test('record reports $code for $field = $value', () {
      _expectError(code, field, () {
        ReminderRecord.fromJson({..._wireRecord(), field: value});
      });
    });
  }

  test('required record keys cannot be omitted', () {
    for (final (field, code) in [
      ('reminder_id', 'INVALID_REMINDER_ID'),
      ('state', 'INVALID_ENUM'),
      ('notification_state', 'INVALID_ENUM'),
      ('created_at', 'INVALID_TIMESTAMP'),
    ]) {
      _expectError(code, field, () {
        ReminderRecord.fromJson(_wireRecord()..remove(field));
      });
    }
  });

  test('unknown frequency and invalid intervals have stable errors', () {
    _expectError('INVALID_ENUM', 'frequency', () {
      ReminderRecurrence.fromJson({'frequency': 'hourly', 'interval': 1});
    });
    for (final invalid in [0, -1, 1.5, '2', null]) {
      _expectError('INVALID_INTERVAL', 'interval', () {
        ReminderRecurrence.fromJson({
          'frequency': 'weekly',
          'interval': invalid,
        });
      });
    }
    _expectError('INVALID_INTERVAL', 'interval', () {
      ReminderRecurrence(ReminderFrequency.none, interval: 2);
    });
  });

  test('typed construction validates identity, title, and timestamps', () {
    _expectError('INVALID_TITLE', 'title', () => ReminderDetails(title: '\n'));
    _expectError('INVALID_REMINDER_ID', 'reminder_id', () {
      ReminderRecord(
        reminderId: ' inbox/r-17',
        details: ReminderDetails(title: 'Pay rent'),
        createdAt: DateTime.utc(2028),
        updatedAt: DateTime.utc(2028),
      );
    });
    _expectError('INVALID_TIMESTAMP', 'due_at', () {
      ReminderDetails(title: 'Pay rent', dueAt: DateTime.utc(10000));
    });
  });

  final original = ReminderRecord.fromJson(_wireRecord());
  final details = original.details.toJson();
  final id = original.reminderId;
  final requests = <Map<String, Object?>>[
    {'operation': 'create', 'details': details},
    {'operation': 'list'},
    {'operation': 'get', 'reminder_id': id},
    {'operation': 'update', 'reminder_id': id, 'details': details},
    {'operation': 'complete', 'reminder_id': id},
    {'operation': 'delete', 'reminder_id': id},
  ];
  for (final wire in requests) {
    test(
      '${wire['operation']} round-trips its request and checks approval',
      () {
        final request = ReminderRequest.fromJson(wire);
        expect(request.toJson(), wire);
        final requiresApproval = {
          'create',
          'update',
          'delete',
        }.contains(wire['operation']);
        expect(request.operation.requiresConfirmation, requiresApproval);
        if (requiresApproval) {
          _expectError('CONFIRMATION_REQUIRED', 'operation', () {
            request.validateConfirmation(confirmed: false);
          });
        } else {
          request.validateConfirmation(confirmed: false);
        }
        request.validateConfirmation(confirmed: true);
        expect(
          request.operation.mayScheduleNotification,
          {'create', 'update'}.contains(wire['operation']),
        );
      },
    );
  }

  test('operation payloads enforce ID and editable field requirements', () {
    for (final op in ['create', 'update']) {
      _expectError('MISSING_FIELD', 'details', () {
        ReminderRequest.fromJson({
          'operation': op,
          if (op == 'update') 'reminder_id': id,
        });
      });
    }
    for (final op in ['get', 'update', 'complete', 'delete']) {
      _expectError('INVALID_REMINDER_ID', 'reminder_id', () {
        ReminderRequest.fromJson({
          'operation': op,
          if (op == 'update') 'details': details,
        });
      });
    }
    for (final op in ['create', 'list']) {
      _expectError('UNEXPECTED_FIELD', 'reminder_id', () {
        ReminderRequest.fromJson({
          'operation': op,
          'reminder_id': id,
          if (op == 'create') 'details': details,
        });
      });
    }
    for (final op in ['list', 'get', 'complete', 'delete']) {
      _expectError('UNEXPECTED_FIELD', 'details', () {
        ReminderRequest.fromJson({
          'operation': op,
          if (op != 'list') 'reminder_id': id,
          'details': details,
        });
      });
    }
    _expectError('INVALID_ENUM', 'operation', () {
      ReminderRequest.fromJson({'operation': 'reschedule'});
    });
    _expectError('INVALID_OBJECT', 'details', () {
      ReminderRequest.fromJson({'operation': 'create', 'details': false});
    });
  });

  test('lifecycle targets are independent of notification outcomes', () {
    expect(ReminderOperation.create.targetState, ReminderState.pending);
    expect(ReminderOperation.complete.targetState, ReminderState.completed);
    expect(ReminderOperation.delete.targetState, ReminderState.cancelled);
    for (final op in [
      ReminderOperation.list,
      ReminderOperation.get,
      ReminderOperation.update,
    ]) {
      expect(op.targetState, null);
    }
  });

  test('wire data cannot grant approval or replace storage-owned fields', () {
    final edit = ReminderRequest.fromJson({
      'operation': 'update',
      'reminder_id': id,
      'confirmed': true,
      'details': {...details, 'reminder_id': 'other', 'state': 'completed'},
    });
    _expectError('CONFIRMATION_REQUIRED', 'operation', () {
      edit.validateConfirmation(confirmed: false);
    });
    expect(edit.reminderId, id);
    expect(edit.details!.toJson(), details);
  });

  const window = Duration(minutes: 5);
  ReminderRecord variant(Map<String, Object?> changes) =>
      ReminderRecord.fromJson({
        ..._wireRecord(),
        'reminder_id': 'second',
        ...changes,
      });

  test('duplicate retries include the window boundary in either order', () {
    final retry = variant({
      'title': '  PAY rent ',
      'due_at': '2028-01-31T08:30:00.123456-01:00',
      'priority': 'low',
      'notification_state': 'unscheduled',
      'created_at': '2028-01-01T00:05:00Z',
    });
    expect(original.isDuplicateOf(retry, window: window), true);
    expect(retry.isDuplicateOf(original, window: window), true);
    expect(original.isDuplicateOf(variant({}), window: Duration.zero), true);
  });

  test('changing any duplicate key or exceeding the window is distinct', () {
    for (final changes in [
      {'title': 'Pay insurance'},
      {'due_at': '2028-01-31T09:30:00.123457Z'},
      {
        'recurrence': {'frequency': 'weekly', 'interval': 2},
      },
      {
        'recurrence': {'frequency': 'monthly', 'interval': 1},
      },
      {'created_at': '2028-01-01T00:05:00.000001Z'},
    ]) {
      expect(
        original.isDuplicateOf(variant(changes), window: window),
        false,
        reason: '$changes',
      );
    }
  });

  test('undated duplicates require two undated reminders', () {
    const once = {'frequency': 'none', 'interval': 1};
    final inbox = variant({'due_at': null, 'recurrence': once});
    final other = variant({
      'reminder_id': 'third',
      'due_at': null,
      'recurrence': once,
    });
    expect(inbox.isDuplicateOf(other, window: window), true);
    expect(
      inbox.isDuplicateOf(variant({'recurrence': once}), window: window),
      false,
    );
  });

  test('a negative duplicate window has a stable error', () {
    _expectError('INVALID_WINDOW', 'window', () {
      original.isDuplicateOf(
        original,
        window: const Duration(microseconds: -1),
      );
    });
  });

  final anchor = original.details.dueAt!;
  test('a one-time rule has at most its original occurrence', () {
    const once = ReminderRecurrence.none();
    expect(once.nextOccurrence(anchor, after: DateTime.utc(2027)), anchor);
    expect(once.nextOccurrence(anchor, after: anchor), null);
    expect(once.nextOccurrence(anchor, after: DateTime.utc(2029)), null);
  });

  test('daily intervals preserve UTC time and skip elapsed occurrences', () {
    final everyThreeDays = ReminderRecurrence(
      ReminderFrequency.daily,
      interval: 3,
    );
    expect(
      everyThreeDays.nextOccurrence(anchor, after: anchor),
      anchor.add(const Duration(days: 3)),
    );
    expect(
      everyThreeDays.nextOccurrence(
        anchor,
        after: anchor.add(const Duration(days: 11, hours: 23)),
      ),
      anchor.add(const Duration(days: 12)),
    );
  });

  test('weekly intervals keep the weekday across year boundaries', () {
    final friday = DateTime.utc(2027, 12, 31, 9);
    final fortnightly = ReminderRecurrence(
      ReminderFrequency.weekly,
      interval: 2,
    );
    expect(
      fortnightly.nextOccurrence(friday, after: friday),
      DateTime.utc(2028, 1, 14, 9),
    );
    expect(
      fortnightly.nextOccurrence(friday, after: DateTime.utc(2028, 1, 14, 9)),
      DateTime.utc(2028, 1, 28, 9),
    );
  });

  test('monthly clamping returns to the anchor day after leap February', () {
    final monthly = ReminderRecurrence(ReminderFrequency.monthly);
    final feb = DateTime.utc(2028, 2, 29, 9, 30, 0, 123, 456);
    final march = DateTime.utc(2028, 3, 31, 9, 30, 0, 123, 456);
    expect(monthly.nextOccurrence(anchor, after: anchor), feb);
    expect(
      monthly.nextOccurrence(
        anchor,
        after: feb.subtract(const Duration(microseconds: 1)),
      ),
      feb,
    );
    expect(monthly.nextOccurrence(anchor, after: feb), march);
  });

  test('monthly intervals cross years and clamp in ordinary February', () {
    final december = DateTime.utc(2028, 12, 31, 16);
    final rule = ReminderRecurrence(ReminderFrequency.monthly, interval: 2);
    expect(
      rule.nextOccurrence(december, after: DateTime.utc(2029, 1, 31)),
      DateTime.utc(2029, 2, 28, 16),
    );
    expect(
      rule.nextOccurrence(december, after: DateTime.utc(2029, 4, 30, 16)),
      DateTime.utc(2029, 6, 30, 16),
    );
  });

  test(
    'expansion ends when the next occurrence exceeds the wire date range',
    () {
      final last = DateTime.utc(9999, 12, 31);
      for (final frequency in ReminderFrequency.values) {
        expect(
          ReminderRecurrence(frequency).nextOccurrence(last, after: last),
          null,
        );
      }
      for (final frequency in [
        ReminderFrequency.daily,
        ReminderFrequency.weekly,
        ReminderFrequency.monthly,
      ]) {
        final rule = ReminderRecurrence(frequency, interval: 1 << 52);
        expect(rule.nextOccurrence(anchor, after: anchor), null);
      }
    },
  );
}
