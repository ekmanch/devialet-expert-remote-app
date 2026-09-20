import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/ui_variant.dart';
import '../../domain/devialet_client_provider.dart';
import '../../domain/settings/settings_owner.dart';
import '../../networking/devialet_client.dart';

/// MANUAL TEST SCREEN — not a real feature screen.
///
/// Phase 1 has no built UI beyond this: a bare scaffold for manually
/// triggering every [Control]-tagged command against a real amp and
/// observing status broadcasts, per the phase's ground rules. Does not
/// auto-discover or auto-connect to hardware — you must type the amp's IP.
class DebugNetworkScreen extends ConsumerStatefulWidget {
  const DebugNetworkScreen({super.key, required this.variant});

  final UiVariant variant;

  @override
  ConsumerState<DebugNetworkScreen> createState() => _DebugNetworkScreenState();
}

class _DebugNetworkScreenState extends ConsumerState<DebugNetworkScreen> {
  final _ipController = TextEditingController();
  double _volumeDb = -40.0;
  int _sourceIndex = 0;
  final List<String> _log = [];

  static const double _minVolumeDb = -60.0;

  @override
  void dispose() {
    _ipController.dispose();
    super.dispose();
  }

  void _appendLog(String message) {
    final timestamp = DateTime.now().toIso8601String().substring(11, 19);
    setState(() {
      _log.insert(0, '$timestamp  $message');
      if (_log.length > 50) _log.removeLast();
    });
  }

  DevialetClient get _client => ref.read(devialetClientProvider);

  void _applyIp() {
    final ip = _ipController.text.trim();
    _client.deviceIp = ip.isEmpty ? null : ip;
    _appendLog('Target IP set to ${_client.deviceIp ?? "(none)"}');
  }

  Future<void> _guard(String label, Future<void> Function() action) async {
    try {
      await action();
      _appendLog('Sent: $label');
    } on NoDeviceIpSetException {
      _appendLog('Error: no device IP set — enter one above first');
    } catch (e) {
      _appendLog('Error sending $label: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final statusAsync = ref.watch(ampStatusStreamProvider);
    final ceiling = ref.watch(settingsProvider).ceilingDb;
    final sliderMin = math.min(_minVolumeDb, ceiling - 0.5);
    final shownVolume = _volumeDb.clamp(sliderMin, ceiling).toDouble();

    final body = ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'MANUAL TEST SCREEN — not auto-connected. UI variant: ${widget.variant.name}',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _ipController,
          decoration: const InputDecoration(labelText: 'Amp IP address'),
          onSubmitted: (_) => _applyIp(),
        ),
        const SizedBox(height: 8),
        ElevatedButton(onPressed: _applyIp, child: const Text('Set target IP')),
        const Divider(height: 32),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ElevatedButton(
              onPressed: () => _guard('Power ON', () => _client.setPower(true)),
              child: const Text('Power ON'),
            ),
            ElevatedButton(
              onPressed: () => _guard('Power OFF', () => _client.setPower(false)),
              child: const Text('Power OFF'),
            ),
            ElevatedButton(
              onPressed: () => _guard('Mute ON', () => _client.setMute(true)),
              child: const Text('Mute ON'),
            ),
            ElevatedButton(
              onPressed: () => _guard('Mute OFF', () => _client.setMute(false)),
              child: const Text('Mute OFF'),
            ),
          ],
        ),
        const Divider(height: 32),
        Text(
          'Volume: ${shownVolume.toStringAsFixed(1)} dB '
          '(clamped to the Settings ceiling $ceiling dB — known-gotchas.md #6)',
        ),
        Slider(
          value: shownVolume,
          min: sliderMin,
          max: ceiling,
          divisions: ((ceiling - sliderMin) / 0.5).round(),
          label: '${shownVolume.toStringAsFixed(1)} dB',
          onChanged: (v) => setState(() => _volumeDb = v),
          onChangeEnd: (v) => _guard('Set volume $v dB', () => _client.setVolumeDb(v, maxDb: ceiling)),
        ),
        const Divider(height: 32),
        const Text('Source status index (0-14; 1 = hardcoded special case):'),
        Row(
          children: [
            Expanded(
              child: Slider(
                value: _sourceIndex.toDouble(),
                min: 0,
                max: 14,
                divisions: 14,
                label: '$_sourceIndex',
                onChanged: (v) => setState(() => _sourceIndex = v.round()),
              ),
            ),
            ElevatedButton(
              onPressed: () => _guard('Select source $_sourceIndex', () => _client.selectSource(_sourceIndex, maxDb: ceiling)),
              child: const Text('Select'),
            ),
          ],
        ),
        const Divider(height: 32),
        Text('Live status broadcast:', style: Theme.of(context).textTheme.titleSmall),
        statusAsync.when(
          data: (report) => Text(
            'From: ${report.senderIp}   Name: ${report.status.deviceName}\n'
            'Power: ${report.status.isPoweredOn}   Mute: ${report.status.isMuted}\n'
            'Active source index: ${report.status.activeSourceIndex}   Volume: ${report.status.volumeDb} dB',
          ),
          loading: () => const Text('Waiting for first broadcast…'),
          error: (e, _) => Text('Status listener error: $e'),
        ),
        const Divider(height: 32),
        Text('Outgoing log:', style: Theme.of(context).textTheme.titleSmall),
        for (final entry in _log) Text(entry, style: Theme.of(context).textTheme.bodySmall),
      ],
    );

    if (widget.variant == UiVariant.ios) {
      return CupertinoPageScaffold(
        navigationBar: const CupertinoNavigationBar(middle: Text('Devialet Remote — Debug')),
        child: SafeArea(child: Material(color: Colors.transparent, child: body)),
      );
    }

    return Scaffold(appBar: AppBar(title: const Text('Devialet Remote — Debug')), body: body);
  }
}
