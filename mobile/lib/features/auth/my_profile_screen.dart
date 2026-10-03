import "dart:typed_data";

import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:klambo_messagerie/core/app_theme.dart";
import "package:klambo_messagerie/core/l10n.dart";
import "package:klambo_messagerie/core/person_name.dart";
import "package:klambo_messagerie/core/profile_photo.dart";
import "package:klambo_messagerie/features/auth/session_provider.dart";
import "package:klambo_messagerie/widgets/section_panel.dart";
import "package:klambo_messagerie/widgets/user_avatar.dart";

/// Profil de l'utilisateur connecté : prénom, nom, téléphone + photo modifiable.
class MyProfileScreen extends ConsumerStatefulWidget {
  const MyProfileScreen({super.key});

  @override
  ConsumerState<MyProfileScreen> createState() => _MyProfileScreenState();
}

class _MyProfileScreenState extends ConsumerState<MyProfileScreen> {
  final _nameCtrl = TextEditingController();
  final _prenomCtrl = TextEditingController();
  Uint8List? _imageBytes;
  String _imageFilename = "avatar.jpg";
  bool _busy = false;
  String? _error;
  String? _savedHint;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _hydrateFromSession());
  }

  void _hydrateFromSession() {
    final user = ref.read(sessionProvider).me?["user"];
    if (user is! Map) return;
    var name = user["name"]?.toString() ?? "";
    if (name.startsWith("+")) name = "";
    setState(() {
      _nameCtrl.text = name;
      _prenomCtrl.text = user["prenom"]?.toString() ?? "";
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _prenomCtrl.dispose();
    super.dispose();
  }

  String? get _phone {
    final user = ref.read(sessionProvider).me?["user"];
    if (user is! Map) return null;
    return user["telephone"]?.toString() ??
        user["phone"]?.toString() ??
        user["phoneNumber"]?.toString();
  }

  String? get _currentImage {
    final user = ref.watch(sessionProvider).me?["user"];
    if (user is! Map) return null;
    return user["image"]?.toString();
  }

  Future<void> _pickImage() async {
    setState(() {
      _error = null;
      _savedHint = null;
    });
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

  Future<void> _save() async {
    final prenom = _prenomCtrl.text.trim();
    final nom = _nameCtrl.text.trim();
    if (prenom.isEmpty && nom.isEmpty) {
      setState(() => _error = "Indiquez au moins un prénom ou un nom.");
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _savedHint = null;
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
      if (!mounted) return;
      setState(() {
        _imageBytes = null;
        _savedHint = "Profil enregistré";
      });
      _hydrateFromSession();
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = ref.watch(l10nProvider);
    final phone = _phone?.trim();
    final nom = _nameCtrl.text.trim();
    final prenom = _prenomCtrl.text.trim();
    final avatarName = nom.isNotEmpty ? nom : prenom;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: ChatPalette.pageBackground(context),
      appBar: AppBar(
        title: Text(l10n.myProfile),
      ),
      body: ListView(
        children: [
          SectionPanel(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 16),
            child: Column(
              children: [
                GestureDetector(
                  onTap: _busy ? null : _pickImage,
                  child: Stack(
                    alignment: Alignment.bottomRight,
                    children: [
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        child: _imageBytes != null
                            ? CircleAvatar(
                                key: const ValueKey("picked"),
                                radius: 56,
                                backgroundImage: MemoryImage(_imageBytes!),
                              )
                            : UserAvatar(
                                key: const ValueKey("current"),
                                image: _currentImage,
                                name: avatarName.isEmpty ? "?" : avatarName,
                                radius: 56,
                              ),
                      ),
                      Container(
                        decoration: const BoxDecoration(
                          color: EteyeloColors.primaryDark,
                          shape: BoxShape.circle,
                        ),
                        padding: const EdgeInsets.all(7),
                        child: const Icon(
                          Icons.camera_alt,
                          color: Colors.white,
                          size: 16,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: _busy ? null : _pickImage,
                  child: Text(l10n.changePhoto),
                ),
              ],
            ),
          ),
          SectionPanel(
            child: Column(
              children: [
                TextField(
                  controller: _prenomCtrl,
                  enabled: !_busy,
                  textCapitalization: TextCapitalization.words,
                  autofillHints: const [AutofillHints.givenName],
                  decoration: InputDecoration(labelText: l10n.firstName),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _nameCtrl,
                  enabled: !_busy,
                  textCapitalization: TextCapitalization.words,
                  autofillHints: const [AutofillHints.familyName],
                  decoration: InputDecoration(labelText: l10n.lastName),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                InputDecorator(
                  decoration: InputDecoration(
                    labelText: l10n.phoneNumber,
                    prefixIcon: const Icon(Icons.phone_outlined),
                  ),
                  child: Text(
                    (phone != null && phone.isNotEmpty) ? phone : "—",
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: scheme.onSurface,
                    ),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: TextStyle(color: scheme.error)),
                ],
                if (_savedHint != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _savedHint!,
                    style: const TextStyle(
                      color: Color(0xFF16A34A),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _busy ? null : _save,
                    child: _busy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(l10n.saveProfile),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
