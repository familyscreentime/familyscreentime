/// Group labels shown next to apps; in parent mode they lead to the rules
/// of the group.
library;

import 'package:flutter/material.dart';
import 'package:screentime_engine/screentime_engine.dart';

import '../controller.dart';
import 'limit_screen.dart';

/// Opens the group [groupId]: its rules and its apps.
Future<void> openGroupRules(
  BuildContext context,
  AppController c,
  String groupId,
) => openLimit(context, c, AppTarget.group(groupId));

/// Labels of the groups containing [appId].
class GroupChips extends StatelessWidget {
  final AppController controller;
  final String appId;

  /// A group left out, e.g. the one being edited.
  final String? exclude;

  /// Tapping a label opens the group's rules (parent mode only).
  final bool interactive;

  const GroupChips({
    super.key,
    required this.controller,
    required this.appId,
    this.exclude,
    this.interactive = false,
  });

  @override
  Widget build(BuildContext context) {
    final ids = [
      for (final id in controller.groupsOf(appId))
        if (id != exclude) id,
    ];
    if (ids.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final style = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onTertiaryContainer,
    );
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: [
        for (final id in ids)
          Material(
            color: theme.colorScheme.tertiaryContainer,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: interactive
                  ? () => openGroupRules(context, controller, id)
                  : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.folder_outlined, size: 12, color: style?.color),
                    const SizedBox(width: 4),
                    Text(controller.groupName(id), style: style),
                    if (interactive) ...[
                      const SizedBox(width: 2),
                      Icon(Icons.chevron_right, size: 12, color: style?.color),
                    ],
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
