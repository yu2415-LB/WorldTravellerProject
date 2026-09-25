import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:world_traveller_project/enums/media_visibility.dart';
import 'package:world_traveller_project/models/location.dart';
import 'package:world_traveller_project/models/media.dart';
import 'package:world_traveller_project/services/local_media_service.dart';
import 'package:world_traveller_project/services/supabase_storage_service.dart';

/// Thrown by [LocationManagingController.removeItem] when the caller is
/// not allowed to delete a picture: not its owner, and not an admin.
class MediaPermissionDeniedException implements Exception {
  final String message;
  const MediaPermissionDeniedException([
    this.message = 'You can only delete pictures you uploaded yourself.',
  ]);

  @override
  String toString() => message;
}

class LocationManagingController extends ChangeNotifier {
  Location? _location;
  final SupabaseStorageService _storageService = SupabaseStorageService();
  List<Location> _locations = [];
  bool _isLoading = false;

  WorldScope _worldScope = WorldScope.generalWorld;
  MediaCategory? _categoryFilter;

  Location? get location => _location;
  List<Location> get locations => _locations;
  bool get isLoading => _isLoading;
  SupabaseStorageService get storageService => _storageService;
  WorldScope get worldScope => _worldScope;
  MediaCategory? get categoryFilter => _categoryFilter;

  void setWorldScope(WorldScope scope) {
    if (_worldScope == scope) return;
    _worldScope = scope;
    if (scope == WorldScope.myWork) {
      _categoryFilter = null;
    }
    notifyListeners();
  }

  void setCategoryFilter(MediaCategory? category) {
    if (_categoryFilter == category) return;
    _categoryFilter = category;
    notifyListeners();
  }

  List<Location> get visibleLocations {
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    final result = <Location>[];

    for (final loc in _locations) {
      final filtered = loc.mediaSet.where((media) => _mediaMatchesCurrentScope(
            media,
            currentUserId: currentUserId,
          ));

      if (filtered.isNotEmpty) {
        result.add(loc.withMedia(filtered));
      }
    }

    return result;
  }

  bool _mediaMatchesCurrentScope(Media media, {required String? currentUserId}) {
    if (_worldScope == WorldScope.myWork) {
      if (currentUserId == null) return false;
      if (media.isLocalOnly) {
        // Local pictures belong to whoever is signed in on this machine.
        return true;
      }
      return media.userId == currentUserId;
    }

    // General World never shows local-only pictures: they are not on the
    // cloud, so nobody but this machine could ever see them anyway.
    if (media.isLocalOnly) return false;
    if (!media.visibility.isPublic) return false;
    if (_categoryFilter != null && media.category != _categoryFilter) return false;
    return true;
  }

  void createPlace({
    required String city,
    required String country,
    String? region,
    String? cityLocal,
    String? regionLocal,
    String? countryLocal,
    required double latitude,
    required double longitude,
  }) {
    _location = Location(
      userId: Supabase.instance.client.auth.currentUser?.id,
      city: city,
      country: country,
      region: region,
      cityLocal: cityLocal,
      regionLocal: regionLocal,
      countryLocal: countryLocal,
      latitude: latitude,
      longitude: longitude,
    );

    notifyListeners();
  }

  void addMedia(Media media) {
    _location?.addMedia(media);
    notifyListeners();
  }

  Future<void> updateMedia(Media updatedMedia, {String? oldFilePath}) async {
    for (var loc in _locations) {
      final hasMedia = loc.mediaSet.any((m) => m.id == updatedMedia.id);
      if (hasMedia) {
        loc.updateMedia(updatedMedia);
        await _storageService.saveLocation(loc);
        break;
      }
    }
    notifyListeners();
  }

  Future<Location?> findLocationForMedia(Media media) async {
    if (_locations.isEmpty) {
      await loadLocationsFromJSON();
    }
    for (var loc in _locations) {
      if (loc.mediaSet
          .any((m) => m.id == media.id || m.filePath == media.filePath)) {
        return loc;
      }
    }
    return null;
  }

  Future<List<Location>> loadLocationsFromJSON() async {
    _isLoading = true;
    notifyListeners();

    try {
      final loaded = await _storageService.loadLocations();
      _locations = loaded;
    } catch (e) {
      debugPrint('Could not load places: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
    return _locations;
  }

  Future<void> saveLocationToJSON() async {
    if (_location == null) return;

    final index = _locations.indexWhere((loc) => loc.id == _location!.id);
    if (index != -1) {
      _locations[index] = _location!;
    } else {
      _locations.add(_location!);
    }

    await _storageService.saveLocation(_location!);
    notifyListeners();
  }

  Future<void> removeItem(Media media, {required bool requestedByAdmin}) async {
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    final isOwner = currentUserId != null && media.userId == currentUserId;

    // Local-only pictures do not have a cloud owner; allow whoever is on
    // this machine to remove them.
    if (!isOwner && !requestedByAdmin && !media.isLocalOnly) {
      throw const MediaPermissionDeniedException();
    }

    Location? parentLoc;
    for (final loc in _locations) {
      if (loc.mediaSet.any((m) => m.id == media.id)) {
        parentLoc = loc;
        break;
      }
    }

    if (parentLoc != null) {
      try {
        await _storageService.deleteMedia(media, parentLoc);
      } catch (e) {
        final reason = e.toString().replaceFirst('Exception: ', '');
        throw MediaPermissionDeniedException(
            'Could not delete this picture. $reason');
      }
      if (parentLoc.mediaSet.isEmpty) {
        await deleteLocation(parentLoc, requestedByAdmin: requestedByAdmin);
      } else {
        notifyListeners();
      }
    }
  }

  Future<void> deleteLocation(Location location,
      {bool requestedByAdmin = false}) async {
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    final isOwner = currentUserId != null &&
        location.userId != null &&
        location.userId == currentUserId;

    if (!isOwner && !requestedByAdmin) {
      throw const MediaPermissionDeniedException(
        'You can only delete places you created yourself.',
      );
    }

    _locations.removeWhere((loc) => loc.id == location.id);
    notifyListeners();
    await _storageService.deleteLocation(location);
  }

  Future<void> moveLocation(
    Location location,
    double newLatitude,
    double newLongitude,
  ) async {
    final index = _locations.indexWhere((loc) => loc.id == location.id);
    if (index == -1) return;

    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    final isOwner = currentUserId != null &&
        location.userId != null &&
        location.userId == currentUserId;
    if (!isOwner) {
      throw const MediaPermissionDeniedException(
        'You can only move places you created yourself.',
      );
    }

    final moved = Location(
      id: location.id,
      userId: location.userId,
      city: location.city,
      country: location.country,
      region: location.region,
      cityLocal: location.cityLocal,
      regionLocal: location.regionLocal,
      countryLocal: location.countryLocal,
      latitude: newLatitude,
      longitude: newLongitude,
      mediaSet: _locations[index].mediaSet,
    );

    _locations[index] = moved;
    notifyListeners();
    await _storageService.saveLocation(moved);
  }

  Future<void> addMediaToLocation(Location location, Media media) async {
    final index = _locations.indexWhere((loc) => loc.id == location.id);

    if (index == -1) {
      location.addMedia(media);
      _locations.add(location);
    } else {
      _locations[index].addMedia(media);
    }

    notifyListeners();
    await _storageService.saveLocation(
        index != -1 ? _locations[index] : location);
  }

  /// Uploads bytes to the right place depending on [localOnly]:
  ///  * false → Supabase Storage, as before
  ///  * true  → this machine's disk, via [LocalMediaService]
  Future<Media> uploadAndCreateMedia({
    required Location location,
    required String fileName,
    required Uint8List rawBytes,
    required MediaType type,
    bool localOnly = false,
  }) async {
    final processedBytes =
        await _storageService.prepareImageBytes(rawBytes, fileName);

    if (localOnly) {
      if (!LocalMediaService.instance.isAvailable) {
        throw StateError(
            'Local-only pictures are not available on this platform.');
      }

      // Build the Media first to get a fresh id, then write to disk
      // using that id so delete/load can find it again by id alone.
      final draft = Media(
        filePath: '',
        type: type,
        grading: 0,
        fileName: fileName,
        lastModification: DateTime.now(),
        tags: const [],
        memoryBytes: processedBytes,
        userId: Supabase.instance.client.auth.currentUser?.id,
        isLocalOnly: true,
      );

      final relativePath = await LocalMediaService.instance.save(
        mediaId: draft.id,
        fileName: fileName,
        bytes: processedBytes,
      );

      draft.localPath = relativePath;
      draft.filePath = relativePath; // kept in sync for the cache / older code
      return draft;
    }

    final uploadResult = await _storageService.uploadMediaFile(
      bytes: processedBytes,
      fileName: fileName,
      locationId: location.id,
      type: type,
    );

    return Media(
      filePath: uploadResult.storagePath,
      type: type,
      grading: 0,
      fileName: fileName,
      lastModification: DateTime.now(),
      tags: const [],
      remoteUrl: uploadResult.publicUrl,
      memoryBytes: processedBytes,
      userId: Supabase.instance.client.auth.currentUser?.id,
    );
  }
}