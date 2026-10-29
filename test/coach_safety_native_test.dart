/// The on-phone safety card must also fire for messages typed in the
/// scripts the coach replies in (Hindi, Telugu, Tamil, Kannada).
import 'package:flutter_test/flutter_test.dart';
import 'package:hux_app/core/coach/safety.dart';

void main() {
  test('chest pain in native scripts -> emergency card', () {
    for (final t in ['मुझे सीने में दर्द है', 'నాకు ఛాతీ నొప్పి', 'எனக்கு நெஞ்சு வலி', 'ನನಗೆ ಎದೆ ನೋವು']) {
      expect(SafetyCheck.check(t)?.kind, SafetyKind.emergency, reason: t);
    }
  });

  test('self-harm in native scripts -> Tele-MANAS card', () {
    for (final t in ['मैं आत्महत्या के बारे में सोच रहा हूँ', 'ఆత్మహత్య', 'தற்கொலை', 'ಆತ್ಮಹತ್ಯೆ']) {
      expect(SafetyCheck.check(t)?.kind, SafetyKind.selfHarm, reason: t);
    }
  });

  test('ordinary messages in native scripts -> no card', () {
    expect(SafetyCheck.check('आज क्या खाऊँ?'), isNull);
    expect(SafetyCheck.check('ఈరోజు ఎంత నడవాలి?'), isNull);
  });
}
