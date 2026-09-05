import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gather2gether/core/media/app_image_picker.dart';
import 'package:image_picker/image_picker.dart';

class _UnreadableImage extends XFile {
  _UnreadableImage() : super('unreadable-image.jpg');

  @override
  Future<Uint8List> readAsBytes() async {
    throw StateError('The temporary image is no longer readable.');
  }
}

class _ImagePickerStub extends ImagePicker {
  @override
  Future<XFile?> pickImage({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    bool requestFullMetadata = true,
  }) async => _UnreadableImage();

  @override
  Future<LostDataResponse> retrieveLostData() async =>
      LostDataResponse(files: [_UnreadableImage()]);
}

void main() {
  test('picking an unreadable image returns a helpful error', () async {
    final picker = PluginAppImagePicker(picker: _ImagePickerStub());

    await expectLater(
      picker.pickImage(AppImageSource.gallery),
      throwsA(
        isA<AppImagePickException>().having(
          (error) => error.message,
          'message',
          'That photo could not be prepared. Try a different image.',
        ),
      ),
    );
  });

  test('recovering an unreadable image returns no image', () async {
    final picker = PluginAppImagePicker(picker: _ImagePickerStub());

    expect(await picker.recoverLostImage(), isNull);
  });
}
