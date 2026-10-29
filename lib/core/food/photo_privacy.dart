/// Removes hidden photo metadata (EXIF: GPS location, camera, time)
/// before a meal photo leaves the phone. Decoding and re-encoding the
/// pixels writes a fresh JPEG with no metadata at all.
library;

import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Returns a metadata-free JPEG of [bytes]. Runs off the UI thread.
/// Throws [FormatException] if the bytes aren't a readable image —
/// never sends the original (with its metadata) instead.
Future<Uint8List> stripPhotoMetadata(Uint8List bytes, {int quality = 80}) =>
    Isolate.run(() => stripPhotoMetadataSync(bytes, quality: quality));

Uint8List stripPhotoMetadataSync(Uint8List bytes, {int quality = 80}) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) throw const FormatException('Unreadable photo');
  // Apply the EXIF orientation to the pixels, then drop all EXIF.
  final upright = img.bakeOrientation(decoded);
  upright.exif = img.ExifData();
  return img.encodeJpg(upright, quality: quality);
}
