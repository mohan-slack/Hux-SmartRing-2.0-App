/// The display face (Sora) for titles and big numbers.
///
/// google_fonts downloads a font the first time it is used. Widget tests
/// have no network, so under `flutter test` this returns the same style
/// without the download (the default test font is used instead).
library;

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/painting.dart';
import 'package:google_fonts/google_fonts.dart';

final bool _inTest = !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');

TextStyle huxSora({
  TextStyle? textStyle,
  double? fontSize,
  FontWeight? fontWeight,
  double? height,
  Color? color,
  double? letterSpacing,
  List<FontFeature>? fontFeatures,
  TextDecoration? decoration,
}) {
  if (_inTest) {
    return (textStyle ?? const TextStyle()).copyWith(
      fontSize: fontSize,
      fontWeight: fontWeight,
      height: height,
      color: color,
      letterSpacing: letterSpacing,
      fontFeatures: fontFeatures,
      decoration: decoration,
    );
  }
  return GoogleFonts.sora(
    textStyle: textStyle,
    fontSize: fontSize,
    fontWeight: fontWeight,
    height: height,
    color: color,
    letterSpacing: letterSpacing,
    fontFeatures: fontFeatures,
    decoration: decoration,
  );
}
