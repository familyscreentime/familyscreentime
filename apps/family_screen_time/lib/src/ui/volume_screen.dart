/// The parent's caps on the media volume, with headphones and on the
/// speaker.
library;

import 'package:flutter/material.dart';

import '../controller.dart';

/// Cap offered when a limit is turned on.
const defaultVolumeCap = 60;

class VolumeScreen extends StatefulWidget {
  final AppController controller;

  const VolumeScreen({super.key, required this.controller});

  @override
  State<VolumeScreen> createState() => _VolumeScreenState();
}

class _VolumeScreenState extends State<VolumeScreen> {
  int? _headphones;
  int? _speaker;

  @override
  void initState() {
    super.initState();
    final child = widget.controller.child;
    _headphones = child?.volumeHeadphones;
    _speaker = child?.volumeSpeaker;
  }

  Future<void> _save() => widget.controller.setVolumeCap(
    headphones: _headphones,
    speaker: _speaker,
  );

  Widget _cap({
    required String title,
    required IconData icon,
    required int? value,
    required void Function(int?) set,
  }) {
    final s = widget.controller.s;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        children: [
          SwitchListTile(
            secondary: Icon(icon),
            title: Text(title),
            subtitle: Text(
              value == null
                  ? s.t('volumeNoCap')
                  : s.t('volumePercent', {'percent': '$value'}),
            ),
            value: value != null,
            onChanged: (on) {
              setState(() => set(on ? defaultVolumeCap : null));
              _save();
            },
          ),
          if (value != null)
            Slider(
              value: value.toDouble(),
              min: 10,
              max: 100,
              divisions: 18,
              label: s.t('volumePercent', {'percent': '$value'}),
              onChanged: (v) => setState(() => set(v.round())),
              onChangeEnd: (_) => _save(),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.controller.s;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(s.t('volumeTitle'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(s.t('volumeHint')),
          const SizedBox(height: 8),
          _cap(
            title: s.t('volumeHeadphones'),
            icon: Icons.headphones,
            value: _headphones,
            set: (v) => _headphones = v,
          ),
          _cap(
            title: s.t('volumeSpeaker'),
            icon: Icons.volume_up,
            value: _speaker,
            set: (v) => _speaker = v,
          ),
          const SizedBox(height: 8),
          Text(s.t('volumeNote'), style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}
