// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Kelivo/features/workspace/models/environment_hub_model.dart';
import 'package:Kelivo/features/workspace/pages/environment_hub_page.dart';

void main() {
  final observed = DateTime.utc(2026, 11, 21);
  testWidgets('empty Hub renders no observation and no action controls', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: EnvironmentHubPage(
          snapshot: EnvironmentHubSnapshot(observedAt: observed, instances: []),
        ),
      ),
    );
    expect(find.text('Environment Hub'), findsOneWidget);
    expect(find.text('No environments recorded'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing);
  });

  testWidgets('mock snapshot shows metadata, ports and disabled entries', (
    tester,
  ) async {
    final instance = EnvironmentInstanceSnapshot(
      id: 'android-main',
      label: 'Local PRoot',
      backend: EnvironmentBackend.androidProot,
      lifecycle: EnvironmentLifecycle.running,
      usedBytes: 1024,
      capacityBytes: 2048,
      ports: [
        EnvironmentPortSnapshot(
          port: 8080,
          protocol: EnvironmentPortProtocol.tcp,
          loopbackOnly: true,
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: EnvironmentHubPage(
          snapshot: EnvironmentHubSnapshot(
            observedAt: observed,
            instances: [instance],
          ),
        ),
      ),
    );
    expect(find.text('Local PRoot'), findsOneWidget);
    expect(find.text('Storage: 1024 / 2048 bytes'), findsOneWidget);
    expect(find.text('TCP 8080 · loopback'), findsOneWidget);
    expect(find.text('Processes: unavailable'), findsOneWidget);
    expect(find.byType(ElevatedButton), findsNothing);
  });
}
