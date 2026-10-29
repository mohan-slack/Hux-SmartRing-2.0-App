/// Meal photos must leave the phone without EXIF (GPS) metadata.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:hux_app/core/food/photo_privacy.dart';

void main() {
  test('re-encoded photo has no EXIF / GPS data', () {
    final photo = img.Image(width: 8, height: 8);
    photo.exif.gpsIfd['GPSLatitudeRef'] = img.IfdValueAscii('N');
    photo.exif.imageIfd['Make'] = img.IfdValueAscii('TestPhone');
    final withExif = img.encodeJpg(photo);
    expect(img.decodeJpgExif(withExif)?.isEmpty ?? true, isFalse,
        reason: 'test setup: the source photo should carry EXIF');

    final clean = stripPhotoMetadataSync(withExif);

    final exif = img.decodeJpgExif(clean);
    expect(exif == null || exif.isEmpty, isTrue);
    expect(img.decodeJpg(clean)!.width, 8);
  });

  test('unreadable bytes throw instead of sending the original', () {
    expect(() => stripPhotoMetadataSync(Uint8List.fromList([1, 2, 3])), throwsFormatException);
  });
}
