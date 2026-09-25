import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:world_traveller_project/models/location.dart';
import 'package:world_traveller_project/models/media.dart';
import 'package:world_traveller_project/services/local_media_service.dart';

class SupabaseStorageService {
  static final SupabaseStorageService _instance =
      SupabaseStorageService._internal();
  factory SupabaseStorageService() => _instance;
  SupabaseStorageService._internal();

  SupabaseClient get _client => Supabase.instance.client;
  static const String _bucketName = 'media';
  static const String _localCacheKey = 'wtp_cached_locations_v2';

  static const Set<String> supportedImageExtensions = {
    'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'tif', 'tiff', 'heic', 'heif', 'avif'
  };

  /// Converts formats browsers cannot show (TIFF and friends) into PNG,
  /// entirely in memory so it works on every platform.
  Future<Uint8List> prepareImageBytes(Uint8List rawBytes, String fileName) async {
    final ext = p.extension(fileName).replaceFirst('.', '').toLowerCase();

    if (ext == 'tif' || ext == 'tiff') {
      try {
        final decoded = img.decodeTiff(rawBytes) ?? img.decodeImage(rawBytes);
        if (decoded != null) {
          img.Image target = decoded;
          if (target.width > 2400 || target.height > 2400) {
            target = img.copyResize(
              target,
              width: target.width >= target.height ? 2400 : null,
              height: target.height > target.width ? 2400 : null,
            );
          }
          return Uint8List.fromList(img.encodePng(target));
        }
      } catch (e) {
        debugPrint('TIFF conversion failed: $e');
      }
    }

    return rawBytes;
  }

  /// Uploads a picture to Supabase Storage and returns its public URL and path.
  Future<({String storagePath, String publicUrl})> uploadMediaFile({
    required Uint8List bytes,
    required String fileName,
    required String locationId,
    required MediaType type,
  }) async {
    final currentUser = _client.auth.currentUser;
    final userId = currentUser?.id ?? 'anonymous';
    final fileExt = p.extension(fileName).toLowerCase();
    final uniqueId = const Uuid().v4().substring(0, 8);
    final cleanName = p
        .basenameWithoutExtension(fileName)
        .replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
    final storagePath = '$userId/$locationId/${cleanName}_$uniqueId$fileExt';

    final mimeType = lookupMimeType(fileName) ?? 'image/jpeg';

    await _client.storage.from(_bucketName).uploadBinary(
      storagePath,
      bytes,
      fileOptions: FileOptions(
        contentType: mimeType,
        upsert: true,
      ),
    );

    final publicUrl =
        _client.storage.from(_bucketName).getPublicUrl(storagePath);
    return (storagePath: storagePath, publicUrl: publicUrl);
  }

  /// Uploads a new profile picture and returns its public URL.
  Future<String> uploadAvatar({
    required String userId,
    required Uint8List bytes,
    required String fileName,
  }) async {
    final fileExt = p.extension(fileName).isEmpty
        ? '.jpg'
        : p.extension(fileName).toLowerCase();
    final storagePath = '$userId/avatar$fileExt';
    final mimeType = lookupMimeType(fileName) ?? 'image/jpeg';

    await _client.storage.from(_bucketName).uploadBinary(
          storagePath,
          bytes,
          fileOptions: FileOptions(contentType: mimeType, upsert: true),
        );
    return '${_client.storage.from(_bucketName).getPublicUrl(storagePath)}?t=${DateTime.now().millisecondsSinceEpoch}';
  }

  /// Loads every place from Supabase, falling back to the local cache.
  Future<List<Location>> loadLocations() async {
    try {
      final List<dynamic> locRows = await _client
          .from('locations')
          .select()
          .order('created_at', ascending: false);

      final List<dynamic> mediaRows = await _client
          .from('media_items')
          .select()
          .order('created_at', ascending: true);

      final Map<String, List<Media>> mediaByLocation = {};
      for (final rawMedia in mediaRows) {
        final row = Map<String, dynamic>.from(rawMedia as Map);
        final locId = row['location_id']?.toString() ?? '';
        final storagePath = row['storage_path']?.toString() ?? '';

        String? publicUrl;
        if (storagePath.isNotEmpty) {
          if (storagePath.startsWith('http://') ||
              storagePath.startsWith('https://') ||
              storagePath.startsWith('data:')) {
            publicUrl = storagePath;
          } else {
            publicUrl =
                _client.storage.from(_bucketName).getPublicUrl(storagePath);
          }
        }

        final mediaItem = Media.fromSupabase(row, publicUrl: publicUrl);
        mediaByLocation.putIfAbsent(locId, () => []).add(mediaItem);
      }

      final locations = <Location>[];
      for (final rawLoc in locRows) {
        final locRow = Map<String, dynamic>.from(rawLoc as Map);
        final locId = locRow['id']?.toString() ?? '';
        final mediaList = mediaByLocation[locId] ?? [];
        locations.add(Location.fromSupabase(locRow, mediaList));
      }

      // Merge in the local-only pictures we hold on this machine, so
      // they appear alongside the cloud ones in the app.
      final localOnly = await _loadLocalOnlyMediaFromCache();
      for (final loc in locations) {
        final locals = localOnly[loc.id];
        if (locals == null) continue;
        for (final m in locals) {
          loc.addMedia(m);
        }
      }

      await _saveLocationsToLocalCache(locations);
      return locations;
    } catch (dbError) {
      debugPrint(
          'Could not load from Supabase ($dbError), using the local cache...');
      return await _loadLocationsFromLocalCache();
    }
  }

  /// Reads the "local-only" pictures we previously saved on this machine,
  /// grouped by their parent location id, and preloads their bytes so
  /// the UI can show them straight away. Never throws.
  Future<Map<String, List<Media>>> _loadLocalOnlyMediaFromCache() async {
    final result = <String, List<Media>>{};
    if (!LocalMediaService.instance.isAvailable) return result;

    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_localCacheKey);
      if (raw == null || raw.trim().isEmpty) return result;

      final decoded = jsonDecode(raw) as List<dynamic>;
      for (final item in decoded) {
        final locJson = item as Map<String, dynamic>;
        final locId = locJson['id']?.toString() ?? '';
        final mediaJson = (locJson['media'] as List?) ?? [];

        for (final rawMedia in mediaJson) {
          final row = rawMedia as Map<String, dynamic>;
          if (row['isLocalOnly'] != true) continue;

          final media = Media.fromJson(row);
          // Preload the bytes from disk so widgets can just use
          // media.memoryBytes without an async round trip.
          final bytes =
              await LocalMediaService.instance.load(media.localPath ?? '');
          media.memoryBytes = bytes;
          result.putIfAbsent(locId, () => []).add(media);
        }
      }
    } catch (e) {
      debugPrint('Could not read local-only pictures from cache: $e');
    }

    return result;
  }

  /// Saves or updates a single place in Supabase, skipping any
  /// "local-only" picture the user chose to keep off the cloud.
  Future<void> saveLocation(Location location) async {
    final user = _client.auth.currentUser;
    final userId = user?.id;
    if (userId == null) {
      throw StateError('You need to be signed in to save a place.');
    }

    await _client.from('locations').upsert(location.toSupabase(userId));

    // Upsert only the CLOUD pictures that belong to it. Local-only ones
    // live on disk and must never touch Supabase Storage or the DB.
    for (final media in location.mediaSet) {
      if (media.isLocalOnly) continue;
      await _client
          .from('media_items')
          .upsert(media.toSupabase(location.id, userId));
    }

    final currentList = await _loadLocationsFromLocalCache();
    final idx = currentList.indexWhere((l) => l.id == location.id);
    if (idx != -1) {
      currentList[idx] = location;
    } else {
      currentList.add(location);
    }
    await _saveLocationsToLocalCache(currentList);
  }

  /// Saves the whole list of places, skipping local-only pictures.
  Future<void> saveLocations(List<Location> locations) async {
    final user = _client.auth.currentUser;
    final userId = user?.id;
    if (userId == null) {
      throw StateError('You need to be signed in to save your places.');
    }

    for (final loc in locations) {
      await _client.from('locations').upsert(loc.toSupabase(userId));
      for (final m in loc.mediaSet) {
        if (m.isLocalOnly) continue;
        await _client
            .from('media_items')
            .upsert(m.toSupabase(loc.id, userId));
      }
    }

    await _saveLocationsToLocalCache(locations);
  }

  /// Deletes a place, its cloud pictures, AND any local-only files it
  /// was holding on this machine.
  Future<void> deleteLocation(Location location) async {
    final cloudPaths = location.mediaSet
        .where((m) => !m.isLocalOnly)
        .map((m) => m.filePath)
        .where((p) =>
            p.isNotEmpty && !p.startsWith('http') && !p.startsWith('data:'))
        .toList();

    if (cloudPaths.isNotEmpty) {
      try {
        await _client.storage.from(_bucketName).remove(cloudPaths);
      } catch (e) {
        debugPrint('Could not remove some files from Storage: $e');
      }
    }

    // Local-only files are ours to delete from disk.
    for (final m in location.mediaSet.where((m) => m.isLocalOnly)) {
      await LocalMediaService.instance.delete(m.localPath ?? '');
    }

    await _client.from('locations').delete().eq('id', location.id);

    final currentList = await _loadLocationsFromLocalCache();
    currentList.removeWhere((l) => l.id == location.id);
    await _saveLocationsToLocalCache(currentList);
  }

  /// Deletes a single picture: from Storage if cloud, from disk if local.
  Future<void> deleteMedia(Media media, Location location) async {
    if (media.isLocalOnly) {
      await LocalMediaService.instance.delete(media.localPath ?? '');
    } else {
      if (media.filePath.isNotEmpty &&
          !media.filePath.startsWith('http') &&
          !media.filePath.startsWith('data:')) {
        try {
          await _client.storage.from(_bucketName).remove([media.filePath]);
        } catch (e) {
          debugPrint('Could not remove the file from Storage: $e');
        }
      }
      await _client.from('media_items').delete().eq('id', media.id);
    }

    location.removeMedia(media);
    await saveLocation(location);
  }

  // --- LOCAL CACHE (SharedPreferences) ---

  Future<void> _saveLocationsToLocalCache(List<Location> locations) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonList = locations.map((loc) => loc.toJson()).toList();
      await prefs.setString(_localCacheKey, jsonEncode(jsonList));
    } catch (e) {
      debugPrint('Could not write the local cache: $e');
    }
  }

  Future<List<Location>> _loadLocationsFromLocalCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_localCacheKey);
      if (raw == null || raw.trim().isEmpty) return [];

      final decoded = jsonDecode(raw) as List<dynamic>;
      final locations = decoded
          .map((item) => Location.fromJson(item as Map<String, dynamic>))
          .toList();

      // Preload local-only bytes so the widgets can show them without
      // an async hop. Missing files are silently skipped.
      if (LocalMediaService.instance.isAvailable) {
        for (final loc in locations) {
          for (final m in loc.mediaSet) {
            if (m.isLocalOnly && (m.memoryBytes == null || m.memoryBytes!.isEmpty)) {
              m.memoryBytes =
                  await LocalMediaService.instance.load(m.localPath ?? '');
            }
          }
        }
      }

      return locations;
    } catch (e) {
      debugPrint('Could not read the local cache: $e');
      return [];
    }
  }
}