import 'package:flutter/services.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:gather2gether/core/media/prepared_image.dart';
import 'package:image_picker/image_picker.dart';

enum AppImageSource { gallery, camera }

class AppImagePickException implements Exception {
  const AppImagePickException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Selects one image and strips metadata before it can be uploaded.
///
/// Keeping the plugin behind this small interface also lets screens recover
/// Android picker results after the activity has been reclaimed by the OS.
abstract interface class AppImagePicker {
  factory AppImagePicker() = PluginAppImagePicker;

  Future<PreparedImage?> pickImage(AppImageSource source);

  Future<PreparedImage?> recoverLostImage();
}

class PluginAppImagePicker implements AppImagePicker {
  PluginAppImagePicker({ImagePicker? picker})
    : _picker = picker ?? ImagePicker();

  static const _maxDimension = 1800.0;
  static const _qualityAttempts = <int>[84, 72, 60];

  final ImagePicker _picker;

  @override
  Future<PreparedImage?> pickImage(AppImageSource source) async {
    try {
      final file = await _picker.pickImage(
        source: switch (source) {
          AppImageSource.gallery => ImageSource.gallery,
          AppImageSource.camera => ImageSource.camera,
        },
        maxWidth: _maxDimension,
        maxHeight: _maxDimension,
        requestFullMetadata: false,
      );
      return file == null ? null : await _prepare(file);
    } on PlatformException catch (error) {
      throw AppImagePickException(_platformMessage(error));
    } on AppImagePickException {
      rethrow;
    } catch (_) {
      throw const AppImagePickException(
        'That photo could not be prepared. Try a different image.',
      );
    }
  }

  @override
  Future<PreparedImage?> recoverLostImage() async {
    try {
      final response = await _picker.retrieveLostData();
      if (response.isEmpty) return null;
      if (response.exception case final exception?) {
        throw AppImagePickException(_platformMessage(exception));
      }
      final file = response.files?.firstOrNull ?? response.file;
      return file == null ? null : await _prepare(file);
    } on UnimplementedError {
      return null;
    } on PlatformException catch (error) {
      throw AppImagePickException(_platformMessage(error));
    } on AppImagePickException {
      rethrow;
    } catch (_) {
      return null;
    }
  }

  Future<PreparedImage> _prepare(XFile file) async {
    final original = await file.readAsBytes();
    if (original.isEmpty) {
      throw const AppImagePickException('The selected photo is empty.');
    }

    for (final quality in _qualityAttempts) {
      final encoded = await FlutterImageCompress.compressWithList(
        original,
        minWidth: _maxDimension.round(),
        minHeight: _maxDimension.round(),
        quality: quality,
        format: CompressFormat.jpeg,
        keepExif: false,
      );
      if (encoded.isNotEmpty && encoded.length <= PreparedImage.maxBytes) {
        return PreparedImage(bytes: encoded);
      }
    }

    throw const AppImagePickException(
      'That photo is too large. Choose one under 5 MB.',
    );
  }

  String _platformMessage(PlatformException error) {
    final code = error.code.toLowerCase();
    if (code.contains('denied') || code.contains('permission')) {
      return 'Photo access is unavailable. Allow access in system settings and try again.';
    }
    if (code.contains('camera')) {
      return 'The camera is unavailable right now.';
    }
    return 'Could not open photos. Please try again.';
  }
}
