/// Which of the app's "two worlds" a picture currently belongs to.
///
/// * [private] = "My Work": only the uploader can ever see it.
/// * [public]  = "General World": shown in the public feed to everyone.
///
/// Every newly uploaded picture starts as [private] — publishing is an
/// explicit choice the owner makes later, never the default.
enum MediaVisibility {
  private,
  public;

  static MediaVisibility fromDb(String? value) {
    return value == 'public' ? MediaVisibility.public : MediaVisibility.private;
  }

  String get toDb => this == MediaVisibility.public ? 'public' : 'private';

  bool get isPublic => this == MediaVisibility.public;
}

/// Inside the public "General World", a picture is further tagged as
/// either a personal trip or professional work/portfolio content.
/// Only meaningful once a picture is [MediaVisibility.public]; a private
/// "My Work" picture has no category yet.
enum MediaCategory {
  personalTrip,
  workPortfolio;

  static MediaCategory? fromDb(String? value) {
    switch (value) {
      case 'personal':
        return MediaCategory.personalTrip;
      case 'work':
        return MediaCategory.workPortfolio;
      default:
        return null;
    }
  }

  String? get toDb {
    switch (this) {
      case MediaCategory.personalTrip:
        return 'personal';
      case MediaCategory.workPortfolio:
        return 'work';
    }
  }

  String get label {
    switch (this) {
      case MediaCategory.personalTrip:
        return 'Personal trip';
      case MediaCategory.workPortfolio:
        return 'Work / Portfolio';
    }
  }
}

/// The two sections the bottom toggle switches between.
enum WorldScope {
  /// Private storage: only the signed-in user's own pictures, regardless
  /// of their [MediaVisibility] (an unpublished "My Work" picture stays
  /// here even if the owner later plans to publish it).
  myWork,

  /// Public feed: every picture anyone has marked [MediaVisibility.public].
  generalWorld,
}
