import 'dart:convert';

import 'package:Kelivo/core/services/tools/ask_user_input_contract.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  void check(AskUserInput input, Object? value, [String? errorCode]) {
    final result = validateAskUserAnswer(input, value);
    expect(result.errorCode, errorCode, reason: 'answer = $value');
    expect(result.isValid, errorCode == null, reason: 'answer = $value');
  }

  test('single choice accepts a suggestion or custom text', () {
    final input = AskUserChoiceInput(AskUserChoiceKind.single, options: ['A']);
    check(input, 'A');
    check(input, 'Other answer');
    check(AskUserChoiceInput(AskUserChoiceKind.single), 'Free text');
    for (final value in [
      null,
      '',
      '  ',
      1,
      ['A'],
    ]) {
      check(input, value, 'invalid_text');
    }
  });

  test('multi choice requires a nonempty list of distinct text answers', () {
    final input = AskUserChoiceInput(
      AskUserChoiceKind.multi,
      options: ['A', 'B'],
    );
    check(input, ['A']);
    check(input, ['B', 'A', 'Other answer']);
    for (final value in [
      null,
      'A',
      [],
      [' '],
      ['A', 2],
      ['A', 'A'],
    ]) {
      check(input, value, 'invalid_selection');
    }
  });

  test('numbers include signed endpoints and reject out-of-range values', () {
    final input = AskUserNumberInput(min: -2.5, max: 1.5, maxDecimalPlaces: 1);
    for (final number in [-2.5, -0.1, 0, 1.5]) {
      check(input, number);
    }
    check(input, -2.6, 'below_minimum');
    check(input, 1.6, 'above_maximum');
  });

  test('number bounds can be absent, one-sided, or equal', () {
    check(AskUserNumberInput(), 0.12345);
    check(AskUserNumberInput(min: 1), 1e30);
    check(AskUserNumberInput(max: -1), -1e30);
    check(AskUserNumberInput(min: 0, max: 0), 0);
  });

  test('numeric answers must be finite JSON numbers', () {
    final input = AskUserNumberInput();
    for (final value in [
      null,
      true,
      '',
      '2.50',
      double.nan,
      double.infinity,
      double.negativeInfinity,
    ]) {
      check(input, value, 'invalid_number');
    }
  });

  test('decimal limits use the value including exponent notation', () {
    final cents = AskUserNumberInput(maxDecimalPlaces: 2);
    check(cents, 1.20);
    check(cents, 0.29);
    check(cents, -0.001, 'too_many_decimal_places');
    final small = AskUserNumberInput(maxDecimalPlaces: 8);
    check(small, 1e-8);
    check(small, -1.2e-7);
    check(small, 1.2e-8, 'too_many_decimal_places');
  });

  test('zero decimal places admits whole numbers', () {
    final input = AskUserNumberInput(maxDecimalPlaces: 0);
    for (final number in [0, -0.0, 3.0, -12, 1.5e24]) {
      check(input, number);
    }
    check(input, 0.5, 'too_many_decimal_places');
  });

  test(
    'invalid precision, reversed or nonfinite number bounds are rejected',
    () {
      expect(
        () => AskUserNumberInput(maxDecimalPlaces: -1),
        throwsArgumentError,
      );
      expect(() => AskUserNumberInput(min: 1, max: 0), throwsArgumentError);
      expect(
        () => AskUserNumberInput(min: double.negativeInfinity),
        throwsArgumentError,
      );
      expect(() => AskUserNumberInput(max: double.nan), throwsArgumentError);
    },
  );

  test('calendar dates include both range endpoints and leap day', () {
    final input = AskUserDateInput(min: '2024-02-28', max: '2024-03-01');
    for (final date in ['2024-02-28', '2024-02-29', '2024-03-01']) {
      check(input, date);
    }
    check(input, '2024-02-27', 'below_minimum');
    check(input, '2024-03-02', 'above_maximum');
  });

  test('date bounds can be absent, one-sided, or equal', () {
    check(AskUserDateInput(), '2000-02-29');
    check(AskUserDateInput(min: '1900-01-01'), '2099-01-01');
    check(AskUserDateInput(max: '2099-01-01'), '1900-01-01');
    check(AskUserDateInput(min: '2000-01-01', max: '2000-01-01'), '2000-01-01');
  });

  test('date answers reject rollover, ambiguous forms, and timestamps', () {
    final input = AskUserDateInput();
    for (final value in [
      null,
      20241231,
      '1900-02-29',
      '2024-02-30',
      '2024-00-01',
      '2024-13-01',
      '2024-01-00',
      '2024-2-29',
      '02/29/2024',
      '20240229',
      '2024-02-29T00:00:00Z',
    ]) {
      check(input, value, 'invalid_date');
    }
  });

  test(
    'date descriptor rejects impossible, malformed, and reversed bounds',
    () {
      expect(() => AskUserDateInput(min: '2023-02-29'), throwsArgumentError);
      expect(() => AskUserDateInput(max: 'tomorrow'), throwsArgumentError);
      expect(
        () => AskUserDateInput(min: '2025-01-01', max: '2024-01-01'),
        throwsArgumentError,
      );
    },
  );

  Map<String, Object> file(String name, int size) => {
    'name': name,
    'sizeBytes': size,
  };

  test('file metadata accepts zero bytes and an inclusive maximum', () {
    final input = AskUserFileInput(
      maxSizeBytes: 1024,
      allowedExtensions: {'PDF', 'txt'},
    );
    check(input, file('report.PdF', 0));
    check(input, file('draft.v2.TXT', 1024));
    check(input, file('draft.txt', 1025), 'file_too_large');
    check(AskUserFileInput(maxSizeBytes: 0), file('empty', 0));
    check(AskUserFileInput(maxSizeBytes: 0), file('full', 1), 'file_too_large');
  });

  test(
    'file extension allowlist checks the final suffix and a basename stem',
    () {
      final input = AskUserFileInput(allowedExtensions: {'pdf'});
      for (final name in [
        'report.pdf.exe',
        'report',
        'report.',
        '.pdf',
        'report.pdf ',
      ]) {
        check(input, file(name, 100), 'extension_not_allowed');
      }
      check(AskUserFileInput(), file('README', 2048));
      check(AskUserFileInput(), file('.profile', 2048));
    },
  );

  test(
    'file answers require a basename and nonnegative integer byte count',
    () {
      final input = AskUserFileInput();
      for (final value in [
        null,
        'report.pdf',
        {},
        {'name': 'file'},
        {'sizeBytes': 1},
        {'name': 4, 'sizeBytes': 0},
        {'name': 'file', 'sizeBytes': 0.5},
        {'name': 'file', 'sizeBytes': '1'},
        file('file', -1),
      ]) {
        check(input, value, 'invalid_file');
      }
      for (final name in [
        '',
        '  ',
        '.',
        '..',
        '../file.txt',
        r'a\b.txt',
        'file\x00.txt',
      ]) {
        check(input, file(name, 0), 'invalid_file');
      }
    },
  );

  test(
    'file descriptors reject malformed constraints and freeze the allowlist',
    () {
      expect(() => AskUserFileInput(maxSizeBytes: -1), throwsArgumentError);
      for (final ext in ['', '.pdf', 'tar.gz', 'a/b']) {
        expect(
          () => AskUserFileInput(allowedExtensions: {ext}),
          throwsArgumentError,
        );
      }
      final extensions = {'pdf'};
      final input = AskUserFileInput(allowedExtensions: extensions);
      extensions.add('txt');
      check(input, file('a.txt', 0), 'extension_not_allowed');
    },
  );

  test(
    'an ordinary question is a form and permits a default or auto-submit',
    () {
      final policy = AskUserRequestClass.classify(
        hasSideEffects: false,
        isHighRisk: false,
      );
      expect(policy, AskUserRequestClass.form);
      expect(policy.requiresExplicitAnswer, false);
      expect(policy.canAutoSubmit, true);
      expect(policy.canUseDefaultAnswer, true);
    },
  );

  test(
    'either risk flag or an explicit approval request forbids automatic answers',
    () {
      for (final (effects, risk, approval) in [
        (true, false, false),
        (false, true, false),
        (true, true, false),
        (false, false, true),
        (true, false, true),
        (false, true, true),
        (true, true, true),
      ]) {
        final policy = AskUserRequestClass.classify(
          hasSideEffects: effects,
          isHighRisk: risk,
          requestsApproval: approval,
        );
        expect(policy, AskUserRequestClass.approval);
        expect(policy.requiresExplicitAnswer, true);
        expect(policy.canAutoSubmit, false);
        expect(policy.canUseDefaultAnswer, false);
      }
    },
  );

  final created = DateTime.utc(2024, 2, 29, 18, 30, 0, 1, 234);
  final pending = PendingApprovalRecord(
    id: 'call-87',
    createdAt: created.toLocal(),
    requestPayloadHash: 'payload-digest',
  );
  const ttl = Duration(minutes: 5);
  final deadline = created.add(ttl);

  test(
    'approval records serialize their identity, hash, UTC creation instant and state',
    () {
      final json = pending.toJson();
      expect(json['id'], 'call-87');
      expect(json['requestPayloadHash'], 'payload-digest');
      expect(json['createdAt'], '2024-02-29T18:30:00.001234Z');
      expect(json['state'], 'pending');
      for (final state in PendingApprovalState.values) {
        final record = PendingApprovalRecord(
          id: pending.id,
          createdAt: created,
          requestPayloadHash: pending.requestPayloadHash,
          state: state,
        );
        final wire = jsonEncode(record.toJson());
        final restored = PendingApprovalRecord.fromJson(
          jsonDecode(wire) as Map<String, dynamic>,
        );
        expect(restored.state, state);
        expect(restored.id, pending.id);
        expect(restored.requestPayloadHash, pending.requestPayloadHash);
        expect(restored.createdAt, created);
        expect(restored.createdAt.isUtc, true);
      }
    },
  );

  test('a resumed pending approval expires exactly at its deadline', () {
    final restored = PendingApprovalRecord.fromJson(pending.toJson());
    final before = deadline.subtract(const Duration(microseconds: 1));
    expect(
      restored.expireIfDue(now: before, ttl: ttl).state,
      PendingApprovalState.pending,
    );
    for (final now in [deadline, deadline.add(const Duration(days: 2))]) {
      final expired = restored.expireIfDue(now: now, ttl: ttl);
      expect(expired.state, PendingApprovalState.expired);
      expect(expired.id, restored.id);
      expect(expired.requestPayloadHash, restored.requestPayloadHash);
      expect(expired.createdAt, restored.createdAt);
    }
    expect(restored.state, PendingApprovalState.pending);
  });

  test(
    'answered and expired approvals retain their state when checking expiry',
    () {
      for (final state in [
        PendingApprovalState.answered,
        PendingApprovalState.expired,
      ]) {
        final restored = PendingApprovalRecord.fromJson({
          ...pending.toJson(),
          'state': state.name,
        });
        for (final now in [created, deadline]) {
          expect(restored.expireIfDue(now: now, ttl: ttl).state, state);
        }
      }
    },
  );

  test('a zero TTL expires immediately and a negative TTL is invalid', () {
    expect(
      pending.expireIfDue(now: created, ttl: Duration.zero).state,
      PendingApprovalState.expired,
    );
    expect(
      () => pending.expireIfDue(
        now: created,
        ttl: const Duration(microseconds: -1),
      ),
      throwsArgumentError,
    );
  });

  test('incomplete or malformed saved approvals cannot resume', () {
    final json = pending.toJson();
    for (final key in json.keys) {
      final incomplete = Map.of(json)..remove(key);
      expect(
        () => PendingApprovalRecord.fromJson(incomplete),
        throwsFormatException,
      );
    }
    for (final change in [
      {'id': ' '},
      {'requestPayloadHash': ''},
      {'state': 'unknown'},
      {'state': 1},
      {'createdAt': 0},
      {'createdAt': 'invalid'},
      {'createdAt': '2023-02-29T18:30:00.000Z'},
      {'createdAt': '2024-02-29T18:30:00.000'},
    ]) {
      expect(
        () => PendingApprovalRecord.fromJson({...json, ...change}),
        throwsFormatException,
      );
    }
  });
}
