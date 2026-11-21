// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Kelivo/features/workspace/models/environment_hub_model.dart';
import 'package:Kelivo/features/workspace/pages/environment_hub_page.dart';

/// Navigation integration uses Flutter Navigator and the real read-only page,
/// but not actual Linux/PRoot/SSH environments or a production app route.
void main() {
  final snapshot = EnvironmentHubSnapshot(
    observedAt: DateTime.utc(2026, 11, 21),
    instances: [
      EnvironmentInstanceSnapshot(
        id: 'test-environment',
        label: 'Test Environment',
        backend: EnvironmentBackend.androidProot,
        lifecycle: EnvironmentLifecycle.stopped,
        ports: [
          EnvironmentPortSnapshot(
            port: 8022,
            protocol: EnvironmentPortProtocol.tcp,
            loopbackOnly: true,
          ),
        ],
      ),
    ],
  );

  testWidgets('navigate from host route, display observation and return', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => EnvironmentHubPage(snapshot: snapshot),
                  ),
                ),
                child: const Text('Show environments'),
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.text('Show environments'), findsOneWidget);
    await tester.tap(find.text('Show environments'));
    await tester.pumpAndSettle();
    expect(find.text('Environment Hub'), findsOneWidget);
    expect(find.text('Test Environment'), findsOneWidget);
    expect(find.text('TCP 8022 · loopback'), findsOneWidget);
    expect(find.text('No host actions'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Show environments'), findsOneWidget);
    expect(find.text('Test Environment'), findsNothing);
  });

  testWidgets('empty snapshot navigates without shell or remote actions', (
    tester,
  ) async {
    final empty = EnvironmentHubSnapshot(
      observedAt: DateTime.utc(2026, 11, 21),
      instances: [],
    );
    await tester.pumpWidget(
      MaterialApp(home: EnvironmentHubPage(snapshot: empty)),
    );
    expect(find.text('No environments recorded'), findsOneWidget);
    expect(
      find.text('A host observation source is not connected.'),
      findsOneWidget,
    );
    expect(find.byType(ElevatedButton), findsNothing);
  });
}
