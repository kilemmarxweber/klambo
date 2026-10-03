import "package:flutter/material.dart";
import "package:klambo_messagerie/core/app_theme.dart";

enum MessageMenuAction {
  react,
  reply,
  copy,
  forward,
  edit,
  pin,
  star,
  select,
  saveImage,
  delete,
}

class MessageMenuResult {
  const MessageMenuResult(this.action, {this.emoji});
  final MessageMenuAction action;
  final String? emoji;
}

/// Menu message animé : réactions + actions (répondre, copier, transférer…).
Future<MessageMenuResult?> showMessageActionMenu({
  required BuildContext context,
  required bool mine,
  required bool canEdit,
  required String preview,
  bool canSaveImage = false,
  bool isDeleted = false,
  bool canReply = true,
  bool canDelete = false,
}) {
  return showModalBottomSheet<MessageMenuResult>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    barrierColor: Colors.black.withValues(alpha: 0.35),
    builder: (ctx) {
      final scheme = Theme.of(ctx).colorScheme;
      final surface = scheme.surface;
      final isDark = Theme.of(ctx).brightness == Brightness.dark;

      return _AnimatedMessageMenuSheet(
        surface: surface,
        isDark: isDark,
        isDeleted: isDeleted,
        mine: mine,
        canEdit: canEdit,
        preview: preview,
        canSaveImage: canSaveImage,
        canReply: canReply,
        canDelete: canDelete || mine,
      );
    },
  );
}

class _AnimatedMessageMenuSheet extends StatefulWidget {
  const _AnimatedMessageMenuSheet({
    required this.surface,
    required this.isDark,
    required this.isDeleted,
    required this.mine,
    required this.canEdit,
    required this.preview,
    required this.canSaveImage,
    required this.canReply,
    required this.canDelete,
  });

  final Color surface;
  final bool isDark;
  final bool isDeleted;
  final bool mine;
  final bool canEdit;
  final String preview;
  final bool canSaveImage;
  final bool canReply;
  final bool canDelete;

  @override
  State<_AnimatedMessageMenuSheet> createState() =>
      _AnimatedMessageMenuSheetState();
}

class _AnimatedMessageMenuSheetState extends State<_AnimatedMessageMenuSheet>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.12),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _scale = Tween<double>(begin: 0.94, end: 1).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack),
    );
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _pop(MessageMenuResult result) async {
    await _ctrl.reverse();
    if (mounted) Navigator.pop(context, result);
  }

  @override
  Widget build(BuildContext context) {
    final panel = widget.isDeleted
        ? _DeletedPanel(surface: widget.surface, onSelect: _pop)
        : _FullPanel(
            surface: widget.surface,
            isDark: widget.isDark,
            mine: widget.mine,
            canEdit: widget.canEdit,
            preview: widget.preview,
            canSaveImage: widget.canSaveImage,
            canReply: widget.canReply,
            canDelete: widget.canDelete,
            onResult: _pop,
          );

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: FadeTransition(
          opacity: _fade,
          child: SlideTransition(
            position: _slide,
            child: ScaleTransition(
              scale: _scale,
              alignment: Alignment.bottomCenter,
              child: panel,
            ),
          ),
        ),
      ),
    );
  }
}

class _DeletedPanel extends StatelessWidget {
  const _DeletedPanel({required this.surface, required this.onSelect});

  final Color surface;
  final Future<void> Function(MessageMenuResult) onSelect;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: surface,
      elevation: 10,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                "Ce message a été retiré",
                style: TextStyle(
                  fontSize: 14,
                  fontStyle: FontStyle.italic,
                  color: EteyeloColors.subtitle,
                ),
              ),
            ),
          ),
          _MenuItem(
            icon: Icons.check_box_outlined,
            label: "Sélectionner",
            index: 0,
            onTap: () => onSelect(
              const MessageMenuResult(MessageMenuAction.select),
            ),
          ),
          const SizedBox(height: 6),
        ],
      ),
    );
  }
}

class _FullPanel extends StatelessWidget {
  const _FullPanel({
    required this.surface,
    required this.isDark,
    required this.mine,
    required this.canEdit,
    required this.preview,
    required this.canSaveImage,
    required this.canReply,
    required this.canDelete,
    required this.onResult,
  });

  final Color surface;
  final bool isDark;
  final bool mine;
  final bool canEdit;
  final String preview;
  final bool canSaveImage;
  final bool canReply;
  final bool canDelete;
  final Future<void> Function(MessageMenuResult) onResult;

  @override
  Widget build(BuildContext context) {
    final actions = <_ActionDef>[
      if (canReply)
        _ActionDef(Icons.reply_rounded, "Répondre", MessageMenuAction.reply),
      if (canSaveImage)
        _ActionDef(
          Icons.download_rounded,
          "Enregistrer dans la galerie",
          MessageMenuAction.saveImage,
        ),
      _ActionDef(Icons.copy_rounded, "Copier", MessageMenuAction.copy),
      _ActionDef(
        Icons.shortcut_rounded,
        "Transférer",
        MessageMenuAction.forward,
      ),
      if (canEdit && mine)
        _ActionDef(Icons.edit_outlined, "Modifier", MessageMenuAction.edit),
      _ActionDef(Icons.push_pin_outlined, "Épingler", MessageMenuAction.pin),
      _ActionDef(
        Icons.star_outline_rounded,
        "Marquer comme important",
        MessageMenuAction.star,
      ),
      _ActionDef(
        Icons.check_box_outlined,
        "Sélectionner",
        MessageMenuAction.select,
      ),
      if (canDelete)
        _ActionDef(
          Icons.delete_outline,
          mine ? "Supprimer" : "Retirer (admin)",
          MessageMenuAction.delete,
          danger: true,
        ),
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: surface,
          elevation: 8,
          shadowColor: Colors.black26,
          borderRadius: BorderRadius.circular(28),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                for (var i = 0; i < 6; i++)
                  _ReactionChip(
                    emoji: const ["👍", "❤️", "😂", "😮", "😢", "🙏"][i],
                    delayMs: 40 + i * 28,
                    onTap: () => onResult(
                      MessageMenuResult(
                        MessageMenuAction.react,
                        emoji: const ["👍", "❤️", "😂", "😮", "😢", "🙏"][i],
                      ),
                    ),
                  ),
                _ReactionChip(
                  emoji: null,
                  delayMs: 40 + 6 * 28,
                  onTap: () => onResult(
                    const MessageMenuResult(
                      MessageMenuAction.react,
                      emoji: "➕",
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Material(
          color: surface,
          elevation: 10,
          shadowColor: Colors.black26,
          borderRadius: BorderRadius.circular(18),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(top: 10, bottom: 4),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white24
                      : const Color(0xFFD1D5DB),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              if (preview.trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      preview.length > 80
                          ? "${preview.substring(0, 80)}…"
                          : preview,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.3,
                        color: ChatPalette.subtitle(context),
                      ),
                    ),
                  ),
                ),
              for (var i = 0; i < actions.length; i++) ...[
                if (actions[i].action == MessageMenuAction.select ||
                    actions[i].action == MessageMenuAction.delete)
                  Divider(
                    height: 1,
                    color: isDark
                        ? Colors.white12
                        : EteyeloColors.listDivider,
                  ),
                _MenuItem(
                  icon: actions[i].icon,
                  label: actions[i].label,
                  danger: actions[i].danger,
                  index: i,
                  onTap: () => onResult(
                    MessageMenuResult(actions[i].action),
                  ),
                ),
              ],
              const SizedBox(height: 4),
            ],
          ),
        ),
      ],
    );
  }
}

class _ActionDef {
  const _ActionDef(this.icon, this.label, this.action, {this.danger = false});
  final IconData icon;
  final String label;
  final MessageMenuAction action;
  final bool danger;
}

class _ReactionChip extends StatefulWidget {
  const _ReactionChip({
    required this.emoji,
    required this.delayMs,
    required this.onTap,
  });

  final String? emoji;
  final int delayMs;
  final VoidCallback onTap;

  @override
  State<_ReactionChip> createState() => _ReactionChipState();
}

class _ReactionChipState extends State<_ReactionChip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _scale = Tween<double>(begin: 0.4, end: 1).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack),
    );
    Future<void>.delayed(Duration(milliseconds: widget.delayMs), () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: widget.onTap,
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: widget.emoji != null
                ? Text(widget.emoji!, style: const TextStyle(fontSize: 24))
                : const Icon(Icons.add_circle_outline, size: 24),
          ),
        ),
      ),
    );
  }
}

class _MenuItem extends StatefulWidget {
  const _MenuItem({
    required this.icon,
    required this.label,
    required this.index,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final int index;
  final VoidCallback onTap;
  final bool danger;

  @override
  State<_MenuItem> createState() => _MenuItemState();
}

class _MenuItemState extends State<_MenuItem>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.18),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    Future<void>.delayed(Duration(milliseconds: 50 + widget.index * 32), () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color =
        widget.danger ? Colors.red.shade700 : Theme.of(context).colorScheme.onSurface;
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: ListTile(
          leading: Icon(widget.icon, color: color, size: 22),
          title: Text(
            widget.label,
            style: TextStyle(
              fontSize: 15.5,
              fontWeight: FontWeight.w500,
              color: color,
            ),
          ),
          onTap: widget.onTap,
          contentPadding: const EdgeInsets.symmetric(horizontal: 18),
          dense: true,
          visualDensity: VisualDensity.compact,
          minVerticalPadding: 12,
        ),
      ),
    );
  }
}
