import 'package:world_traveller_project/models/user_profile.dart';

/// What kind of notification a [MailboxMessage] carries.
enum MailboxMessageType {
  /// "Someone would like you to get in touch" — the original Phase 4
  /// contact request. Carries no free text.
  contactRequest,

  /// "X accepted your request — you can get in touch now". Created
  /// when the recipient of a [contactRequest] taps Accept.
  contactAccepted,

  /// A warning from the administrator about a terms-of-use violation,
  /// sent before any account gets blocked. Carries [MailboxMessage.body].
  warning;

  static MailboxMessageType fromDb(String? value) {
    switch (value) {
      case 'warning':
        return MailboxMessageType.warning;
      case 'contact_accepted':
        return MailboxMessageType.contactAccepted;
      case 'contact_request':
      default:
        return MailboxMessageType.contactRequest;
    }
  }

  String toDb() => switch (this) {
        MailboxMessageType.warning => 'warning',
        MailboxMessageType.contactRequest => 'contact_request',
        MailboxMessageType.contactAccepted => 'contact_accepted',
      };
}

/// One entry in a traveller's private "mailbox" ("buchetta della
/// posta"): either a notification that another traveller would like to
/// be contacted (created when someone answers "yes" to the "Contact"
/// popup on a profile — no email address is ever attached to this), or
/// a warning message sent by the administrator about a terms-of-use
/// violation.
class MailboxMessage {
  final String id;
  final String recipientId;
  final String senderId;
  final DateTime createdAt;
  final bool isRead;
  final MailboxMessageType type;

  /// Free text, only set for [MailboxMessageType.warning] messages.
  final String? body;

  /// Filled in by [MailboxService.fetchInbox] so the inbox screen can
  /// show who is asking to be contacted without a second round trip.
  final UserProfile? senderProfile;

  const MailboxMessage({
    required this.id,
    required this.recipientId,
    required this.senderId,
    required this.createdAt,
    required this.isRead,
    this.type = MailboxMessageType.contactRequest,
    this.body,
    this.senderProfile,
  });

  bool get isWarning => type == MailboxMessageType.warning;
  bool get isContactRequest => type == MailboxMessageType.contactRequest;
  bool get isContactAccepted => type == MailboxMessageType.contactAccepted;

  factory MailboxMessage.fromSupabase(
    Map<String, dynamic> row, {
    UserProfile? senderProfile,
  }) {
    return MailboxMessage(
      id: row['id']?.toString() ?? '',
      recipientId: row['recipient_id']?.toString() ?? '',
      senderId: row['sender_id']?.toString() ?? '',
      createdAt: DateTime.tryParse(row['created_at']?.toString() ?? '') ??
          DateTime.now(),
      isRead: row['is_read'] as bool? ?? false,
      type: MailboxMessageType.fromDb(row['type'] as String?),
      body: row['body'] as String?,
      senderProfile: senderProfile,
    );
  }

  MailboxMessage copyWith({bool? isRead}) {
    return MailboxMessage(
      id: id,
      recipientId: recipientId,
      senderId: senderId,
      createdAt: createdAt,
      isRead: isRead ?? this.isRead,
      type: type,
      body: body,
      senderProfile: senderProfile,
    );
  }
}
