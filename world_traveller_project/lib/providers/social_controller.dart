import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:world_traveller_project/models/mailbox_message.dart';
import 'package:world_traveller_project/models/media.dart';
import 'package:world_traveller_project/models/user_profile.dart';
import 'package:world_traveller_project/services/mailbox_service.dart';
import 'package:world_traveller_project/services/profile_service.dart';

/// Keeps track of everything "social": who the signed in traveller is,
/// which pictures they liked, the usernames shown on each picture, and
/// (Phase 4) how many unread "please contact me" requests are sitting
/// in their private mailbox.
class SocialController extends ChangeNotifier {
  final ProfileService _service = ProfileService();
  final MailboxService _mailboxService = MailboxService();

  UserProfile? _myProfile;
  final Set<String> _favouriteIds = {};
  final Map<String, UserProfile> _profileCache = {};
  bool _loading = false;
  int _unreadMailboxCount = 0;

  UserProfile? get myProfile => _myProfile;
  Set<String> get favouriteIds => Set.unmodifiable(_favouriteIds);
  bool get isLoading => _loading;

  /// How many unread contact requests are waiting in "my" mailbox —
  /// shown as a small badge next to the mailbox icon.
  int get unreadMailboxCount => _unreadMailboxCount;

  SupabaseClient get _client => Supabase.instance.client;
  String? get _currentUserId => _client.auth.currentUser?.id;

  bool isFavourite(String mediaId) => _favouriteIds.contains(mediaId);

  /// True when the signed-in traveller is the platform administrator.
  /// Backed by the `role` column now (see SUPABASE_SETUP_PHASE1.sql)
  /// instead of a hard-coded email address.
  bool get isCurrentUserAdmin => _myProfile?.isAdmin ?? false;

  /// True when the signed-in traveller's own account has been blocked
  /// by the administrator. main.dart checks this right after sign-in
  /// and immediately signs the person back out when it's true.
  bool get isCurrentUserBlocked => _myProfile?.isBlocked ?? false;

  /// "Nome Cognome" to display for a given uploader, when we already
  /// know it (falls back to their unique ID if only that is on file).
  String? displayNameFor(String? userId) {
    if (userId == null || userId.isEmpty) return null;
    return _profileCache[userId]?.fullName;
  }

  UserProfile? profileFor(String? userId) {
    if (userId == null || userId.isEmpty) return null;
    return _profileCache[userId];
  }

  /// Call after login/logout and on app start.
  Future<void> refreshForCurrentUser() async {
    final userId = _currentUserId;

    if (userId == null) {
      _myProfile = null;
      _favouriteIds.clear();
      _unreadMailboxCount = 0;
      notifyListeners();
      return;
    }

    _loading = true;
    notifyListeners();

    try {
      final profile = await _service.fetchProfile(userId);
      final favourites = await _service.fetchFavouriteIds(userId);
      final unread = await _mailboxService.unreadCount(userId);

      _myProfile = profile;
      if (profile != null) {
        _profileCache[profile.id] = profile;
      }
      _favouriteIds
        ..clear()
        ..addAll(favourites);
      _unreadMailboxCount = unread;
    } catch (e) {
      debugPrint('Could not refresh social data: $e');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Re-reads just the unread mailbox count, used after opening the
  /// inbox or sending/receiving a contact request, without re-fetching
  /// the whole profile + favourites.
  Future<void> refreshMailboxCount() async {
    final userId = _currentUserId;
    if (userId == null) return;
    try {
      _unreadMailboxCount = await _mailboxService.unreadCount(userId);
      notifyListeners();
    } catch (e) {
      debugPrint('Could not refresh mailbox count: $e');
    }
  }

  /// Sends a "please get in touch" request to [recipientId] on behalf
  /// of the signed-in traveller. Returns false when nobody is signed
  /// in (the caller should then ask them to log in).
  Future<bool> sendContactRequest(String recipientId) async {
    final userId = _currentUserId;
    if (userId == null) return false;
    if (userId == recipientId) return false;

    await _mailboxService.sendContactRequest(
      senderId: userId,
      recipientId: recipientId,
    );
    return true;
  }

  /// Sends a terms-of-use warning to [recipientId]. Only meant to be
  /// called when [isCurrentUserAdmin] is true — Supabase refuses it
  /// otherwise regardless.
  Future<void> warnUser(String recipientId, String body) async {
    final adminId = _currentUserId;
    if (adminId == null) return;
    await _mailboxService.sendWarning(
      adminId: adminId,
      recipientId: recipientId,
      body: body,
    );
  }

  /// Blocks or unblocks [userId]'s account. Only meant to be called
  /// when [isCurrentUserAdmin] is true.
  Future<void> setUserBlocked(String userId, bool blocked) async {
    await _service.setBlocked(userId: userId, blocked: blocked);
    // Keep any cached copy of that profile in sync so the UI updates
    // straight away without a full reload.
    final cached = _profileCache[userId];
    if (cached != null) {
      _profileCache[userId] = UserProfile(
        id: cached.id,
        publicId: cached.publicId,
        firstName: cached.firstName,
        lastName: cached.lastName,
        avatarUrl: cached.avatarUrl,
        role: cached.role,
        email: cached.email,
        bio: cached.bio,
        createdAt: cached.createdAt,
        isBlocked: blocked,
      );
      notifyListeners();
    }
  }

  Future<List<MailboxMessage>> fetchMyInbox() async {
    final userId = _currentUserId;
    if (userId == null) return [];
    return _mailboxService.fetchInbox(userId);
  }

  Future<void> markMailboxMessageRead(String messageId) async {
    await _mailboxService.markAsRead(messageId);
    await refreshMailboxCount();
  }

  Future<void> deleteMailboxMessage(String messageId) async {
    await _mailboxService.deleteMessage(messageId);
    await refreshMailboxCount();
  }

  /// Makes sure we know the username of every uploader in [mediaItems],
  /// then writes it straight onto each Media so the widgets can show it.
  Future<void> resolveUsernames(Iterable<Media> mediaItems) async {
    final missing = mediaItems
        .map((m) => m.userId)
        .whereType<String>()
        .where((id) => id.isNotEmpty && !_profileCache.containsKey(id))
        .toSet();

    if (missing.isNotEmpty) {
      final fetched = await _service.fetchProfiles(missing);
      _profileCache.addAll(fetched);
    }

    var changed = false;
    for (final media in mediaItems) {
      final displayName = displayNameFor(media.userId);
      if (displayName != null && media.ownerDisplayName != displayName) {
        media.ownerDisplayName = displayName;
        changed = true;
      }
    }

    if (changed) notifyListeners();
  }

  /// Adds or removes a like. Returns the new state, or null when the user
  /// is not signed in (the caller should then ask them to log in).
  Future<bool?> toggleFavourite(String mediaId) async {
    final userId = _currentUserId;
    if (userId == null) return null;

    final wasFavourite = _favouriteIds.contains(mediaId);

    // Update the UI immediately, roll back if the server refuses.
    if (wasFavourite) {
      _favouriteIds.remove(mediaId);
    } else {
      _favouriteIds.add(mediaId);
    }
    notifyListeners();

    try {
      if (wasFavourite) {
        await _service.removeFavourite(userId, mediaId);
      } else {
        await _service.addFavourite(userId, mediaId);
      }
      return !wasFavourite;
    } catch (e) {
      debugPrint('Could not toggle favourite: $e');
      if (wasFavourite) {
        _favouriteIds.add(mediaId);
      } else {
        _favouriteIds.remove(mediaId);
      }
      notifyListeners();
      return wasFavourite;
    }
  }

  Future<List<UserProfile>> searchUsers(String query) async {
    final results = await _service.searchProfiles(query);
    for (final profile in results) {
      _profileCache[profile.id] = profile;
    }
    return results;
  }

  Future<UserProfile?> loadProfile(String userId) async {
    final cached = _profileCache[userId];
    if (cached != null) return cached;

    final profile = await _service.fetchProfile(userId);
    if (profile != null) {
      _profileCache[profile.id] = profile;
      notifyListeners();
    }
    return profile;
  }
}
