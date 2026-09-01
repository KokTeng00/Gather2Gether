import 'dart:typed_data';

/// A privacy-safe JPEG that is ready to leave the device.
class PreparedImage {
  const PreparedImage({required this.bytes});

  static const jpegContentType = 'image/jpeg';
  static const maxBytes = 5 * 1024 * 1024;

  final Uint8List bytes;

  String get contentType => jpegContentType;
}
