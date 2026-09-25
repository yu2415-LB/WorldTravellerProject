import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:world_traveller_project/models/mailbox_message.dart';
import 'package:world_traveller_project/services/profile_service.dart';

/// Talks to the `mailbox_messages` table (Phase 4 — see
/// SUPABASE_SETUP_PHASE4.sql). This is the whole "Contact" flow: no
/// email address ever travels through this service, only a "someone
/// would like you to reach out" notification.
class MailboxService {
  static final MailboxService _instance = MailboxService._internal();
  factory MailboxService() => _instance;
  MailboxService._internal();

  final ProfileService _profileService = ProfileService();

  SupabaseClient get _client => Supabase.instance.client;

  static const String _table = 'mailbox_messages';

  /// Sends a "please get in touch" request to [recipientId] on behalf
  /// of the signed-in traveller.
  Future<void> sendContactRequest({
    required String senderId,
    required String recipientId,
  }) async {
    if (senderId == recipientId) return;

    await _client.from(_table).insert({
      'sender_id': senderId,
      'recipient_id': recipientId,
      'type': 'contact_request',
    });
  }

  /// Looks up the existing contact relationship between [myId] and
  /// [otherId] in BOTH directions, so the UI can refuse to send a
  /// duplicate request and can show the shared email straight away when
  /// the contact has already been accepted.
  ///
  /// Returns:
  ///  * `'accepted'` when a `contact_accepted` message exists either way.
  ///    [email] carries the address the accepter chose to share (or null
  ///    when they accepted without sharing one).
  ///  * `'sent'` when I have a pending `contact_request` to them.
  ///  * `'received'` when they have a pending `contact_request` to me.
  ///  * `null` when we have never contacted each other.
  Future<({String status, String? email})?> findContactWith(
    String myId,
    String otherId,
  ) async {
    if (myId.isEmpty || otherId.isEmpty || myId == otherId) return null;

    try {
      final rows = await _client
          .from(_table)
          .select()
          .or('and(sender_id.eq.$myId,recipient_id.eq.$otherId),'
              'and(sender_id.eq.$otherId,recipient_id.eq.$myId)')
          .order('created_at', ascending: false);

      final list = (rows as List)
          .map((r) => Map<String, dynamic>.from(r as Map))
          .toList();

      // Priority 1: an accepted contact (in either direction). The email
      // travels inside `body` — only the two parties can read this row.
      for (final row in list) {
        if (row['type'] == 'contact_accepted') {
          final email = (row['body'] as String?)?.trim();
          return (
            status: 'accepted',
            email: (email != null && email.isNotEmpty) ? email : null,
          );
        }
      }

      // Priority 2: a pending request I sent them.
      for (final row in list) {
        if (row['type'] == 'contact_request' &&
            row['sender_id']?.toString() == myId) {
          return (status: 'sent', email: null);
        }
      }

      // Priority 3: a pending request they sent me (waiting on my reply).
      for (final row in list) {
        if (row['type'] == 'contact_request' &&
            row['sender_id']?.toString() == otherId) {
          return (status: 'received', email: null);
        }
      }

      return null;
    } catch (e) {
      debugPrint('Could not check contact status: $e');
      return null;
    }
  }

  /// The recipient of a contact request said "yes": tell the person who
  /// asked (they get a `contact_accepted` entry in their own mailbox) and
  /// remove the original request so it can't be answered twice.
  Future<void> acceptContactRequest({
    required String requestId,
    required String accepterId,
    required String requesterId,
    String? accepterEmail,
  }) async {
    // The email travels in `body`: only the person who was accepted
    // can read this row, so it is shared with them and nobody else.
    await _client.from(_table).insert({
      'sender_id': accepterId,
      'recipient_id': requesterId,
      'type': 'contact_accepted',
      if (accepterEmail != null && accepterEmail.isNotEmpty)
        'body': accepterEmail,
    });
    await _client.from(_table).delete().eq('id', requestId);
  }

  /// The recipient said "no": the request simply disappears. Nobody is
  /// notified, so declining is always painless.
  Future<void> declineContactRequest(String requestId) async {
    await _client.from(_table).delete().eq('id', requestId);
  }

  /// Sends a terms-of-use warning to [recipientId], from the
  /// administrator, before the account is blocked. RLS on the
  /// `mailbox_messages` table restricts this to admin accounts only.
  Future<void> sendWarning({
    required String adminId,
    required String recipientId,
    required String body,
  }) async {
    await _client.from(_table).insert({
      'sender_id': adminId,
      'recipient_id': recipientId,
      'type': 'warning',
      'body': body,
    });
  }

  /// Everything sitting in [userId]'s own mailbox, most recent first,
  /// each entry carrying the sender's profile so the inbox can show a
  /// name and picture without extra round trips.
  Future<List<MailboxMessage>> fetchInbox(String userId) async {
    try {
      final rows = await _client
          .from(_table)
          .select()
          .eq('recipient_id', userId)
          .order('created_at', ascending: false);

      final list = (rows as List)
          .map((raw) => Map<String, dynamic>.from(raw as Map))
          .toList();

      final senderIds = list
          .map((row) => row['sender_id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toSet();
      final profiles = await _profileService.fetchProfiles(senderIds);

      return list
          .map((row) => MailboxMessage.fromSupabase(
                row,
                senderProfile: profiles[row['sender_id']?.toString()],
              ))
          .toList();
    } catch (e) {
      debugPrint('Could not load mailbox: $e');
      return [];
    }
  }

  /// How many unread requests are waiting for [userId] — shown as a
  /// small badge on the mailbox icon.
  Future<int> unreadCount(String userId) async {
    try {
      final rows = await _client
          .from(_table)
          .select('id')
          .eq('recipient_id', userId)
          .eq('is_read', false);
      return (rows as List).length;
    } catch (e) {
      debugPrint('Could not count unread mailbox entries: $e');
      return 0;
    }
  }

  Future<void> markAsRead(String messageId) async {
    await _client.from(_table).update({'is_read': true}).eq('id', messageId);
  }

  Future<void> markAllAsRead(String userId) async {
    await _client
        .from(_table)
        .update({'is_read': true})
        .eq('recipient_id', userId)
        .eq('is_read', false);
  }

  Future<void> deleteMessage(String messageId) async {
    await _client.from(_table).delete().eq('id', messageId);
  }
}