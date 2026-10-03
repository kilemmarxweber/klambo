import "dart:typed_data";

import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:klambo_messagerie/core/app_theme.dart";
import "package:klambo_messagerie/core/l10n.dart";
import "package:klambo_messagerie/core/person_name.dart";
import "package:klambo_messagerie/core/profile_photo.dart";
import "package:klambo_messagerie/features/auth/session_provider.dart";
import "package:klambo_messagerie/widgets/section_panel.dart";

class ProfileOnboardingScreen extends ConsumerStatefulWidget {
  const ProfileOnboardingScreen({super.key});

  @override
  ConsumerState<ProfileOnboardingScreen> createState() =>
      _ProfileOnboardingScreenState();
}

class _ProfileOnboardingScreenState
    extends ConsumerState<ProfileOnboardingScreen> {
  final _nameCtrl = TextEditingController();
  final _prenomCtrl = TextEditingController();
  Uint8List? _imageBytes;
  String _imageFilename = "avatar.jpg";
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final me = ref.read(sessionProvider).me;
    final user = me?["user"];
    if (user is Map) {
      _nameCtrl.text = user["name"]?.toString() ?? "";
      _prenomCtrl.text = user["prenom"]?.toString() ?? "";
      if (_nameCtrl.text.startsWith("+")) _nameCtrl.clear();
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _prenomCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    setState(() => _error = null);
    try {
      final picked = await pickProfilePhoto();
      if (picked == null) return;
      setState(() {
        _imageBytes = picked.bytes;
        _imageFilename = picked.filename;
      });
    } catch (e) {
      setState(() => _error = "Impossible de choisir la photo : $e");
    }
  }

  Future<void> _submit() async {
    final prenom = _prenomCtrl.text.trim();
    final nom = _nameCtrl.text.trim();
    if (prenom.isEmpty && nom.isEmpty) {
      setState(() => _error = "Indiquez au moins un prénom ou un nom.");
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final auth = ref.read(authRepositoryProvider);
      final data = await auth.completeProfile(
        name: profileSubmitName(prenom: prenom, nom: nom),
        prenom: prenom.isEmpty ? null : prenom,
        imageBytes: _imageBytes,
        imageFilename: _imageFilename,
      );
      await ref.read(sessionProvider.notifier).applyAuthPayload({
        ...data,
        "token": ref.read(sessionProvider).token,
      });
      await ref.read(sessionProvider.notifier).refreshMe();
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = ref.watch(l10nProvider);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: ChatPalette.pageBackground(context),
      appBar: AppBar(title: Text(l10n.myProfile)),
      body: ListView(
        padding: const EdgeInsets.only(top: 8),
        children: [
          SectionPanel(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
            child: Column(
              children: [
                GestureDetector(
                  onTap: _busy ? null : _pickImage,
                  child: CircleAvatar(
                    radius: 48,
                    backgroundColor:
                        EteyeloColors.primary.withValues(alpha: 0.12),
                    backgroundImage:
                        _imageBytes != null ? MemoryImage(_imageBytes!) : null,
                    child: _imageBytes == null
                        ? Icon(
                            Icons.camera_alt_outlined,
                            size: 32,
                            color: scheme.onSurface.withValues(alpha: 0.55),
                          )
                        : null,
                  ),
                ),
                TextButton(
                  onPressed: _busy ? null : _pickImage,
                  child: Text(
                    _imageBytes == null
                        ? "${l10n.changePhoto} (${l10n.optional})"
                        : l10n.changePhoto,
                  ),
                ),
              ],
            ),
          ),
          SectionPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _prenomCtrl,
                  textCapitalization: TextCapitalization.words,
                  autofillHints: const [AutofillHints.givenName],
                  decoration: InputDecoration(labelText: l10n.firstName),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _nameCtrl,
                  textCapitalization: TextCapitalization.words,
                  autofillHints: const [AutofillHints.familyName],
                  decoration: InputDecoration(labelText: l10n.lastName),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: TextStyle(color: scheme.error)),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(l10n.saveProfile),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
