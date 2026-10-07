import "dart:async";
import "dart:typed_data";

import "package:emoji_picker_flutter/emoji_picker_flutter.dart";
import "package:file_picker/file_picker.dart";
import "package:flutter/foundation.dart" as foundation;
import "package:flutter/material.dart";
import "package:image_picker/image_picker.dart";
import "package:klambo_messagerie/core/app_theme.dart";
import "package:klambo_messagerie/widgets/linkified_text.dart";
import "package:path/path.dart" as p;
import "package:path_provider/path_provider.dart";
import "package:record/record.dart";

enum PendingAttachmentKind { image, pdf, audio }

class PendingAttachment {
  PendingAttachment({
    required this.kind,
    required this.bytes,
    required this.filename,
    this.mimeType,
    this.durationMs,
  });

  final PendingAttachmentKind kind;
  final Uint8List bytes;
  final String filename;
  final String? mimeType;
  final int? durationMs;
}

/// Barre de saisie : texte, emojis (un ou plusieurs), image, PDF, audio.
class ChatComposer extends StatefulWidget {
  const ChatComposer({
    super.key,
    required this.controller,
    required this.sending,
    required this.onSend,
    this.enabled = true,
    this.autofocus = true,
    this.hintText = "Écrire un message…",
  });

  final TextEditingController controller;
  final bool sending;
  final bool enabled;
  final bool autofocus;
  final String hintText;

  /// Appelé avec le texte et la liste (éventuellement vide) de pièces jointes.
  final Future<void> Function(String text, List<PendingAttachment> attachments)
      onSend;

  @override
  State<ChatComposer> createState() => ChatComposerState();
}

class ChatComposerState extends State<ChatComposer> {
  final _focus = FocusNode();
  final _recorder = AudioRecorder();
  final List<PendingAttachment> _pending = [];

  bool _showEmoji = false;
  bool _emojiPanelReady = false;
  bool _showAttachActions = false;
  bool _recording = false;
  DateTime? _recordStartedAt;
  Timer? _recordTick;
  Duration _recordElapsed = Duration.zero;
  String? _error;

  bool get _hasText => widget.controller.text.trim().isNotEmpty;
  bool get _canSend =>
      widget.enabled &&
      !widget.sending &&
      !_recording &&
      (_hasText || _pending.isNotEmpty);

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
    if (widget.autofocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.enabled && !_recording) {
          requestFocus();
        }
      });
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    _recordTick?.cancel();
    _focus.dispose();
    _recorder.dispose();
    super.dispose();
  }

  bool get hasFocus => _focus.hasFocus;

  /// Ferme le clavier avant d'ouvrir un autre Ã©cran, comme celui d'appel.
  void unfocus() {
    _focus.unfocus();
  }

  /// Place le curseur dans le champ de saisie.
  void requestFocus() {
    if (!mounted || !widget.enabled || _recording) return;
    if (_showEmoji || _showAttachActions) {
      setState(() {
        _showEmoji = false;
        _emojiPanelReady = false;
        _showAttachActions = false;
      });
    }
    _focus.requestFocus();
  }

  /// Insère [text] dans le champ (à la position du curseur ou à la fin).
  void pasteText(String text) {
    if (!mounted || text.isEmpty) return;
    final ctrl = widget.controller;
    final value = ctrl.value;
    final selection = value.selection;
    final current = value.text;
    final start = selection.isValid ? selection.start : current.length;
    final end = selection.isValid ? selection.end : current.length;
    final safeStart = start.clamp(0, current.length);
    final safeEnd = end.clamp(0, current.length);
    final next = current.replaceRange(safeStart, safeEnd, text);
    ctrl.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: safeStart + text.length),
    );
    requestFocus();
  }

  void _onTextChanged() {
    if (mounted) setState(() {});
  }

  void _toggleEmoji() {
    setState(() {
      _showAttachActions = false;
      _showEmoji = !_showEmoji;
      if (!_showEmoji) _emojiPanelReady = false;
      _error = null;
    });
    if (_showEmoji) {
      _focus.unfocus();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_showEmoji) return;
        setState(() => _emojiPanelReady = true);
      });
    } else {
      _focus.requestFocus();
    }
  }

  void _toggleAttachActions() {
    if (!widget.enabled || widget.sending || _recording) return;
    setState(() {
      _showEmoji = false;
      _emojiPanelReady = false;
      _showAttachActions = !_showAttachActions;
      _error = null;
    });
  }

  void _runAttach(Future<void> Function() action) {
    setState(() => _showAttachActions = false);
    unawaited(action());
  }

  void _insertEmoji(String emoji) {
    final ctrl = widget.controller;
    final value = ctrl.value;
    final selection = value.selection;
    final current = value.text;
    final start = selection.isValid ? selection.start : current.length;
    final end = selection.isValid ? selection.end : current.length;
    final safeStart = start.clamp(0, current.length);
    final safeEnd = end.clamp(0, current.length);
    final next = current.replaceRange(safeStart, safeEnd, emoji);
    ctrl.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: safeStart + emoji.length),
    );
  }

  static const _quickEmojis = <String>[
    "😀",
    "😂",
    "🥰",
    "😍",
    "👍",
    "🙏",
    "🔥",
    "🎉",
    "😊",
    "😎",
    "😢",
    "🤔",
    "👏",
    "❤️",
    "✅",
    "👋",
  ];

  Future<void> _addImageFile(XFile file) async {
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) return;
    final name = file.name.trim().isNotEmpty
        ? file.name
        : "image_${DateTime.now().millisecondsSinceEpoch}.jpg";
    _pending.add(
      PendingAttachment(
        kind: PendingAttachmentKind.image,
        bytes: bytes,
        filename: name,
        mimeType: file.mimeType,
      ),
    );
  }

  Future<void> _pickImages() async {
    setState(() => _error = null);
    try {
      final picker = ImagePicker();
      final files = await picker.pickMultiImage(
        maxWidth: 1920,
        imageQuality: 85,
      );
      if (files.isEmpty) return;
      for (final file in files) {
        await _addImageFile(file);
      }
      setState(() {});
      requestFocus();
    } catch (e) {
      setState(() => _error = "Impossible d'ajouter l'image : $e");
    }
  }

  Future<void> _takePhoto() async {
    if (!widget.enabled || widget.sending || _recording) return;
    setState(() => _error = null);
    try {
      final picker = ImagePicker();
      final file = await picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1920,
        imageQuality: 85,
        preferredCameraDevice: CameraDevice.rear,
      );
      if (file == null) return;
      await _addImageFile(file);
      setState(() {});
      requestFocus();
    } catch (e) {
      setState(() => _error = "Impossible de prendre la photo : $e");
    }
  }

  Future<void> _pickPdf() async {
    setState(() => _error = null);
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ["pdf"],
        withData: true,
        allowMultiple: true,
      );
      if (result == null || result.files.isEmpty) return;
      for (final file in result.files) {
        final bytes = file.bytes;
        if (bytes == null || bytes.isEmpty) continue;
        final name = file.name.trim().isNotEmpty
            ? file.name
            : "document_${DateTime.now().millisecondsSinceEpoch}.pdf";
        _pending.add(
          PendingAttachment(
            kind: PendingAttachmentKind.pdf,
            bytes: Uint8List.fromList(bytes),
            filename: name.endsWith(".pdf") ? name : "$name.pdf",
            mimeType: "application/pdf",
          ),
        );
      }
      setState(() {});
      requestFocus();
    } catch (e) {
      setState(() => _error = "Impossible d'ajouter le PDF : $e");
    }
  }

  Future<String> _recordPath() async {
    if (foundation.kIsWeb) {
      return "voice_${DateTime.now().millisecondsSinceEpoch}.webm";
    }
    final dir = await getTemporaryDirectory();
    return p.join(
      dir.path,
      "voice_${DateTime.now().millisecondsSinceEpoch}.m4a",
    );
  }

  Future<void> _startRecording() async {
    if (!widget.enabled || widget.sending || _recording) return;
    setState(() => _error = null);

    try {
      final allowed = await _recorder.hasPermission();
      if (!allowed) {
        setState(() => _error = "Autorisez le micro pour enregistrer un audio.");
        return;
      }
      final path = await _recordPath();
      var encoder =
          foundation.kIsWeb ? AudioEncoder.opus : AudioEncoder.aacLc;
      if (!await _recorder.isEncoderSupported(encoder)) {
        encoder = AudioEncoder.wav;
      }
      if (!await _recorder.isEncoderSupported(encoder)) {
        encoder = AudioEncoder.aacLc;
      }
      final ext = switch (encoder) {
        AudioEncoder.wav => "wav",
        AudioEncoder.opus => "webm",
        _ => foundation.kIsWeb ? "webm" : "m4a",
      };
      final recordPath = foundation.kIsWeb
          ? "voice_${DateTime.now().millisecondsSinceEpoch}.$ext"
          : path.endsWith(".$ext")
              ? path
              : "${path.substring(0, path.lastIndexOf('.'))}.$ext";
      await _recorder.start(
        RecordConfig(encoder: encoder, bitRate: 128000, numChannels: 1),
        path: recordPath,
      );
      _recordStartedAt = DateTime.now();
      _recordElapsed = Duration.zero;
      _recordTick?.cancel();
      _recordTick = Timer.periodic(const Duration(seconds: 1), (_) {
        final started = _recordStartedAt;
        if (started == null || !mounted) return;
        setState(() => _recordElapsed = DateTime.now().difference(started));
      });
      setState(() {
        _recording = true;
        _showEmoji = false;
        _emojiPanelReady = false;
        _showAttachActions = false;
      });
    } catch (e) {
      setState(() => _error = "Enregistrement impossible : $e");
    }
  }

  /// Arrête l'enregistrement et envoie tout de suite (bouton mic → send).
  Future<void> _stopRecordingAndSend() async {
    if (!_recording || widget.sending) return;
    await _stopRecordingAndAttach();
    if (!mounted) return;
    if (_canSend) {
      await _submit();
    }
  }

  Future<void> _cancelRecording() async {
    try {
      if (await _recorder.isRecording()) {
        await _recorder.stop();
      }
    } catch (_) {}
    _recordTick?.cancel();
    setState(() {
      _recording = false;
      _recordStartedAt = null;
      _recordElapsed = Duration.zero;
    });
  }

  Future<void> _stopRecordingAndAttach() async {
    try {
      final started = _recordStartedAt;
      final path = await _recorder.stop();
      _recordTick?.cancel();
      final durationMs = started == null
          ? null
          : DateTime.now().difference(started).inMilliseconds;
      setState(() {
        _recording = false;
        _recordStartedAt = null;
        _recordElapsed = Duration.zero;
      });
      if (path == null || path.isEmpty) {
        setState(() => _error = "Aucun audio enregistré.");
        return;
      }
      final file = XFile(path);
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) {
        setState(() => _error = "Audio vide, réessayez.");
        return;
      }
      final lower = path.toLowerCase();
      final filename = lower.contains("/") || lower.contains("\\")
          ? p.basename(path)
          : (lower.endsWith(".wav")
              ? "audio_${DateTime.now().millisecondsSinceEpoch}.wav"
              : lower.endsWith(".webm") || lower.endsWith(".opus")
                  ? "audio_${DateTime.now().millisecondsSinceEpoch}.webm"
                  : "audio_${DateTime.now().millisecondsSinceEpoch}.m4a");
      final mime = filename.endsWith(".wav")
          ? "audio/wav"
          : filename.endsWith(".webm")
              ? "audio/webm"
              : "audio/mp4";
      setState(() {
        _pending.add(
          PendingAttachment(
            kind: PendingAttachmentKind.audio,
            bytes: bytes,
            filename: filename,
            mimeType: mime,
            durationMs: durationMs,
          ),
        );
      });
    } catch (e) {
      setState(() {
        _recording = false;
        _error = "Arrêt de l'enregistrement impossible : $e";
      });
    }
  }

  Future<void> _submit() async {
    if (!_canSend) return;
    final text = widget.controller.text.trim();
    final attachments = List<PendingAttachment>.from(_pending);
    setState(() {
      _pending.clear();
      _showEmoji = false;
      _emojiPanelReady = false;
      _showAttachActions = false;
      _error = null;
    });
    widget.controller.clear();
    await widget.onSend(text, attachments);
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, "0");
    final s = d.inSeconds.remainder(60).toString().padLeft(2, "0");
    return "$m:$s";
  }

  IconData _pendingIcon(PendingAttachmentKind kind) {
    switch (kind) {
      case PendingAttachmentKind.image:
        return Icons.image_outlined;
      case PendingAttachmentKind.pdf:
        return Icons.picture_as_pdf_outlined;
      case PendingAttachmentKind.audio:
        return Icons.mic_none_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Un seul bouton d'action : mic → send (en enregistrement ou contenu prêt).
    final showSend = _recording || _canSend || widget.sending;

    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_error != null)
            Material(
              color: Colors.red.shade50,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: Colors.red.shade800,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      onPressed: () => setState(() => _error = null),
                      icon: const Icon(Icons.close, size: 18),
                    ),
                  ],
                ),
              ),
            ),
          if (_pending.isNotEmpty)
            Container(
              width: double.infinity,
              color: EteyeloColors.chatInputBar,
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var i = 0; i < _pending.length; i++)
                    InputChip(
                      avatar: Icon(_pendingIcon(_pending[i].kind), size: 18),
                      label: Text(
                        _pending[i].kind == PendingAttachmentKind.audio
                            ? "Audio${_pending[i].durationMs != null ? " (${(_pending[i].durationMs! / 1000).round()}s)" : ""}"
                            : _pending[i].filename,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onDeleted: widget.sending
                          ? null
                          : () => setState(() => _pending.removeAt(i)),
                    ),
                ],
              ),
            ),
          Builder(
            builder: (context) {
              final links = findLinkMatches(widget.controller.text);
              if (links.isEmpty) return const SizedBox.shrink();
              return Container(
                width: double.infinity,
                color: EteyeloColors.chatInputBar,
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    for (final m in links.take(4))
                      ActionChip(
                        avatar: Icon(
                          m.kind == LinkMatchKind.url
                              ? Icons.link_rounded
                              : Icons.phone_rounded,
                          size: 16,
                          color: EteyeloColors.primaryDark,
                        ),
                        label: Text(
                          m.display,
                          style: const TextStyle(
                            color: EteyeloColors.primaryDark,
                            decoration: TextDecoration.underline,
                            decorationColor: EteyeloColors.primaryDark,
                            fontWeight: FontWeight.w600,
                            fontSize: 12.5,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        backgroundColor: const Color(0xFFE8F0FE),
                        side: BorderSide(
                          color: EteyeloColors.primary.withValues(alpha: 0.25),
                        ),
                        onPressed: () => showLinkActions(context, m),
                      ),
                  ],
                ),
              );
            },
          ),
          if (_recording)
            Container(
              width: double.infinity,
              color: EteyeloColors.chatInputBar,
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Row(
                children: [
                  const Icon(Icons.fiber_manual_record, color: Colors.red, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    "Enregistrement ${_formatDuration(_recordElapsed)}",
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFB91C1C),
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: _cancelRecording,
                    child: const Text("Annuler"),
                  ),
                ],
              ),
            ),
          AnimatedSize(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            alignment: Alignment.bottomCenter,
            child: _showAttachActions
                ? Container(
                    width: double.infinity,
                    color: EteyeloColors.chatInputBar,
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        _AttachActionChip(
                          icon: Icons.photo_camera_rounded,
                          label: "Photo",
                          color: const Color(0xFF0EA5E9),
                          delayMs: 0,
                          onTap: () => _runAttach(_takePhoto),
                        ),
                        const SizedBox(width: 10),
                        _AttachActionChip(
                          icon: Icons.image_rounded,
                          label: "Galerie",
                          color: const Color(0xFF8B5CF6),
                          delayMs: 40,
                          onTap: () => _runAttach(_pickImages),
                        ),
                        const SizedBox(width: 10),
                        _AttachActionChip(
                          icon: Icons.picture_as_pdf_rounded,
                          label: "PDF",
                          color: const Color(0xFFEF4444),
                          delayMs: 80,
                          onTap: () => _runAttach(_pickPdf),
                        ),
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          Container(
            color: EteyeloColors.chatInputBar,
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        IconButton(
                          tooltip: "Emojis",
                          style: IconButton.styleFrom(
                            hoverColor: Colors.transparent,
                            highlightColor: Colors.transparent,
                            splashFactory: NoSplash.splashFactory,
                          ),
                          icon: Icon(
                            _showEmoji
                                ? Icons.keyboard_alt_outlined
                                : Icons.emoji_emotions_outlined,
                            color: _showEmoji
                                ? EteyeloColors.primary
                                : Colors.grey.shade500,
                          ),
                          onPressed: !widget.enabled || _recording
                              ? null
                              : _toggleEmoji,
                        ),
                        Expanded(
                          child: Theme(
                            data: Theme.of(context).copyWith(
                              hoverColor: Colors.transparent,
                              splashColor: Colors.transparent,
                              highlightColor: Colors.transparent,
                            ),
                            child: TextField(
                            controller: widget.controller,
                            focusNode: _focus,
                            autofocus: widget.autofocus,
                            enabled: widget.enabled && !_recording,
                            enableInteractiveSelection: true,
                            cursorColor: EteyeloColors.primary,
                            contextMenuBuilder: (context, editableTextState) {
                              return AdaptiveTextSelectionToolbar.editableText(
                                editableTextState: editableTextState,
                              );
                            },
                            decoration: InputDecoration(
                              hintText: _recording
                                  ? "Enregistrement en cours…"
                                  : widget.hintText,
                              hintStyle: const TextStyle(
                                color: EteyeloColors.bubbleMeta,
                                fontWeight: FontWeight.w400,
                              ),
                              filled: true,
                              fillColor: Colors.white,
                              hoverColor: Colors.transparent,
                              focusColor: Colors.transparent,
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              disabledBorder: InputBorder.none,
                              errorBorder: InputBorder.none,
                              focusedErrorBorder: InputBorder.none,
                              contentPadding:
                                  const EdgeInsets.symmetric(vertical: 12),
                            ),
                            minLines: 1,
                            maxLines: 5,
                            textCapitalization: TextCapitalization.sentences,
                            onTap: () {
                              if (_showEmoji || _showAttachActions) {
                                setState(() {
                                  _showEmoji = false;
                                  _emojiPanelReady = false;
                                  _showAttachActions = false;
                                });
                              }
                            },
                            ),
                            ),
                        ),
                        IconButton(
                          tooltip: "Joindre",
                          style: IconButton.styleFrom(
                            hoverColor: Colors.transparent,
                            highlightColor: Colors.transparent,
                            splashFactory: NoSplash.splashFactory,
                          ),
                          icon: AnimatedRotation(
                            turns: _showAttachActions ? 0.125 : 0,
                            duration: const Duration(milliseconds: 220),
                            child: Icon(
                              _showAttachActions
                                  ? Icons.close_rounded
                                  : Icons.add_circle_outline_rounded,
                              color: _showAttachActions
                                  ? EteyeloColors.primary
                                  : Colors.grey.shade500,
                            ),
                          ),
                          onPressed: !widget.enabled ||
                                  widget.sending ||
                                  _recording
                              ? null
                              : _toggleAttachActions,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Material(
                  color: _recording
                      ? const Color(0xFFDC2626)
                      : EteyeloColors.primaryDark,
                  shape: const CircleBorder(),
                  elevation: 1,
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: !widget.enabled || widget.sending
                        ? null
                        : _recording
                            ? _stopRecordingAndSend
                            : _canSend
                                ? _submit
                                : _startRecording,
                    child: SizedBox(
                      width: 48,
                      height: 48,
                      child: Center(
                        child: widget.sending
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Icon(
                                showSend
                                    ? Icons.send_rounded
                                    : Icons.mic_none_rounded,
                                color: Colors.white,
                                size: 22,
                              ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: !_showEmoji
                ? const SizedBox.shrink()
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: double.infinity,
                        color: EteyeloColors.chatInputBar,
                        padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              for (final e in _quickEmojis)
                                InkWell(
                                  onTap: () => _insertEmoji(e),
                                  borderRadius: BorderRadius.circular(8),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 4,
                                    ),
                                    child: Text(e, style: const TextStyle(fontSize: 24)),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      SizedBox(
                        height: 240,
                        child: _emojiPanelReady
                            ? EmojiPicker(
                                textEditingController: widget.controller,
                                onBackspacePressed: () {
                                  final text = widget.controller.text;
                                  if (text.isEmpty) return;
                                  final chars = text.characters;
                                  final keep =
                                      chars.take(chars.length - 1).toString();
                                  widget.controller
                                    ..text = keep
                                    ..selection = TextSelection.collapsed(
                                      offset: keep.length,
                                    );
                                },
                                config: Config(
                                  height: 240,
                                  checkPlatformCompatibility: false,
                                  emojiViewConfig: EmojiViewConfig(
                                    emojiSizeMax: 26,
                                    backgroundColor: EteyeloColors.chatInputBar,
                                    recentsLimit: 28,
                                  ),
                                  categoryViewConfig: const CategoryViewConfig(
                                    initCategory: Category.SMILEYS,
                                    backgroundColor: EteyeloColors.chatInputBar,
                                    indicatorColor: EteyeloColors.primary,
                                    iconColorSelected: EteyeloColors.primary,
                                  ),
                                  bottomActionBarConfig:
                                      const BottomActionBarConfig(
                                    enabled: false,
                                  ),
                                  searchViewConfig: const SearchViewConfig(
                                    backgroundColor: EteyeloColors.chatInputBar,
                                  ),
                                ),
                              )
                            : const Center(
                                child: SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
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

class _AttachActionChip extends StatefulWidget {
  const _AttachActionChip({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.delayMs = 0,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final int delayMs;

  @override
  State<_AttachActionChip> createState() => _AttachActionChipState();
}

class _AttachActionChipState extends State<_AttachActionChip>
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
      begin: const Offset(0, 0.45),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
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
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Material(
              color: widget.color,
              shape: const CircleBorder(),
              elevation: 2,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: widget.onTap,
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: Icon(widget.icon, color: Colors.white, size: 22),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              widget.label,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Color(0xFF475569),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
