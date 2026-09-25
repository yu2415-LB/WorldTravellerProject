import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Stores pictures on the local disk only. They never reach Supabase
/// Storage and never appear for any other traveller. Desktop / mobile
/// only: on the web there is no writable directory and [isAvailable]
/// returns false, so the UI hides the "keep it on this computer" option.
///
/// Files are written under:
///   <app documents>/world_traveller/local_media/<mediaId>_<safeName>
/// and they are removed the moment the corresponding Media is deleted.
class LocalMediaService {
  LocalMediaService._();
  static final LocalMediaService instance = LocalMediaService._();

  static const String _folderName = 'local_media';
  static const String _appFolder = 'world_traveller';

  /// False on the web (no local storage for binaries) and whenever the
  /// platform can't give us a documents directory.
  bool get isAvailable => !kIsWeb;

  Future<Directory> _rootDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, _appFolder, _folderName));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Safe file name: only letters, digits, dashes and underscores.
  String _safeName(String raw) {
    final base = p.basenameWithoutExtension(raw);
    final ext = p.extension(raw).toLowerCase();
    final clean = base.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
    return '$clean$ext';
  }

  /// Saves [bytes] to disk and returns the path relative to the app
  /// documents directory. Callers should hold on to this string and
  /// pass it back to [load] / [delete].
  Future<String> save({
    required String mediaId,
    required String fileName,
    required Uint8List bytes,
  }) async {
    if (!isAvailable) {
      throw StateError('Local storage is not available on this platform.');
    }
    final dir = await _rootDir();
    final safe = _safeName(fileName);
    final file = File(p.join(dir.path, '${mediaId}_$safe'));
    await file.writeAsBytes(bytes, flush: true);
    final docs = await getApplicationDocumentsDirectory();
    return p.relative(file.path, from: docs.path);
  }

  /// Reads the bytes back. Returns null if the file is missing (user
  /// deleted it by hand, copied the app to a new machine, ...).
  Future<Uint8List?> load(String relativePath) async {
    if (!isAvailable) return null;
    if (relativePath.trim().isEmpty) return null;
    try {
      final docs = await getApplicationDocumentsDirectory();
      final file = File(p.join(docs.path, relativePath));
      if (!await file.exists()) return null;
      return await file.readAsBytes();
    } catch (e) {
      debugPrint('Could not read local media: $e');
      return null;
    }
  }

  Future<void> delete(String relativePath) async {
    if (!isAvailable) return;
    if (relativePath.trim().isEmpty) return;
    try {
      final docs = await getApplicationDocumentsDirectory();
      final file = File(p.join(docs.path, relativePath));
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      debugPrint('Could not delete local media: $e');
    }
  }
}