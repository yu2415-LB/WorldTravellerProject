import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:world_traveller_project/models/mailbox_message.dart';
import 'package:world_traveller_project/models/user_profile.dart';
import 'package:world_traveller_project/providers/social_controller.dart';
import 'package:world_traveller_project/views/user_profile_view.dart';

/// The traveller's private "buchetta della posta": every "please get in
/// touch" request other travellers have sent them (Phase 4). Nobody's
/// email is ever shown here — this screen only tells you WHO would
/// like to hear from you, so you can decide whether to reach out.
class MailboxView extends StatefulWidget {
  const MailboxView({super.key});

  @override
  State<MailboxView> createState() => _MailboxViewState();
}

class _MailboxViewState extends State<MailboxView> {
  List<MailboxMessage>? _messages;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final social = context.read<SocialController>();
    final messages = await social.fetchMyInbox();
    if (!mounted) return;
    setState(() {
      _messages = messages;
      _loading = false;
    });

    // Opening the mailbox counts as reading it: mark every still-unread
    // entry as seen and refresh the little badge on the mailbox icon.
    final unread = messages.where((m) => !m.isRead);
    for (final message in unread) {
      await social.markMailboxMessageRead(message.id);
    }
  }

  Future<void> _delete(MailboxMessage message) async {
    final social = context.read<SocialController>();
    setState(() => _messages?.removeWhere((m) => m.id == message.id));
    try {
      await social.deleteMailboxMessage(message.id);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not delete: $e')));
      _load();
    }
  }

  Future<void> _accept(MailboxMessage message) async {
    final social = context.read<SocialController>();
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _messages?.removeWhere((m) => m.id == message.id));
    try {
      await social.acceptContactRequest(message);
      messenger.showSnackBar(SnackBar(
        content: Text('Accepted. ${message.senderProfile?.fullName ?? 'They'} will be notified.'),
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not accept: $e')));
      if (mounted) _load();
    }
  }

  Future<void> _decline(MailboxMessage message) async {
    final social = context.read<SocialController>();
    setState(() => _messages?.removeWhere((m) => m.id == message.id));
    try {
      await social.declineContactRequest(message.id);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not decline: $e')));
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final messages = _messages ?? const [];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mailbox'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : messages.isEmpty
              ? _EmptyMailbox(onRefresh: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: messages.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) =>
                        _MailboxTile(
                      message: messages[index],
                      onDelete: _delete,
                      onAccept: _accept,
                      onDecline: _decline,
                    ),
                  ),
                ),
    );
  }
}

class _EmptyMailbox extends StatelessWidget {
  final Future<void> Function() onRefresh;
  const _EmptyMailbox({required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(height: MediaQuery.of(context).size.height * 0.2),
          Icon(Icons.mail_outline, size: 56, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          Center(
            child: Text(
              'Your mailbox is empty',
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey.shade600),
            ),
          ),
          const SizedBox(height: 4),
          Center(
            child: Text(
              "When someone asks you to get in touch,\nit'll show up here.",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: Colors.grey.shade500),
            ),
          ),
        ],
      ),
    );
  }
}

class _MailboxTile extends StatelessWidget {
  final MailboxMessage message;
  final Future<void> Function(MailboxMessage) onDelete;
  final Future<void> Function(MailboxMessage) onAccept;
  final Future<void> Function(MailboxMessage) onDecline;

  const _MailboxTile({
    required this.message,
    required this.onDelete,
    required this.onAccept,
    required this.onDecline,
  });

  void _openProfile(BuildContext context, UserProfile sender) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => UserProfileView(
          userId: sender.id,
          preloadedProfile: sender,
        ),
      ),
    );
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 30) return '${diff.inDays}d ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sender = message.senderProfile;
    final name = sender?.fullName ?? (message.isWarning ? 'World Traveller admin' : 'A traveller');

    // A warning from the administrator stands out visually (a plain red
    // banner) from a normal "wants to contact you" tile, so it can't be
    // mistaken for routine social activity.
    final Color background = message.isWarning
        ? theme.colorScheme.errorContainer.withValues(alpha: 0.55)
        : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5);

    return Dismissible(
      key: ValueKey(message.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: theme.colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(Icons.delete_outline, color: theme.colorScheme.onErrorContainer),
      ),
      onDismissed: (_) => onDelete(message),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(14),
          border: message.isWarning
              ? Border.all(color: theme.colorScheme.error.withValues(alpha: 0.4))
              : null,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (message.isWarning)
              CircleAvatar(
                radius: 20,
                backgroundColor: theme.colorScheme.error,
                child: const Icon(Icons.report_outlined, color: Colors.white, size: 20),
              )
            else
              CircleAvatar(
                radius: 20,
                backgroundColor: theme.colorScheme.primaryContainer,
                backgroundImage: (sender?.avatarUrl != null && sender!.avatarUrl!.isNotEmpty)
                    ? NetworkImage(sender.avatarUrl!)
                    : null,
                child: (sender?.avatarUrl == null || sender!.avatarUrl!.isEmpty)
                    ? Text(
                        sender?.initial ?? '?',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      )
                    : null,
              ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (message.isWarning) ...[
                    Text(
                      'Warning from the admin',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: theme.colorScheme.onErrorContainer,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      message.body ?? '',
                      style: TextStyle(
                        fontSize: 13,
                        color: theme.colorScheme.onErrorContainer,
                      ),
                    ),
                  ] else
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: name,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                          TextSpan(
                            text: message.isContactAccepted
                                ? ' accepted your request \u2014 you can get in touch now!'
                                : ' would like you to get in touch',
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 4),
                  Text(
                    _timeAgo(message.createdAt),
                    style: TextStyle(
                      fontSize: 11.5,
                      color: message.isWarning
                          ? theme.colorScheme.onErrorContainer.withValues(alpha: 0.75)
                          : Colors.grey.shade600,
                    ),
                  ),
                  if (message.isContactRequest) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.icon(
                          icon: const Icon(Icons.check, size: 18),
                          label: const Text('Accept'),
                          onPressed: () => onAccept(message),
                        ),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.close, size: 18),
                          label: const Text('Decline'),
                          onPressed: () => onDecline(message),
                        ),
                        if (sender != null)
                          TextButton.icon(
                            icon: const Icon(Icons.person_outline, size: 18),
                            label: const Text('View profile'),
                            onPressed: () => _openProfile(context, sender),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (!message.isContactRequest) ...[
              if (message.isContactAccepted && sender != null)
                FilledButton.tonalIcon(
                  icon: const Icon(Icons.person_outline, size: 18),
                  label: const Text('View profile'),
                  onPressed: () => _openProfile(context, sender),
                ),
              IconButton(
                tooltip: 'Dismiss',
                icon: const Icon(Icons.close, size: 18),
                onPressed: () => onDelete(message),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
