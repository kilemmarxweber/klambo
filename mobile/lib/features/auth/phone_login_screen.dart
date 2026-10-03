import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:klambo_messagerie/core/app_theme.dart";
import "package:klambo_messagerie/core/config.dart";
import "package:klambo_messagerie/core/country_dial_codes.dart";
import "package:klambo_messagerie/core/l10n.dart";
import "package:klambo_messagerie/features/auth/session_provider.dart";
import "package:klambo_messagerie/widgets/country_code_picker.dart";
import "package:shared_preferences/shared_preferences.dart";

class PhoneLoginScreen extends ConsumerStatefulWidget {
  const PhoneLoginScreen({super.key, this.changeContact = false});

  /// Ouvert depuis les paramètres : la session actuelle reste
  /// tant que le nouveau numéro n’est pas confirmé.
  final bool changeContact;

  @override
  ConsumerState<PhoneLoginScreen> createState() => _PhoneLoginScreenState();
}

class _PhoneLoginScreenState extends ConsumerState<PhoneLoginScreen> {
  static const _prefsCountryKey = "klambo_phone_country_iso";

  final _phoneCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  final _apiCtrl = TextEditingController();
  final _otpFocus = FocusNode();
  CountryDial _country = countryByIso(kDefaultCountryIso);
  bool _otpSent = false;
  bool _busy = false;
  bool _showConfig = false;
  String? _error;
  String? _hint;
  String? _configSavedHint;

  @override
  void initState() {
    super.initState();
    _apiCtrl.text = AppConfig.apiBaseUrl;
    _loadSavedCountry();
  }

  Future<void> _loadSavedCountry() async {
    final prefs = await SharedPreferences.getInstance();
    final iso = prefs.getString(_prefsCountryKey);
    if (iso == null || iso.isEmpty) return;
    if (!mounted) return;
    setState(() => _country = countryByIso(iso));
  }

  Future<void> _persistCountry(CountryDial country) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsCountryKey, country.iso2);
  }

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _codeCtrl.dispose();
    _apiCtrl.dispose();
    _otpFocus.dispose();
    super.dispose();
  }

  String get _fullPhone => composeE164(
        dialCode: _country.dialCode,
        nationalInput: _phoneCtrl.text,
      );

  String? get _currentPhone {
    final user = ref.read(sessionProvider).me?["user"];
    if (user is! Map) return null;
    return user["telephone"]?.toString() ??
        user["phone"]?.toString() ??
        user["phoneNumber"]?.toString();
  }

  String _digits(String? value) =>
      (value ?? "").replaceAll(RegExp(r"\D"), "");

  bool get _sameAsCurrent {
    final current = _digits(_currentPhone);
    if (current.isEmpty) return false;
    return _digits(_fullPhone) == current;
  }

  String get _langCode {
    switch (ref.read(localeProvider).lang) {
      case AppLang.en:
        return "en";
      case AppLang.pt:
        return "pt";
      case AppLang.fr:
        return "fr";
    }
  }

  Future<void> _pickCountry(L10n l10n) async {
    final picked = await showCountryDialPicker(
      context: context,
      selected: _country,
      langCode: _langCode,
      title: l10n.countryCode,
      searchHint: l10n.searchCountry,
    );
    if (picked == null || !mounted) return;
    setState(() => _country = picked);
    await _persistCountry(picked);
  }

  Future<void> _saveApiSource(L10n l10n) async {
    final raw = _apiCtrl.text.trim();
    if (raw.isEmpty) {
      setState(() => _error = l10n.sourceRequired);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _configSavedHint = null;
    });
    try {
      await ref.read(apiClientProvider).setApiBaseUrl(raw);
      setState(() {
        _apiCtrl.text = AppConfig.apiBaseUrl;
        _configSavedHint = l10n.sourceSaved(AppConfig.apiBaseUrl);
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _applyPreset(String url, L10n l10n) async {
    _apiCtrl.text = url;
    await _saveApiSource(l10n);
  }

  bool _validateNational(L10n l10n) {
    final digits = _phoneCtrl.text.replaceAll(RegExp(r"\D"), "");
    if (digits.length < 6) {
      setState(() => _error = l10n.phoneNationalInvalid);
      return false;
    }
    return true;
  }

  Future<void> _requestOtp(L10n l10n) async {
    if (!_validateNational(l10n)) return;
    if (widget.changeContact && _sameAsCurrent) {
      setState(() => _error = l10n.changeContactSame);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final auth = ref.read(authRepositoryProvider);
      final full = _fullPhone;
      final res = await auth.requestOtp(full);
      final devCode = res["devCode"]?.toString();
      if (devCode != null && devCode.isNotEmpty) {
        _codeCtrl.text = devCode;
      }
      final phone = res["maskedPhone"]?.toString() ?? full;
      final channel = res["channel"]?.toString() ?? "sms";
      setState(() {
        _otpSent = true;
        _hint = l10n.otpSent(phone, channel);
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _otpFocus.requestFocus();
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _verify() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      TextInput.finishAutofillContext(shouldSave: true);
      final auth = ref.read(authRepositoryProvider);
      final data = await auth.verifyOtp(
        phone: _fullPhone,
        code: _codeCtrl.text.trim(),
      );
      await ref.read(sessionProvider.notifier).applyAuthPayload(data);
      if (!mounted || !widget.changeContact) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _busy = false);
    }
  }

  Widget _langChip(AppLang lang, String label, AppLang current) {
    final selected = current == lang;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: _busy
          ? null
          : (_) async {
              await ref.read(localeProvider).setLang(lang);
              setState(() {});
            },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = ref.watch(l10nProvider);
    final lang = ref.watch(localeProvider).lang;
    final scheme = Theme.of(context).colorScheme;

    final presets = <(String, String)>[
      (l10n.presetProd, AppConfig.productionBaseUrl),
      (l10n.presetEmulator, "http://10.0.2.2:3000"),
      (l10n.presetLocalhost, "http://localhost:3000"),
    ];

    return Scaffold(
      appBar: widget.changeContact
          ? AppBar(
              title: Text(l10n.changeContact),
            )
          : null,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  tooltip: l10n.config,
                  onPressed: () => setState(() {
                    _showConfig = !_showConfig;
                    if (_showConfig) {
                      _apiCtrl.text = AppConfig.apiBaseUrl;
                    }
                  }),
                  icon: Icon(
                    _showConfig ? Icons.close : Icons.settings_outlined,
                    color: ChatPalette.subtitle(context),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                widget.changeContact ? l10n.changeContact : l10n.appName,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: EteyeloColors.primary,
                    ),
              ),
              const SizedBox(height: 6),
              Text(
                widget.changeContact
                    ? l10n.changeContactHint
                    : l10n.messaging,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: scheme.onSurface.withValues(alpha: 0.75),
                    ),
              ),
              if (widget.changeContact &&
                  (_currentPhone?.trim().isNotEmpty ?? false)) ...[
                const SizedBox(height: 8),
                Text(
                  "${l10n.changeContactCurrent} : ${_currentPhone!.trim()}",
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                child: _showConfig
                    ? KeyedSubtree(
                        key: const ValueKey("config"),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const SizedBox(height: 24),
                            Text(
                              l10n.language,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                _langChip(AppLang.fr, "FR", lang),
                                _langChip(AppLang.en, "EN", lang),
                                _langChip(AppLang.pt, "PT", lang),
                              ],
                            ),
                            const SizedBox(height: 20),
                            Text(
                              l10n.sourceTitle,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _apiCtrl,
                              keyboardType: TextInputType.url,
                              autocorrect: false,
                              autofillHints: const [AutofillHints.url],
                              decoration: InputDecoration(
                                labelText: l10n.apiUrlLabel,
                                hintText: l10n.apiUrlHint,
                                helperText: l10n.apiUrlHelp,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final (label, url) in presets)
                                  ActionChip(
                                    label: Text(label),
                                    onPressed: _busy
                                        ? null
                                        : () => _applyPreset(url, l10n),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            OutlinedButton(
                              onPressed:
                                  _busy ? null : () => _saveApiSource(l10n),
                              child: Text(l10n.saveSource),
                            ),
                            if (_configSavedHint != null) ...[
                              const SizedBox(height: 8),
                              Text(
                                _configSavedHint!,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: const Color(0xFF16A34A),
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                            ],
                          ],
                        ),
                      )
                    : KeyedSubtree(
                        key: const ValueKey("auth"),
                        child: AutofillGroup(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const SizedBox(height: 8),
                              Text(
                                AppConfig.apiBaseUrl,
                                textAlign: TextAlign.center,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: ChatPalette.subtitle(context),
                                    ),
                              ),
                              const SizedBox(height: 28),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  CountryDialButton(
                                    country: _country,
                                    enabled: !_otpSent && !_busy,
                                    onTap: () => _pickCountry(l10n),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: SizedBox(
                                      height: kPhoneFieldHeight,
                                      child: TextField(
                                        controller: _phoneCtrl,
                                        keyboardType: TextInputType.phone,
                                        textInputAction: TextInputAction.next,
                                        autofillHints: const [
                                          AutofillHints
                                              .telephoneNumberNational,
                                        ],
                                        inputFormatters: [
                                          FilteringTextInputFormatter.allow(
                                            RegExp(r"[0-9\s]"),
                                          ),
                                        ],
                                        style: const TextStyle(fontSize: 16),
                                        decoration: InputDecoration(
                                          hintText: l10n.phoneLabel,
                                          floatingLabelBehavior:
                                              FloatingLabelBehavior.never,
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                            horizontal: 14,
                                            vertical: 16,
                                          ),
                                        ),
                                        enabled: !_otpSent,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              AnimatedSize(
                                duration: const Duration(milliseconds: 220),
                                curve: Curves.easeOutCubic,
                                child: _otpSent
                                    ? Padding(
                                        padding: const EdgeInsets.only(top: 16),
                                        child: TextField(
                                          controller: _codeCtrl,
                                          focusNode: _otpFocus,
                                          // Dernier type Android recommandé pour SMS OTP
                                          // (Autofill / SMS User Consent → oneTimeCode).
                                          keyboardType: TextInputType.number,
                                          textInputAction: TextInputAction.done,
                                          autofillHints: const [
                                            AutofillHints.oneTimeCode,
                                          ],
                                          maxLength: 6,
                                          inputFormatters: [
                                            FilteringTextInputFormatter
                                                .digitsOnly,
                                          ],
                                          onSubmitted: (_) {
                                            if (!_busy) _verify();
                                          },
                                          decoration: InputDecoration(
                                            labelText: l10n.otpLabel,
                                            counterText: "",
                                          ),
                                        ),
                                      )
                                    : const SizedBox.shrink(),
                              ),
                              if (_hint != null) ...[
                                const SizedBox(height: 12),
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: EteyeloColors.primary
                                        .withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: EteyeloColors.primary
                                          .withValues(alpha: 0.28),
                                    ),
                                  ),
                                  child: Text(
                                    _hint!,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                          fontWeight: FontWeight.w600,
                                          color: EteyeloColors.primaryDark,
                                        ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: TextStyle(color: scheme.error)),
              ],
              const Spacer(),
              if (!_showConfig)
                FilledButton(
                  onPressed: _busy
                      ? null
                      : (_otpSent ? _verify : () => _requestOtp(l10n)),
                  child: _busy
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(_otpSent ? l10n.verify : l10n.continueLabel),
                ),
              if (_otpSent && !_showConfig)
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => setState(() {
                            _otpSent = false;
                            _codeCtrl.clear();
                          }),
                  child: Text(l10n.changeNumber),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
