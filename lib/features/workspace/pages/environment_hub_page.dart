// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:Kelivo/features/workspace/models/environment_hub_model.dart';

/// Read-only Environment Hub page prototype driven exclusively by snapshots.
/// The host may later wire real observation and authorized navigation; this
/// widget never starts shells, opens listeners, reads credentials or mutates VM.
class EnvironmentHubPage extends StatelessWidget {
  const EnvironmentHubPage({super.key, required this.snapshot});
  final EnvironmentHubSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entries = snapshot.instances;
    return Scaffold(
      appBar: AppBar(title: const Text('Environment Hub')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Read-only environment snapshot',
            style: theme.textTheme.titleMedium,
          ),
          Text('Observed ${snapshot.observedAt.toIso8601String()}'),
          const SizedBox(height: 16),
          if (entries.isEmpty)
            const ListTile(
              title: Text('No environments recorded'),
              subtitle: Text('A host observation source is not connected.'),
            ),
          for (final env in entries)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(env.label, style: theme.textTheme.titleMedium),
                    Text('${env.backend.wireName} · ${env.lifecycle.wireName}'),
                    Text('ID: ${env.id}'),
                    if (env.distribution != null)
                      Text('Distribution: ${env.distribution}'),
                    if (env.version != null) Text('Version: ${env.version}'),
                    if (env.usedBytes != null && env.capacityBytes != null)
                      Text(
                        'Storage: ${env.usedBytes} / ${env.capacityBytes} bytes',
                      ),
                    Text(
                      'Ports (${env.ports.length})',
                      style: theme.textTheme.titleSmall,
                    ),
                    for (final port in env.ports)
                      Text(
                        '${port.protocol.wireName.toUpperCase()} ${port.port} · '
                        '${port.loopbackOnly ? 'loopback' : 'non-loopback'}',
                      ),
                    const SizedBox(height: 8),
                    const Wrap(
                      spacing: 8,
                      children: [
                        Chip(label: Text('Terminal: preview only')),
                        Chip(label: Text('Processes: unavailable')),
                        Chip(label: Text('No host actions')),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
