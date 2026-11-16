/// "Share on WhatsApp": opens WhatsApp with the message ready (the user
/// picks the chat and taps send). Without WhatsApp, the phone's share
/// sheet opens instead. HUX itself sends nothing.
library;

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'hux/hux_kit.dart';

class WhatsAppShareButton extends StatefulWidget {
  final String label;

  /// Builds the message at tap time; null = not enough data yet.
  final Future<String?> Function() text;

  /// Shown when [text] returns null.
  final String emptyMessage;

  const WhatsAppShareButton({
    super.key,
    required this.label,
    required this.text,
    this.emptyMessage = 'Not enough data to share yet — check back later today.',
  });

  @override
  State<WhatsAppShareButton> createState() => _WhatsAppShareButtonState();
}

class _WhatsAppShareButtonState extends State<WhatsAppShareButton> {
  static const _green = Color(0xFF1FA855);
  bool _busy = false;

  Future<void> _share() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      String? text;
      try {
        text = await widget.text();
      } catch (_) {}
      if (!mounted) return;
      if (text == null) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(widget.emptyMessage)));
        return;
      }
      // The app link only (never the wa.me web link): the message must
      // not travel in a web address if WhatsApp isn't installed.
      var opened = false;
      try {
        opened = await launchUrl(
          Uri(scheme: 'whatsapp', host: 'send', queryParameters: {'text': text}),
          mode: LaunchMode.externalApplication,
        );
      } catch (_) {}
      if (opened || !mounted) return;
      final box = context.findRenderObject();
      await Share.share(
        text,
        sharePositionOrigin: box is RenderBox && box.hasSize ? box.localToGlobal(Offset.zero) & box.size : null,
      );
    } catch (_) {
      // Sharing was cancelled or isn't available: nothing to do.
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: TextButton.icon(
        onPressed: _busy ? null : _share,
        icon: const Icon(Icons.send_rounded, size: 18, color: _green),
        label: Text(widget.label, style: TextStyle(fontWeight: FontWeight.w700, color: huxInk)),
      ),
    );
  }
}
