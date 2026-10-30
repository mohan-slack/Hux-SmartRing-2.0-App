/// Turns a card into a shareable image (WhatsApp, Instagram…): the card
/// is drawn inside a RepaintBoundary with a small HUX footer, and the
/// Share button below it captures exactly that area as a PNG.
library;

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:share_plus/share_plus.dart';

import '../theme/hux_tokens.dart';

class ShareCapture extends StatefulWidget {
  final Widget child;
  final String fileName;
  final String shareText;
  final String buttonLabel;

  const ShareCapture({
    super.key,
    required this.child,
    required this.fileName,
    required this.shareText,
    this.buttonLabel = 'Share',
  });

  @override
  State<ShareCapture> createState() => _ShareCaptureState();
}

class _ShareCaptureState extends State<ShareCapture> {
  final _boundary = GlobalKey();
  final _button = GlobalKey();
  bool _busy = false;

  /// iPad — and iPhone since iOS 26 — needs an anchor for the share
  /// sheet; without one the share call throws.
  Rect? _origin() {
    for (final key in [_button, _boundary]) {
      final box = key.currentContext?.findRenderObject();
      if (box is RenderBox && box.hasSize && box.size.width > 0) {
        return box.localToGlobal(Offset.zero) & box.size;
      }
    }
    return null;
  }

  Future<void> _share() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final box = _boundary.currentContext?.findRenderObject();
      if (box is! RenderRepaintBoundary) return;
      final image = await box.toImage(pixelRatio: 3);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (data == null) return;
      await Share.shareXFiles(
        [XFile.fromData(data.buffer.asUint8List(), mimeType: 'image/png', name: widget.fileName)],
        text: widget.shareText,
        sharePositionOrigin: _origin(),
      );
    } catch (e) {
      debugPrint('Share card failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text("Couldn't create the image — try again.")));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RepaintBoundary(
          key: _boundary,
          child: Container(
            // Solid background so the PNG isn't transparent.
            color: HuxColors.bg,
            padding: const EdgeInsets.all(HuxSpacing.xs),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                widget.child,
                Padding(
                  padding: const EdgeInsets.only(top: HuxSpacing.xs, right: HuxSpacing.sm),
                  child: Text('HUX · your body, in plain words',
                      textAlign: TextAlign.right,
                      style: text.labelSmall?.copyWith(color: HuxColors.mutedText, letterSpacing: 0.4)),
                ),
              ],
            ),
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            key: _button,
            onPressed: _busy ? null : _share,
            icon: const Icon(Icons.ios_share_rounded, size: 18),
            label: Text(widget.buttonLabel),
          ),
        ),
      ],
    );
  }
}
