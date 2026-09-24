
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:world_traveller_project/services/supabase_storage_service.dart';

/// A problem with a picked file, already worded for the traveller.
class ImageValidationException implements Exception {
  final String message;
  const ImageValidationException(this.message);

  @override
  String toString() => message;
}

/// A picture that passed validation and is ready to upload.
class PreparedImage {
  final Uint8List bytes;

  /// May differ from the picked name if the format had to change
  /// (e.g. a huge WEBP re-encoded as JPG), so extension and bytes agree.
  final String fileName;
  final int width;
  final int height;
  final bool wasResized;

  const PreparedImage({
    required this.bytes,
    required this.fileName,
    required this.width,
    required this.height,
    required this.wasResized,
  });
}

/// Checks a picked picture (format, real content, size) and scales it
/// down so its longest side is at most [maxLongSide] px. Pictures already
/// within the limit are left byte-for-byte untouched: no needless
/// re-compression.
class ImageValidationService {
  ImageValidationService._();
  static final ImageValidationService instance = ImageValidationService._();

  static const int maxLongSide = 2048;
  static const int maxFileBytes = 30 * 1024 * 1024;

  Future<PreparedImage> prepare(Uint8List raw, String fileName) async {
    final ext = p.extension(fileName).replaceFirst('.', '').toLowerCase();

    if (!SupabaseStorageService.supportedImageExtensions.contains(ext)) {
      throw const ImageValidationException(
          'Unsupported format. Use JPG, PNG or WEBP.');
    }
    if (raw.isEmpty) {
      throw const ImageValidationException('This file is empty.');
    }
    if (raw.length > maxFileBytes) {
      throw ImageValidationException(
          'Picture too large (max ${maxFileBytes ~/ (1024 * 1024)} MB).');
    }

    // The three main formats are checked by their real content, not
    // just the extension, and scaled down when needed.
    if (ext == 'jpg' || ext == 'jpeg' || ext == 'png' || ext == 'webp') {
      if (!_looksLike(ext, raw)) {
        throw const ImageValidationException(
            'The file content does not match its format.');
      }
      final result = await compute(_inspectAndScale, _Job(raw, ext));
      if (result == null) {
        throw const ImageValidationException(
            'This picture looks damaged and cannot be read.');
      }
      if (result.bytes == null) {
        return PreparedImage(
          bytes: raw,
          fileName: fileName,
          width: result.width,
          height: result.height,
          wasResized: false,
        );
      }
      final base = p.basenameWithoutExtension(fileName);
      return PreparedImage(
        bytes: result.bytes!,
        fileName: '$base.${result.ext}',
        width: result.width,
        height: result.height,
        wasResized: true,
      );
    }

    // Other formats supported by the app keep their old handling.
    return PreparedImage(
      bytes: raw,
      fileName: fileName,
      width: 0,
      height: 0,
      wasResized: false,
    );
  }

  bool _looksLike(String ext, Uint8List b) {
    if (b.length < 12) return false;
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF;
      case 'png':
        return b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47;
      case 'webp':
        return b[0] == 0x52 && b[1] == 0x49 && b[2] == 0x46 && b[3] == 0x46 &&
            b[8] == 0x57 && b[9] == 0x45 && b[10] == 0x42 && b[11] == 0x50;
    }
    return true;
  }
}

class _Job {
  final Uint8List bytes;
  final String ext;
  _Job(this.bytes, this.ext);
}

class _Result {
  /// null = the original bytes can be used as they are.
  final Uint8List? bytes;
  final int width;
  final int height;
  final String ext;
  _Result(this.bytes, this.width, this.height, this.ext);
}

/// Runs off the UI thread on native platforms (compute).
_Result? _inspectAndScale(_Job job) {
  try {
    var image = img.decodeImage(job.bytes);
    if (image == null) return null;

    final longest = image.width > image.height ? image.width : image.height;
    if (longest <= ImageValidationService.maxLongSide) {
      return _Result(null, image.width, image.height, job.ext);
    }

    image = img.bakeOrientation(image);
    final landscape = image.width >= image.height;
    final resized = img.copyResize(
      image,
      width: landscape ? ImageValidationService.maxLongSide : null,
      height: landscape ? null : ImageValidationService.maxLongSide,
    );

    if (job.ext == 'png') {
      return _Result(Uint8List.fromList(img.encodePng(resized)),
          resized.width, resized.height, 'png');
    }
    // JPG stays JPG; WEBP (no encoder available) becomes a high-quality JPG.
    return _Result(Uint8List.fromList(img.encodeJpg(resized, quality: 90)),
        resized.width, resized.height, 'jpg');
  } catch (e) {
    debugPrint('Image inspection failed: $e');
    return null;
  }
}
