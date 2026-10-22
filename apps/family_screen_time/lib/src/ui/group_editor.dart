/// Creates or edits an app group: a name and a selection of installed apps.
library;

import 'package:flutter/material.dart';

import '../controller.dart';
import '../platform.dart';
import '../store.dart';
import 'group_chips.dart';

class GroupEditor extends StatefulWidget {
  final AppController controller;

  /// Group to edit; `null` creates a new one.
  final String? groupId;

  const GroupEditor({super.key, required this.controller, this.groupId});

  @override
  State<GroupEditor> createState() => _GroupEditorState();
}

class _GroupEditorState extends State<GroupEditor> {
  late final TextEditingController _name;
  late Set<String> _selected;
  List<InstalledApp>? _apps;
  String _query = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    final c = widget.controller;
    final id = widget.groupId;
    _name = TextEditingController(
      text: id == null ? '' : c.family.groupNames[id] ?? '',
    );
    _selected = {...?c.family.config.appGroups[id]};
    // The group's apps first; the order stays put while ticking.
    final members = {..._selected};
    c.platform.launcherApps().then((apps) {
      String name(InstalledApp a) =>
          c.appName(a.package, androidLabel: a.label).toLowerCase();
      final sorted = [...apps]
        ..sort((a, b) {
          final ma = members.contains(a.package);
          final mb = members.contains(b.package);
          if (ma != mb) return ma ? -1 : 1;
          return name(a).compareTo(name(b));
        });
      if (mounted) setState(() => _apps = sorted);
    });
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final c = widget.controller;
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = c.s.t('groupNameMissing'));
      return;
    }
    final id = widget.groupId ?? newId();
    await c.updateFamily(
      c.family.copyWith(
        config: configWithGroups(c.family.config, {
          ...c.family.config.appGroups,
          id: _selected,
        }),
        groupNames: {...c.family.groupNames, id: name},
      ),
    );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final s = c.s;
    final apps = _apps;
    final q = _query.toLowerCase();
    String name(InstalledApp a) => c.appName(a.package, androidLabel: a.label);
    final shown = apps
        ?.where(
          (a) =>
              q.isEmpty ||
              name(a).toLowerCase().contains(q) ||
              a.label.toLowerCase().contains(q) ||
              a.package.contains(q),
        )
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(s.t('groups')),
        actions: [TextButton(onPressed: _save, child: Text(s.t('save')))],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _name,
              decoration: InputDecoration(
                labelText: s.t('groupName'),
                errorText: _error,
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: s.t('searchApps'),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Expanded(
            child: shown == null
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    itemCount: shown.length,
                    itemBuilder: (context, i) {
                      final app = shown[i];
                      return CheckboxListTile(
                        value: _selected.contains(app.package),
                        title: Text(name(app)),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(app.package),
                            GroupChips(
                              controller: c,
                              appId: app.package,
                              exclude: widget.groupId,
                              interactive: true,
                            ),
                          ],
                        ),
                        onChanged: (v) => setState(() {
                          if (v == true) {
                            _selected.add(app.package);
                          } else {
                            _selected.remove(app.package);
                          }
                        }),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
