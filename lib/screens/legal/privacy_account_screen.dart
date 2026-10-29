/// Privacy & account: what HUX uses, your choices (coach sharing, meal
/// photos), download a copy, delete data on this phone, delete account,
/// policy links and sign out.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/auth/auth_models.dart';
import '../../core/coach/coach_service.dart';
import '../../core/food/food_log_service.dart';
import '../../core/legal/privacy_notice.dart';
import '../../core/legal/privacy_service.dart';
import '../../theme/hux_page.dart';
import '../../theme/hux_tokens.dart';
import '../../theme/hux_ui.dart';
import 'privacy_consent_screen.dart';
import '../../widgets/text_prompt.dart';

class PrivacyAccountScreen extends StatefulWidget {
  final PrivacyService privacy;
  final CoachService? coach;
  final FoodLogService? foodLog;

  /// After "Delete data on this phone" (the app restarts its first-run).
  final VoidCallback onLocalDataDeleted;

  const PrivacyAccountScreen({
    super.key,
    required this.privacy,
    required this.onLocalDataDeleted,
    this.coach,
    this.foodLog,
  });

  @override
  State<PrivacyAccountScreen> createState() => _PrivacyAccountScreenState();
}

class _PrivacyAccountScreenState extends State<PrivacyAccountScreen> {
  bool? _coachOn;
  bool? _photosOn;
  String? _agreedOn;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final coach = await widget.coach?.hasConsent();
    final photos = await widget.foodLog?.hasPhotoConsent();
    final consent = await widget.privacy.consent();
    if (!mounted) return;
    setState(() {
      _coachOn = coach;
      _photosOn = photos;
      final at = consent?.at.toLocal();
      _agreedOn = at == null ? null : '${at.day}/${at.month}/${at.year}';
    });
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _guarded(Future<void> Function() f, {String error = "That didn't work — please try again."}) async {
    setState(() => _busy = true);
    try {
      await f();
    } catch (e) {
      // AuthException messages are already written for users.
      _snack(e is AuthException ? e.message : error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setCoach(bool on) async {
    if (on) {
      // Turning ON happens in the coach, where the exact summary is shown.
      _snack('Open HUX coach to see what it shares and turn it on.');
      return;
    }
    await _guarded(() async {
      await widget.coach!.withdrawConsent();
      _snack('Coach sharing is off and your chat was deleted.');
      await _load();
    });
  }

  Future<void> _setPhotos(bool on) => _guarded(() async {
        await widget.foodLog!.setPhotoConsent(on);
        await _load();
      });

  Future<void> _download() => _guarded(() async {
        final jsonText = await widget.privacy.exportJson();
        final now = DateTime.now();
        final name = 'hux-data-${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}.json';
        await Share.shareXFiles(
          [XFile.fromData(utf8.encode(jsonText), mimeType: 'application/json', name: name)],
          subject: 'My HUX data',
        );
      }, error: "Couldn't prepare your data. Please try again.");

  Future<bool> _confirm({required String title, required String body, required String action, String? typeToConfirm}) async {
    if (typeToConfirm != null) {
      // Owns its controller (disposed after the closing animation).
      final typed = await showDialog<String>(
        context: context,
        builder: (_) => TextPromptDialog(
          title: title,
          body: body,
          requiredText: typeToConfirm,
          confirmLabel: action,
          confirmColor: HuxColors.rundown,
        ),
      );
      return typed != null && typed.trim().toUpperCase() == typeToConfirm.toUpperCase();
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            style: TextButton.styleFrom(foregroundColor: HuxColors.rundown),
            child: Text(action),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _deleteLocal() async {
    final ok = await _confirm(
      title: 'Delete data on this phone?',
      body: 'This removes your readings, journal, meals, plans, coach chat, answers and reminders '
          'from this phone. Your account stays. Data in Apple Health / Health Connect is not touched.',
      action: 'Delete',
    );
    if (!ok) return;
    await _guarded(() async {
      await widget.privacy.deleteLocalData();
      widget.onLocalDataDeleted();
    });
  }

  Future<void> _deleteAccount() async {
    final ok = await _confirm(
      title: 'Delete your account?',
      body: 'This permanently deletes your ${LegalConfig.appName} account and sign-in, and everything '
          '${LegalConfig.appName} keeps about you on this phone. It can\'t be undone. '
          'Data in Apple Health / Health Connect stays there.',
      action: 'Delete forever',
      typeToConfirm: 'DELETE',
    );
    if (!ok) return;
    var deleted = false;
    await _guarded(() async {
      await widget.privacy.deleteAccount();
      deleted = true;
    }, error: "Couldn't delete your account. Check your internet and try again.");
    // Signed out now: close this screen so the welcome screen shows.
    if (deleted && mounted) Navigator.of(context).popUntil((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    Widget switchRow({
      required IconData icon,
      required Color color,
      required String title,
      required String subtitle,
      required bool? value,
      required ValueChanged<bool> onChanged,
    }) =>
        HuxListRow(
          icon: icon,
          color: color,
          title: title,
          subtitle: subtitle,
          trailing: Switch(value: value ?? false, onChanged: value == null ? null : onChanged),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Privacy & account')),
      body: AbsorbPointer(
        absorbing: _busy,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(HuxSpacing.lg, HuxSpacing.sm, HuxSpacing.lg, HuxSpacing.xxl),
          children: [
            if (_busy) ...[
              const LinearProgressIndicator(),
              const SizedBox(height: HuxSpacing.sm),
            ],
            HuxHeroCard(
              icon: Icons.verified_user_rounded,
              color: HuxColors.accentPurple,
              eyebrow: 'Your data stays yours',
              title: 'Privacy & account',
              subtitle: _agreedOn != null
                  ? 'You agreed to the privacy notice on $_agreedOn.'
                  : 'Your readings, journal and meals live on this phone.',
            ),
            const SizedBox(height: HuxSpacing.xl),
            const HuxSectionTitle('Your choices', icon: Icons.tune_rounded),
            HuxCard(
              padding: const EdgeInsets.symmetric(horizontal: HuxSpacing.md, vertical: HuxSpacing.xs),
              child: Column(
                children: [
                  if (widget.coach != null)
                    switchRow(
                      icon: Icons.chat_bubble_outline_rounded,
                      color: HuxColors.ringCharge,
                      title: 'Share a summary with the HUX coach',
                      subtitle: 'Off = coach stops and your chat is deleted',
                      value: _coachOn,
                      onChanged: _setCoach,
                    ),
                  if (widget.coach != null && widget.foodLog != null)
                    const Divider(height: 1, color: HuxColors.hairline),
                  if (widget.foodLog != null)
                    switchRow(
                      icon: Icons.photo_camera_outlined,
                      color: HuxColors.ringFood,
                      title: 'Analyse meal photos',
                      subtitle: 'Photos go to an AI service for an estimate; not stored by HUX',
                      value: _photosOn,
                      onChanged: _setPhotos,
                    ),
                ],
              ),
            ),
            const SizedBox(height: HuxSpacing.sm),
            Text(
              'Reminders and air & heat alerts can be turned off on their own screens.',
              style: text.bodySmall?.copyWith(color: HuxColors.mutedText),
            ),
            const SizedBox(height: HuxSpacing.xl),
            const HuxSectionTitle('Your data', icon: Icons.folder_outlined),
            HuxCard(
              padding: const EdgeInsets.symmetric(horizontal: HuxSpacing.md, vertical: HuxSpacing.xs),
              child: Column(
                children: [
                  HuxListRow(
                    icon: Icons.download_rounded,
                    color: HuxColors.accentIndigo,
                    title: 'Download my data',
                    subtitle: 'A copy of everything HUX keeps, as a file',
                    onTap: _download,
                  ),
                  const Divider(height: 1, color: HuxColors.hairline),
                  HuxListRow(
                    icon: Icons.phonelink_erase_rounded,
                    color: HuxColors.stretched,
                    title: 'Delete data on this phone',
                    subtitle: 'Keeps your account',
                    onTap: _deleteLocal,
                  ),
                  const Divider(height: 1, color: HuxColors.hairline),
                  HuxListRow(
                    icon: Icons.delete_forever_rounded,
                    color: HuxColors.rundown,
                    title: 'Delete account',
                    subtitle: 'Permanently, with all your data',
                    onTap: _deleteAccount,
                  ),
                ],
              ),
            ),
            const SizedBox(height: HuxSpacing.xl),
            HuxCard(
              padding: const EdgeInsets.symmetric(horizontal: HuxSpacing.md),
              child: Theme(
                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  leading: const HuxIconBadge(icon: Icons.inventory_2_outlined, color: HuxColors.accentPurple, size: 36),
                  title: Text('What HUX uses and why', style: text.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                  childrenPadding: const EdgeInsets.only(bottom: HuxSpacing.md),
                  children: const [DataUseList()],
                ),
              ),
            ),
            const SizedBox(height: HuxSpacing.md),
            const HuxSectionTitle('Your rights', icon: Icons.gavel_rounded, iconColor: HuxColors.recharged),
            HuxCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final r in PrivacyNotice.rights)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: HuxSpacing.xs),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.check_circle_rounded, size: 18, color: HuxColors.recharged),
                          const SizedBox(width: HuxSpacing.sm),
                          Expanded(child: Text(r, style: text.bodySmall)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            Wrap(
              spacing: HuxSpacing.sm,
              children: [
                TextButton(
                  onPressed: () => openLegalLink(context, LegalConfig.privacyPolicyUrl),
                  child: const Text('Privacy policy'),
                ),
                TextButton(
                  onPressed: () => openLegalLink(context, LegalConfig.termsUrl),
                  child: const Text('Terms of use'),
                ),
              ],
            ),
            Text(
              '${LegalConfig.company} · ${LegalConfig.privacyEmail}',
              style: text.bodySmall?.copyWith(color: HuxColors.mutedText),
            ),
          ],
        ),
      ),
    );
  }
}
