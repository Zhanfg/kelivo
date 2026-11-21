import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// Deterministic admission gates; no socket opened or credentials generated.
/// Host authentication integration is not installed in this package.
bool isLoopbackBind(InternetAddress address) {
  if (address.type != InternetAddressType.IPv4 &&
      address.type != InternetAddressType.IPv6) {
    return false;
  }
  return address.isLoopback;
}

class LocalRequestEvidence {
  const LocalRequestEvidence({
    required this.loopback,
    required this.authenticated,
    required this.taskAuthorized,
    required this.revoked,
    required this.expired,
    required this.withinRateLimit,
  });
  final bool loopback,
      authenticated,
      taskAuthorized,
      revoked,
      expired,
      withinRateLimit;
  bool get admitted =>
      loopback &&
      authenticated &&
      taskAuthorized &&
      !revoked &&
      !expired &&
      withinRateLimit;
}

void main() {
  test('only explicit IPv4 and IPv6 loopback accepted', () {
    expect(isLoopbackBind(InternetAddress.loopbackIPv4), isTrue);
    expect(isLoopbackBind(InternetAddress.loopbackIPv6), isTrue);
    for (final ip in ['0.0.0.0', '::', '192.168.1.1', '8.8.8.8']) {
      expect(isLoopbackBind(InternetAddress(ip)), isFalse);
    }
  });
  test('deny by default and require every independent security gate', () {
    const baseline = LocalRequestEvidence(
      loopback: true,
      authenticated: true,
      taskAuthorized: true,
      revoked: false,
      expired: false,
      withinRateLimit: true,
    );
    expect(baseline.admitted, isTrue);
    for (final rejected in [
      const LocalRequestEvidence(
        loopback: false,
        authenticated: true,
        taskAuthorized: true,
        revoked: false,
        expired: false,
        withinRateLimit: true,
      ),
      const LocalRequestEvidence(
        loopback: true,
        authenticated: false,
        taskAuthorized: true,
        revoked: false,
        expired: false,
        withinRateLimit: true,
      ),
      const LocalRequestEvidence(
        loopback: true,
        authenticated: true,
        taskAuthorized: false,
        revoked: false,
        expired: false,
        withinRateLimit: true,
      ),
      const LocalRequestEvidence(
        loopback: true,
        authenticated: true,
        taskAuthorized: true,
        revoked: true,
        expired: false,
        withinRateLimit: true,
      ),
      const LocalRequestEvidence(
        loopback: true,
        authenticated: true,
        taskAuthorized: true,
        revoked: false,
        expired: true,
        withinRateLimit: true,
      ),
      const LocalRequestEvidence(
        loopback: true,
        authenticated: true,
        taskAuthorized: true,
        revoked: false,
        expired: false,
        withinRateLimit: false,
      ),
    ]) {
      expect(rejected.admitted, isFalse);
    }
  });
  test('no listener or SSH daemon is opened by contract tests', () {
    expect(isLoopbackBind(InternetAddress.anyIPv4), isFalse);
  });
}
