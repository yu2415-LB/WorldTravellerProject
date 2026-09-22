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

class SupabaseStorageService {
  static final SupabaseStorageService _instance = SupabaseStorageService._internal();
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

    // Formats that browsers and Flutter Web cannot display natively.
    if (ext == 'tif' || ext == 'tiff') {
      try {
        final decoded = img.decodeTiff(rawBytes) ?? img.decodeImage(rawBytes);
        if (decoded != null) {
          // Shrink very large pictures to save bandwidth and memory.
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
    final cleanName = p.basenameWithoutExtension(fileName).replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
    final storagePath = '$userId/$locationId/${cleanName}_$uniqueId$fileExt';

    // Work out the right MIME type.
    final mimeType = lookupMimeType(fileName) ?? 'image/jpeg';

    try {
      // 1. Try uploading to Supabase Storage.
      await _client.storage.from(_bucketName).uploadBinary(
        storagePath,
        bytes,
        fileOptions: FileOptions(
          contentType: mimeType,
          upsert: true,
        ),
      );

      final publicUrl = _client.storage.from(_bucketName).getPublicUrl(storagePath);
      return (storagePath: storagePath, publicUrl: publicUrl);
    } catch (e) {
      debugPrint('Supabase Storage upload failed or bucket not ready ($e).');
      // Fallback: build a base64 data URL so the picture still shows up.
      final base64String = base64Encode(bytes);
      final dataUrl = 'data:$mimeType;base64,$base64String';
      return (storagePath: storagePath, publicUrl: dataUrl);
    }
  }

  /// Uploads a new profile picture and returns its public URL.
  /// Used by "My Account" (Phase 2) to let a traveller change their photo.
  Future<String> uploadAvatar({
    required String userId,
    required Uint8List bytes,
    required String fileName,
  }) async {
    final fileExt = p.extension(fileName).isEmpty ? '.jpg' : p.extension(fileName).toLowerCase();
    final storagePath = 'avatars/$userId$fileExt';
    final mimeType = lookupMimeType(fileName) ?? 'image/jpeg';

    try {
      await _client.storage.from(_bucketName).uploadBinary(
            storagePath,
            bytes,
            fileOptions: FileOptions(contentType: mimeType, upsert: true),
          );
      // Cache-bust so the new picture shows up immediately everywhere.
      return '${_client.storage.from(_bucketName).getPublicUrl(storagePath)}?t=${DateTime.now().millisecondsSinceEpoch}';
    } catch (e) {
      debugPrint('Avatar upload failed ($e).');
      final base64String = base64Encode(bytes);
      return 'data:$mimeType;base64,$base64String';
    }
  }

  /// Loads every place from Supabase, falling back to the local cache.
  Future<List<Location>> loadLocations() async {
    // 1. Try loading from the Supabase database.
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
          if (storagePath.startsWith('http://') || storagePath.startsWith('https://') || storagePath.startsWith('data:')) {
            publicUrl = storagePath;
          } else {
            publicUrl = _client.storage.from(_bucketName).getPublicUrl(storagePath);
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

      // Keep a local copy for speed and offline use.
      await _saveLocationsToLocalCache(locations);
      return locations;
    } catch (dbError) {
      debugPrint('Could not load from Supabase ($dbError), using the local cache...');
      return await _loadLocationsFromLocalCache();
    }
  }

  /// Saves or updates a single place in Supabase and in the local cache.
  Future<void> saveLocation(Location location) async {
    final user = _client.auth.currentUser;
    final userId = user?.id;

    if (userId != null) {
      try {
        await _client.from('locations').upsert(location.toSupabase(userId));

        // Upsert the pictures that belong to it.
        for (final media in location.mediaSet) {
          await _client.from('media_items').upsert(media.toSupabase(location.id, userId));
        }
      } catch (e) {
        debugPrint('Saving to Supabase failed ($e). Stored in the local cache.');
      }
    }

    // Always refresh the local cache.
    final currentList = await _loadLocationsFromLocalCache();
    final idx = currentList.indexWhere((l) => l.id == location.id);
    if (idx != -1) {
      currentList[idx] = location;
    } else {
      currentList.add(location);
    }
    await _saveLocationsToLocalCache(currentList);
  }

  /// Saves the whole list of places.
  Future<void> saveLocations(List<Location> locations) async {
    await _saveLocationsToLocalCache(locations);

    final user = _client.auth.currentUser;
    final userId = user?.id;
    if (userId == null) return;

    for (final loc in locations) {
      try {
        await _client.from('locations').upsert(loc.toSupabase(userId));
        for (final m in loc.mediaSet) {
          await _client.from('media_items').upsert(m.toSupabase(loc.id, userId));
        }
      } catch (e) {
        debugPrint('Supabase sync failed ($e)');
      }
    }
  }

  /// Deletes a place and every picture in it.
  Future<void> deleteLocation(Location location) async {
    try {
      // Remove the files from storage.
      final filesToDelete = location.mediaSet
          .map((m) => m.filePath)
          .where((p) => p.isNotEmpty && !p.startsWith('http') && !p.startsWith('data:'))
          .toList();

      if (filesToDelete.isNotEmpty) {
        try {
          await _client.storage.from(_bucketName).remove(filesToDelete);
        } catch (_) {}
      }

      // Remove it from the database.
      await _client.from('locations').delete().eq('id', location.id);
    } catch (e) {
      debugPrint('Could not delete from Supabase: $e');
    }

    final currentList = await _loadLocationsFromLocalCache();
    currentList.removeWhere((l) => l.id == location.id);
    await _saveLocationsToLocalCache(currentList);
  }

  /// Deletes a single picture.
  Future<void> deleteMedia(Media media, Location location) async {
    try {
      if (media.filePath.isNotEmpty && !media.filePath.startsWith('http') && !media.filePath.startsWith('data:')) {
        await _client.storage.from(_bucketName).remove([media.filePath]);
      }
      await _client.from('media_items').delete().eq('id', media.id);
    } catch (e) {
      debugPrint('Could not delete the picture from Supabase: $e');
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
      return decoded.map((item) => Location.fromJson(item as Map<String, dynamic>)).toList();
    } catch (e) {
      debugPrint('Could not read the local cache: $e');
      return [];
    }
  }
}

