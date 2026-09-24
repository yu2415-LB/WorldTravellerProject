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

  /// Freeform "how does it make you feel" text. Either one of
  /// [standardMoods] or something the person typed themselves after
  /// picking "Other..." — [isStandardMood] tells the two apart.
  String? mood;

  /// The technical name of the uploaded file (e.g.
  /// "IMG_8410_Original.jpeg"). Never shown to the person and never
  /// edited by them — see [title] for the caption they actually write.
  String fileName;

  /// The caption the traveller gives their picture ("Sunset over the
  /// hills"). Kept separate from [fileName] on purpose: editing the
  /// title must never rename the underlying file, and a raw file name
  /// (extension included) is not something anyone should see as a
  /// "title" in the first place.
  String? title;

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

  /// Alias kept for readability where the list is used as "the standard,
  /// selectable moods" rather than as display labels.
  static const List<String> standardMoods = emotionLabels;

  Media({
    String? id,
    required this.filePath,
    required this.type,
    required this.grading,
    this.mood,
    required this.fileName,
    this.title,
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

  /// What to show as this picture's title: the caption the person wrote,
  /// or a plain, friendly placeholder — never the raw uploaded file name.
  String get displayTitle {
    final t = title?.trim();
    return (t != null && t.isNotEmpty) ? t : 'Untitled memory';
  }

  /// The mood text to show, or null when none was ever picked.
  String? get emotionLabel => (mood != null && mood!.trim().isNotEmpty) ? mood : null;

  /// True when [mood] is one of the five preset feelings rather than
  /// something the person typed in after choosing "Other...".
  bool get isStandardMood => mood != null && standardMoods.contains(mood);

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
      'mood': mood,
      'name': fileName,
      'title': title,
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
      mood: _readMood(json['mood'], json['moodRating']),
      fileName: json['name'] as String? ?? 'Memory',
      title: json['title'] as String?,
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
      mood: _readMood(row['mood'], row['mood_rating']),
      fileName: row['file_name'] as String? ?? 'Memory',
      title: row['title'] as String?,
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

  /// Reads the freeform mood text, falling back to translating an old
  /// numeric `mood_rating` index (from before this field existed) into
  /// its matching label, so rows saved by an older version of the app
  /// still show a sensible mood instead of nothing.
  static String? _readMood(dynamic moodValue, dynamic legacyIndex) {
    if (moodValue is String && moodValue.trim().isNotEmpty) return moodValue;
    final index = (legacyIndex as num?)?.toInt();
    if (index != null && index >= 0 && index < emotionLabels.length) {
      return emotionLabels[index];
    }
    return null;
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
      'title': title,
      'grading': grading,
      'mood': mood,
      'tags': tags,
      'story_note': storyNote,
      'last_modification': lastModification.toIso8601String(),
      'travel_date': (travelDate ?? lastModification).toIso8601String().split('T').first,
      'visibility': visibility.toDb,
      'category': category?.toDb,
    };
  }
}
