/// The standard "not medical" footnote, in ONE place so the wording on
/// every screen matches the Terms of use (docs/legal/TERMS_OF_USE.md)
/// and the store listings.
library;

import 'package:flutter/material.dart';

import '../theme/hux_tokens.dart';

class WellnessNote extends StatelessWidget {
  static const text = 'HUX gives wellness insights from your own data. It is not a medical device and '
      "doesn't diagnose or treat any condition. For health concerns, please see a doctor.";

  const WellnessNote({super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: HuxSpacing.md),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: HuxColors.mutedText),
        ),
      );
}
