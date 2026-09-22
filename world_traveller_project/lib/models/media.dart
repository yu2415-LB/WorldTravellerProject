import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:world_traveller_project/enums/media_visibility.dart';

/// The app only deals with pictures now. The enum is kept so that rows
/// saved by older versions of the app (which could also store videos)
/// still load without crashing.
enum MediaType {
  image,
  unknown,
}

class Media {
  final String id;
  String filePath;
  final MediaType type;
  double grading;
  int moodRating;
  String fileName;
  final DateTime lastModification;
  final List<String> tags;
  String? storyNote;
  String? remoteUrl;
  Uint8List? memoryBytes;

  /// The date the trip/photo actually happened, as opposed to
  /// [lastModification] (when the row was last saved). Used to sort and
  /// group pictures by when the memory took place, not when it was
  /// uploaded or edited.
  DateTime? travelDate;

  /// "My Work" (private) vs "General World" (public). Every new upload
  /// starts as [MediaVisibility.private]; publishing is an explicit,
  /// later choice made by the owner.
  MediaVisibility visibility;

  /// Only meaningful once [visibility] is public: personal trip vs
  /// work/portfolio content.
  MediaCategory? category;

  /// Id of the Supabase user who uploaded this picture.
  /// Used to decide who is allowed to edit or delete it.
  String? userId;

  /// Full name ("Nome Cognome") of the uploader, resolved from the
  /// `profiles` table. Not stored in the media row itself: it is filled
  /// in at runtime so that the picture can show who posted it.
  String? ownerDisplayName;

  static const List<String> emotionLabels = [
    '\u2728 Inspired',
    '\u{1F30A} Relaxed',
    '\u{1F305} Nostalgic',
    '\u{1F929} Excited',
    '\u{1F343} At peace',
  ];

  Media({
    String? id,
    required this.filePath,
    required this.type,
    required this.grading,
    required this.moodRating,
    required this.fileName,
    required this.lastModification,
    required this.tags,
    this.storyNote,
    this.remoteUrl,
    this.memoryBytes,
    this.travelDate,
    this.visibility = MediaVisibility.private,
    this.category,
    this.userId,
    this.ownerDisplayName,
  }) : id = id ?? const Uuid().v4();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Media && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;

  String get emotionLabel {
    if (moodRating >= 0 && moodRating < emotionLabels.length) {
      return emotionLabels[moodRating];
    }
    return emotionLabels[0];
  }

  /// URL to feed into Image.network.
  /// Returns remoteUrl when set, or filePath when it already is a http(s) URL.
  String? get publicUrl {
    if (remoteUrl != null && remoteUrl!.isNotEmpty) return remoteUrl;
    if (filePath.startsWith('http://') || filePath.startsWith('https://')) {
      return filePath;
    }
    return null;
  }

  Future<String> getAbsolutePath() async {
    if (kIsWeb) {
      return remoteUrl ?? filePath;
    }
    try {
      final directory = await getApplicationSupportDirectory();
      return path.join(directory.path, filePath);
    } catch (_) {
      return filePath;
    }
  }

  void addTag(String tag) => tags.add(tag);

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'path': filePath,
      'type': type.name,
      'grading': grading,
      'moodRating': moodRating,
      'name': fileName,
      'lastModification': lastModification.toIso8601String(),
      'tags': tags,
      'storyNote': storyNote,
      'remoteUrl': remoteUrl,
      'travelDate': travelDate?.toIso8601String(),
      'visibility': visibility.toDb,
      'category': category?.toDb,
      'userId': userId,
      'ownerDisplayName': ownerDisplayName,
    };
  }

  factory Media.fromJson(Map<String, dynamic> json) {
    return Media(
      id: json['id'] as String?,
      filePath: json['path'] as String? ?? '',
      type: MediaType.image,
      grading: (json['grading'] as num?)?.toDouble() ?? 0.0,
      moodRating: (json['moodRating'] as num?)?.toInt() ?? 0,
      fileName: json['name'] as String? ?? 'Memory',
      lastModification: json['lastModification'] != null
          ? DateTime.tryParse(json['lastModification'] as String) ?? DateTime.now()
          : DateTime.now(),
      tags: json['tags'] != null ? List<String>.from(json['tags'] as List) : <String>[],
      storyNote: json['storyNote'] as String?,
      remoteUrl: json['remoteUrl'] as String?,
      travelDate: json['travelDate'] != null
          ? DateTime.tryParse(json['travelDate'] as String)
          : null,
      visibility: MediaVisibility.fromDb(json['visibility'] as String?),
      category: MediaCategory.fromDb(json['category'] as String?),
      userId: json['userId'] as String?,
      ownerDisplayName: json['ownerDisplayName'] as String?,
    );
  }

  factory Media.fromSupabase(Map<String, dynamic> row, {String? publicUrl}) {
    return Media(
      id: row['id'] as String?,
      filePath: row['storage_path'] as String? ?? '',
      type: MediaType.image,
      grading: (row['grading'] as num?)?.toDouble() ?? 0.0,
      moodRating: (row['mood_rating'] as num?)?.toInt() ?? 0,
      fileName: row['file_name'] as String? ?? 'Memory',
      lastModification: row['last_modification'] != null
          ? DateTime.tryParse(row['last_modification'] as String) ?? DateTime.now()
          : DateTime.now(),
      tags: row['tags'] != null ? List<String>.from(row['tags'] as List) : <String>[],
      storyNote: row['story_note'] as String?,
      remoteUrl: publicUrl,
      travelDate: row['travel_date'] != null
          ? DateTime.tryParse(row['travel_date'].toString())
          : null,
      visibility: MediaVisibility.fromDb(row['visibility'] as String?),
      category: MediaCategory.fromDb(row['category'] as String?),
      userId: row['user_id'] as String?,
    );
  }

  Map<String, dynamic> toSupabase(String locationId, String fallbackUserId) {
    return {
      'id': id,
      'location_id': locationId,
      // Never overwrite the original uploader: if this media already has an
      // owner, keep it, so an admin editing someone else's picture does not
      // silently take it over.
      'user_id': userId ?? fallbackUserId,
      'storage_path': filePath,
      'type': type.name,
      'file_name': fileName,
      'grading': grading,
      'mood_rating': moodRating,
      'tags': tags,
      'story_note': storyNote,
      'last_modification': lastModification.toIso8601String(),
      'travel_date': (travelDate ?? lastModification).toIso8601String().split('T').first,
      'visibility': visibility.toDb,
      'category': category?.toDb,
    };
  }
}
