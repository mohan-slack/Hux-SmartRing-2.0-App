/// First-run privacy notice (DPDP-style standalone notice): what HUX
/// uses, why, where it goes, your rights, and an 18+ confirmation.
/// Shown again whenever [PrivacyNotice.noticeVersion] changes.
library;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/legal/privacy_notice.dart';
import '../../theme/hux_page.dart';
import '../../theme/hux_tokens.dart';
import '../../theme/hux_ui.dart';

class PrivacyConsentScreen extends StatefulWidget {
  final Future<void> Function() onAgree;

  /// "Not now": signs out (HUX can't run without these basics).
  final Future<void> Function() onDecline;

  const PrivacyConsentScreen({super.key, required this.onAgree, required this.onDecline});

  @override
  State<PrivacyConsentScreen> createState() => _PrivacyConsentScreenState();
}

class _PrivacyConsentScreenState extends State<PrivacyConsentScreen> {
  bool _adult = false;
  bool _busy = false;

  Future<void> _run(Future<void> Function() f) async {
    setState(() => _busy = true);
    try {
      await f();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text("That didn't work — please try again.")));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(HuxSpacing.lg, HuxSpacing.lg, HuxSpacing.lg, HuxSpacing.xl),
          children: [
            const HuxHeroCard(
              icon: Icons.verified_user_rounded,
              color: HuxColors.accentPurple,
              eyebrow: 'Privacy first',
              title: 'Your data, your choice',
              subtitle: 'Before you start, here is exactly what ${LegalConfig.appName} uses and why. '
                  'Optional items only happen when you turn that feature on.',
            ),
            const SizedBox(height: HuxSpacing.xl),
            const HuxSectionTitle('What HUX uses', icon: Icons.inventory_2_outlined, iconColor: HuxColors.accentPurple),
            const DataUseList(),
            const SizedBox(height: HuxSpacing.lg),
            const HuxSectionTitle('Never', icon: Icons.block_rounded, iconColor: HuxColors.rundown),
            HuxCard(
              child: Column(
                children: [for (final line in PrivacyNotice.neverDone) _Bullet(line, icon: Icons.block_rounded, color: HuxColors.rundown)],
              ),
            ),
            const SizedBox(height: HuxSpacing.lg),
            const HuxSectionTitle('Your rights', icon: Icons.gavel_rounded, iconColor: HuxColors.recharged),
            HuxCard(
              child: Column(
                children: [for (final line in PrivacyNotice.rights) _Bullet(line, icon: Icons.check_circle_rounded, color: HuxColors.recharged)],
              ),
            ),
            const SizedBox(height: HuxSpacing.md),
            Text(
              '${LegalConfig.appName} gives wellness insights, not medical advice. It is not a medical device.',
              style: text.bodySmall?.copyWith(color: HuxColors.mutedText),
            ),
            Wrap(
              spacing: HuxSpacing.sm,
              children: [
                TextButton(
                  onPressed: () => openLegalLink(context, LegalConfig.privacyPolicyUrl),
                  child: const Text('Full privacy policy'),
                ),
                TextButton(
                  onPressed: () => openLegalLink(context, LegalConfig.termsUrl),
                  child: const Text('Terms of use'),
                ),
              ],
            ),
            HuxCard(
              padding: const EdgeInsets.symmetric(horizontal: HuxSpacing.sm, vertical: HuxSpacing.xs),
              child: CheckboxListTile(
                value: _adult,
                onChanged: _busy ? null : (v) => setState(() => _adult = v ?? false),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                title: const Text('I am ${LegalConfig.minAge} or older'),
                subtitle: const Text('By tapping Agree you accept the Terms of use and the Privacy policy.'),
              ),
            ),
            const SizedBox(height: HuxSpacing.lg),
            SizedBox(
              height: 52,
              child: FilledButton(
                onPressed: _adult && !_busy ? () => _run(widget.onAgree) : null,
                child: const Text('Agree & continue'),
              ),
            ),
            TextButton(
              onPressed: _busy ? null : () => _run(widget.onDecline),
              child: const Text('Not now (sign out)'),
            ),
          ],
        ),
      ),
    );
  }
}

/// The itemised "what / why / where" list, shared with Privacy & account.
class DataUseList extends StatelessWidget {
  const DataUseList({super.key});

  static (IconData, Color) _look(String what) {
    final w = what.toLowerCase();
    if (w.contains('email')) return (Icons.alternate_email_rounded, HuxColors.accentIndigo);
    if (w.contains('health')) return (Icons.monitor_heart_outlined, HuxColors.ringHeart);
    if (w.contains('photo')) return (Icons.photo_camera_outlined, HuxColors.ringFood);
    if (w.contains('city')) return (Icons.location_city_rounded, HuxColors.ringSteps);
    if (w.contains('report')) return (Icons.flag_outlined, HuxColors.stretched);
    if (w.contains('count')) return (Icons.numbers_rounded, HuxColors.mutedText);
    if (w.contains('coach')) return (Icons.chat_bubble_outline_rounded, HuxColors.ringCharge);
    return (Icons.edit_note_rounded, HuxColors.accentPurple);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return HuxCard(
      padding: const EdgeInsets.symmetric(horizontal: HuxSpacing.md, vertical: HuxSpacing.xs),
      child: Column(
        children: [
          for (var i = 0; i < PrivacyNotice.uses.length; i++) ...[
            if (i > 0) const Divider(height: 1, color: HuxColors.hairline),
            Builder(builder: (context) {
              final u = PrivacyNotice.uses[i];
              final (icon, color) = _look(u.what);
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: HuxSpacing.md),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    HuxIconBadge(icon: icon, color: color, size: 36),
                    const SizedBox(width: HuxSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: Text(u.what, style: text.titleSmall?.copyWith(fontWeight: FontWeight.w600))),
                              if (u.optional) const HuxPill(label: 'Optional', color: HuxColors.accentPink),
                            ],
                          ),
                          const SizedBox(height: HuxSpacing.xs),
                          Text('Why: ${u.why}', style: text.bodySmall),
                          Text('Where: ${u.where}', style: text.bodySmall?.copyWith(color: HuxColors.mutedText)),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  final String text;
  final IconData icon;
  final Color color;
  const _Bullet(this.text, {required this.icon, required this.color});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: HuxSpacing.xs),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: HuxSpacing.sm),
            Expanded(child: Text(text, style: Theme.of(context).textTheme.bodySmall)),
          ],
        ),
      );
}

/// Opens a policy page in the browser; shows the address if it can't.
Future<void> openLegalLink(BuildContext context, String url) async {
  var ok = false;
  try {
    ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  } catch (_) {
    ok = false;
  }
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Open $url in your browser')));
  }
}
