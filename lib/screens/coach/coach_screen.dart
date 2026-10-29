/// HUX coach chat: consent first (showing exactly what is shared), then
/// a simple chat with quick questions, on-phone safety cards with
/// tap-to-call help numbers, and controls to clear or stop sharing.
library;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/coach/coach_service.dart';
import '../../core/coach/safety.dart';
import '../../theme/hux_glass.dart';
import '../../theme/hux_tokens.dart';

class CoachScreen extends StatefulWidget {
  final CoachService coach;

  /// True when shown as the Coach tab: transparent background and the
  /// input lifted above the floating nav bar.
  final bool embedded;

  const CoachScreen({super.key, required this.coach, this.embedded = false});

  @override
  State<CoachScreen> createState() => _CoachScreenState();
}

enum _Menu { shared, clear, stop }

class _CoachScreenState extends State<CoachScreen> {
  static const _quick = [
    'What should I do today?',
    'How can I sleep better tonight?',
    'Easy protein ideas for my diet',
    'Make me a simple walking plan for 2 weeks',
    'Why is my HUX Charge low?',
  ];

  final _input = TextEditingController();
  final _scroll = ScrollController();
  bool _loading = true;
  bool _consent = false;
  bool _sending = false;
  List<ChatMessage> _messages = const [];
  List<String>? _shared;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final consent = await widget.coach.hasConsent();
    final history = consent ? await widget.coach.history() : const <ChatMessage>[];
    List<String>? shared;
    if (!consent) shared = (await widget.coach.previewContext()).preview();
    if (!mounted) return;
    setState(() {
      _consent = consent;
      _messages = history;
      _shared = shared;
      _loading = false;
    });
    _toBottom();
  }

  void _toBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  Future<void> _agree() async {
    await widget.coach.giveConsent();
    if (!mounted) return;
    setState(() => _consent = true);
  }

  Future<void> _send(String text) async {
    final t = text.trim();
    if (t.isEmpty || _sending) return;
    _input.clear();
    // Show the message (and any safety card) immediately.
    setState(() {
      _sending = true;
      _messages = [
        ..._messages,
        ChatMessage(role: ChatRole.user, text: t, at: DateTime.now(), safety: SafetyCheck.check(t)?.kind),
      ];
    });
    _toBottom();
    try {
      final updated = await widget.coach.send(t);
      if (!mounted) return;
      setState(() => _messages = updated);
    } on CoachException catch (e) {
      if (!mounted) return;
      if (e.kind == CoachErrorKind.tooLong) {
        setState(() => _messages = _messages.sublist(0, _messages.length - 1));
        _input.text = t;
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _sending = false);
      _toBottom();
    }
  }

  Future<void> _report(int index) async {
    final reason = await showModalBottomSheet<ReportReason>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              title: Text('Report this reply'),
              subtitle: Text('HUX gets this reply and your question to review. Your health numbers are not sent.'),
            ),
            for (final r in ReportReason.values)
              ListTile(title: Text(r.label), onTap: () => Navigator.pop(c, r)),
          ],
        ),
      ),
    );
    if (reason == null) return;
    try {
      final updated = await widget.coach.report(index, reason);
      if (!mounted) return;
      setState(() => _messages = updated);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Thanks — we\'ll review it.')));
    } on CoachException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _retry() async {
    if (_sending) return;
    setState(() => _sending = true);
    _toBottom();
    try {
      final updated = await widget.coach.retryLast();
      if (mounted) setState(() => _messages = updated);
    } on CoachException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _sending = false);
      _toBottom();
    }
  }

  Future<void> _onMenu(_Menu m) async {
    switch (m) {
      case _Menu.shared:
        final lines = (await widget.coach.previewContext()).preview();
        if (!mounted) return;
        await showModalBottomSheet<void>(
          context: context,
          builder: (_) => Padding(
            padding: const EdgeInsets.all(HuxSpacing.lg),
            child: _SharedList(lines: lines),
          ),
        );
      case _Menu.clear:
        await widget.coach.clearHistory();
        if (mounted) setState(() => _messages = const []);
      case _Menu.stop:
        final ok = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('Stop sharing?'),
            content: const Text('The coach will stop, and your chat on this phone will be deleted.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
              TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Stop & delete')),
            ],
          ),
        );
        if (ok != true) return;
        await widget.coach.withdrawConsent();
        final shared = (await widget.coach.previewContext()).preview();
        if (!mounted) return;
        setState(() {
          _consent = false;
          _messages = const [];
          _shared = shared;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: widget.embedded ? Colors.transparent : null,
      appBar: AppBar(
        automaticallyImplyLeading: !widget.embedded,
        title: Row(
          children: [
            const _CoachAvatar(size: 32),
            const SizedBox(width: HuxSpacing.sm),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('HUX coach'),
                Text(_sending ? 'typing…' : 'Your wellness companion',
                    style: Theme.of(context).textTheme.labelSmall),
              ],
            ),
          ],
        ),
        actions: [
          if (_consent)
            PopupMenuButton<_Menu>(
              onSelected: _onMenu,
              itemBuilder: (_) => const [
                PopupMenuItem(value: _Menu.shared, child: Text('What HUX shares')),
                PopupMenuItem(value: _Menu.clear, child: Text('Clear chat')),
                PopupMenuItem(value: _Menu.stop, child: Text('Stop sharing & delete chat')),
              ],
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : !widget.coach.hasBackend
              ? const _Message(text: 'The coach needs the HUX online service, which isn\'t set up in this build yet.')
              : !_consent
                  ? _ConsentView(shared: _shared ?? const [], onAgree: _agree)
                  : _chat(context),
    );
  }

  static const _suggestions = [
    (icon: Icons.wb_sunny_rounded, color: HuxColors.ringSteps, text: 'What should I do today?'),
    (icon: Icons.bedtime_rounded, color: HuxColors.ringSleep, text: 'How can I sleep better tonight?'),
    (icon: Icons.restaurant_rounded, color: HuxColors.ringFood, text: 'Easy protein ideas for my diet'),
    (icon: Icons.directions_walk_rounded, color: HuxColors.ringCharge, text: 'Make me a 2-week walking plan'),
  ];

  Widget _chat(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      children: [
        Expanded(
          child: ListView(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(HuxSpacing.lg, HuxSpacing.sm, HuxSpacing.lg, HuxSpacing.lg),
            children: [
              if (_messages.isEmpty) ...[
                const SizedBox(height: HuxSpacing.xl),
                const Center(child: _CoachAvatar(size: 64)),
                const SizedBox(height: HuxSpacing.md),
                Text('How can I help today?',
                    textAlign: TextAlign.center,
                    style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: HuxSpacing.xs),
                Text('I use your HUX numbers to keep it personal.',
                    textAlign: TextAlign.center, style: text.bodySmall),
                const SizedBox(height: HuxSpacing.xl),
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: HuxSpacing.sm,
                  crossAxisSpacing: HuxSpacing.sm,
                  childAspectRatio: 1.45,
                  children: [
                    for (final q in _suggestions)
                      _SuggestionCard(icon: q.icon, color: q.color, text: q.text, onTap: () => _send(q.text)),
                  ],
                ),
                const SizedBox(height: HuxSpacing.md),
                Wrap(
                  spacing: HuxSpacing.sm,
                  runSpacing: HuxSpacing.sm,
                  alignment: WrapAlignment.center,
                  children: [
                    for (final q in _quick.skip(4)) ActionChip(label: Text(q), onPressed: () => _send(q)),
                  ],
                ),
              ],
              for (final (i, m) in _messages.indexed) ...[
                _Bubble(message: m, onReport: m.role == ChatRole.coach && !m.reported ? () => _report(i) : null),
                if (m.safety != null)
                  _SafetyCardView(
                    card: m.safety == SafetyKind.selfHarm ? SafetyCheck.selfHarmCard : SafetyCheck.emergencyCard,
                  ),
              ],
              if (_sending)
                const _TypingBubble()
              else if (CoachService.awaitingReply(_messages))
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: _retry,
                    icon: const Icon(Icons.refresh_rounded, size: 18, color: HuxColors.rundown),
                    label: const Text('Not delivered · Retry', style: TextStyle(color: HuxColors.rundown)),
                  ),
                ),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            // In the tab, keep the input above the floating nav bar.
            padding: EdgeInsets.fromLTRB(
                HuxSpacing.lg, HuxSpacing.xs, HuxSpacing.lg, widget.embedded ? 96 : HuxSpacing.sm),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(HuxSpacing.lg, 4, 4, 4),
                  decoration: BoxDecoration(
                    color: HuxColors.card,
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(color: HuxColors.glassStroke),
                    boxShadow: const [BoxShadow(color: HuxColors.shadow, blurRadius: 16, offset: Offset(0, 4))],
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _input,
                          minLines: 1,
                          maxLines: 4,
                          maxLength: CoachService.maxMessageChars,
                          textInputAction: TextInputAction.send,
                          onSubmitted: _send,
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(
                            hintText: 'Message your coach…',
                            counterText: '',
                            filled: false,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
                      _SendButton(
                        enabled: !_sending && _input.text.trim().isNotEmpty,
                        onTap: () => _send(_input.text),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: HuxSpacing.xs),
                Text(
                  'AI coach — it can make mistakes. Wellness tips, not medical advice.',
                  textAlign: TextAlign.center,
                  style: text.labelSmall,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// The coach's round gradient avatar with the HUX "H".
class _CoachAvatar extends StatelessWidget {
  final double size;
  const _CoachAvatar({this.size = 32});

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [HuxColors.ringSleep, HuxColors.ringCharge],
          ),
        ),
        child: Text('H',
            style: TextStyle(
              color: HuxColors.onVivid,
              fontWeight: FontWeight.w700,
              fontSize: size * 0.45,
            )),
      );
}

class _SuggestionCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;
  final VoidCallback onTap;

  const _SuggestionCard({required this.icon, required this.color, required this.text, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: HuxColors.card,
      borderRadius: BorderRadius.circular(HuxRadii.card),
      child: InkWell(
        borderRadius: BorderRadius.circular(HuxRadii.card),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(HuxSpacing.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(HuxRadii.card),
            border: Border.all(color: HuxColors.glassStroke),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(icon, color: color, size: 22),
              Text(text,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}

class _SendButton extends StatelessWidget {
  final bool enabled;
  final VoidCallback onTap;
  const _SendButton({required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Send',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: AnimatedContainer(
          duration: HuxMotion.quick,
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: enabled ? null : HuxColors.hairline,
            gradient: enabled
                ? const LinearGradient(colors: [HuxColors.ringCharge, HuxColors.accentPurple])
                : null,
          ),
          child: Icon(Icons.arrow_upward_rounded, color: enabled ? HuxColors.onVivid : HuxColors.mutedText),
        ),
      ),
    );
  }
}

/// Three dots that pulse while the coach is writing.
class _TypingBubble extends StatefulWidget {
  const _TypingBubble();

  @override
  State<_TypingBubble> createState() => _TypingBubbleState();
}

class _TypingBubbleState extends State<_TypingBubble> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: HuxSpacing.xs),
      child: Row(
        children: [
          const _CoachAvatar(),
          const SizedBox(width: HuxSpacing.sm),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: HuxSpacing.md, vertical: 14),
            decoration: BoxDecoration(
              color: HuxColors.card,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: HuxColors.glassStroke),
            ),
            child: AnimatedBuilder(
              animation: _c,
              builder: (_, __) => Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < 3; i++)
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: HuxColors.accentPurple.withValues(
                          alpha: 0.25 + 0.75 * (((_c.value * 3 - i) % 3) < 1 ? 1 - ((_c.value * 3 - i) % 3) : 0),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConsentView extends StatelessWidget {
  final List<String> shared;
  final VoidCallback onAgree;
  const _ConsentView({required this.shared, required this.onAgree});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.all(HuxSpacing.lg),
      children: [
        Text('Your personal coach', style: text.titleLarge),
        const SizedBox(height: HuxSpacing.sm),
        Text(
          'To give advice that fits YOU, the coach needs a short summary of your HUX numbers. '
          'Your message and this summary go to HUX\'s server and an AI service to write the reply. '
          'HUX doesn\'t keep your chat — it stays on this phone.',
          style: text.bodyMedium,
        ),
        const SizedBox(height: HuxSpacing.lg),
        GlassPanel(child: _SharedList(lines: shared)),
        const SizedBox(height: HuxSpacing.md),
        Text(
          'Never shared: your name, email, phone number, location, photos, or minute-by-minute readings.',
          style: text.bodySmall?.copyWith(color: HuxColors.mutedText),
        ),
        const SizedBox(height: HuxSpacing.sm),
        Text(
          'You can stop sharing any time from the menu — that also deletes the chat on this phone.',
          style: text.bodySmall?.copyWith(color: HuxColors.mutedText),
        ),
        const SizedBox(height: HuxSpacing.xl),
        FilledButton(onPressed: onAgree, child: const Text('Agree & start')),
        TextButton(onPressed: () => Navigator.of(context).maybePop(), child: const Text('Not now')),
      ],
    );
  }
}

class _SharedList extends StatelessWidget {
  final List<String> lines;
  const _SharedList({required this.lines});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('What HUX shares with the coach', style: text.titleSmall),
        const SizedBox(height: HuxSpacing.sm),
        for (final l in lines)
          Padding(
            padding: const EdgeInsets.only(bottom: HuxSpacing.xs),
            child: Text('• $l', style: text.bodyMedium),
          ),
      ],
    );
  }
}

class _Bubble extends StatelessWidget {
  final ChatMessage message;

  /// Coach replies only; null hides the report button.
  final VoidCallback? onReport;
  const _Bubble({required this.message, this.onReport});

  @override
  Widget build(BuildContext context) {
    final mine = message.role == ChatRole.user;
    final width = MediaQuery.sizeOf(context).width;
    if (mine) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.only(top: HuxSpacing.sm, bottom: HuxSpacing.xs, left: HuxSpacing.xxl),
          padding: const EdgeInsets.symmetric(horizontal: HuxSpacing.md, vertical: HuxSpacing.sm + 2),
          constraints: BoxConstraints(maxWidth: width * 0.78),
          decoration: const BoxDecoration(
            gradient: LinearGradient(colors: [HuxColors.accentPurple, HuxColors.ringCharge]),
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
              bottomLeft: Radius.circular(20),
              bottomRight: Radius.circular(6),
            ),
          ),
          child: SelectableText(message.text,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: HuxColors.onVivid, height: 1.35)),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: HuxSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CoachAvatar(),
          const SizedBox(width: HuxSpacing.sm),
          Expanded(
            child: Container(
              padding: const EdgeInsets.fromLTRB(HuxSpacing.md, HuxSpacing.md, HuxSpacing.md, HuxSpacing.xs),
              decoration: BoxDecoration(
                color: HuxColors.card,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(6),
                  topRight: Radius.circular(20),
                  bottomLeft: Radius.circular(20),
                  bottomRight: Radius.circular(20),
                ),
                border: Border.all(color: HuxColors.glassStroke),
                boxShadow: const [BoxShadow(color: HuxColors.shadow, blurRadius: 12, offset: Offset(0, 4))],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _FormattedReply(message.text),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (message.reported)
                        Padding(
                          padding: const EdgeInsets.only(bottom: HuxSpacing.sm),
                          child: Text('Reported', style: Theme.of(context).textTheme.labelSmall),
                        )
                      else if (onReport != null)
                        IconButton(
                          tooltip: 'Report this reply',
                          visualDensity: VisualDensity.compact,
                          iconSize: 18,
                          icon: const Icon(Icons.outlined_flag, color: HuxColors.mutedText),
                          onPressed: onReport,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Light formatting for coach replies: paragraphs, "- " / "• " / "1. "
/// lists, and **bold**. Anything else is shown as plain text.
class _FormattedReply extends StatelessWidget {
  final String text;
  const _FormattedReply(this.text);

  static final _bullet = RegExp(r'^\s*([-•*]|\d+[.)])\s+');

  List<TextSpan> _spans(String line, TextStyle? base) {
    final out = <TextSpan>[];
    final parts = line.split('**');
    for (var i = 0; i < parts.length; i++) {
      if (parts[i].isEmpty) continue;
      out.add(TextSpan(
        text: parts[i],
        style: i.isOdd ? base?.copyWith(fontWeight: FontWeight.w700) : base,
      ));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.4);
    final children = <Widget>[];
    for (final raw in text.split('\n')) {
      final line = raw.trimRight();
      if (line.trim().isEmpty) {
        children.add(const SizedBox(height: HuxSpacing.sm));
        continue;
      }
      final m = _bullet.firstMatch(line);
      if (m != null) {
        final marker = m.group(1)!;
        final isNumber = RegExp(r'\d').hasMatch(marker);
        children.add(Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 20,
                child: Text(isNumber ? marker : '•',
                    style: base?.copyWith(color: HuxColors.accentPurple, fontWeight: FontWeight.w700)),
              ),
              Expanded(child: Text.rich(TextSpan(children: _spans(line.substring(m.end), base)))),
            ],
          ),
        ));
      } else {
        children.add(Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text.rich(TextSpan(children: _spans(line, base))),
        ));
      }
    }
    return SelectionArea(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children));
  }
}

class _SafetyCardView extends StatelessWidget {
  final SafetyCard card;
  const _SafetyCardView({required this.card});

  Future<void> _call(BuildContext context, String number) async {
    var ok = false;
    try {
      ok = await launchUrl(Uri(scheme: 'tel', path: number));
    } catch (_) {
      ok = false;
    }
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Please dial $number')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: HuxSpacing.sm),
      child: GlassPanel(
        strokeColor: HuxColors.rundown,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(card.title, style: text.titleSmall),
            const SizedBox(height: HuxSpacing.xs),
            Text(card.body, style: text.bodyMedium),
            const SizedBox(height: HuxSpacing.sm),
            Wrap(
              spacing: HuxSpacing.sm,
              runSpacing: HuxSpacing.sm,
              children: [
                for (final c in card.calls)
                  FilledButton.tonalIcon(
                    onPressed: () => _call(context, c.number),
                    icon: const Icon(Icons.call),
                    label: Text(c.label),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  final String text;
  const _Message({required this.text});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(HuxSpacing.xl),
          child: Text(text, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
        ),
      );
}
