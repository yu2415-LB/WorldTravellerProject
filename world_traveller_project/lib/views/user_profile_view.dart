import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:world_traveller_project/components/media_results_grid.dart';
import 'package:world_traveller_project/main.dart';
import 'package:world_traveller_project/models/user_profile.dart';
import 'package:world_traveller_project/providers/location_managing_controller.dart';
import 'package:world_traveller_project/providers/social_controller.dart';

/// Everything a single traveller has posted, plus a way to contact them.
class UserProfileView extends StatefulWidget {
  final String userId;
  final UserProfile? preloadedProfile;

  const UserProfileView({
    super.key,
    required this.userId,
    this.preloadedProfile,
  });

  @override
  State<UserProfileView> createState() => _UserProfileViewState();
}

class _UserProfileViewState extends State<UserProfileView> {
  UserProfile? _profile;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _profile = widget.preloadedProfile;

    if (_profile == null) {
      _loading = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        final profile =
            await context.read<SocialController>().loadProfile(widget.userId);
        if (!mounted) return;
        setState(() {
          _profile = profile;
          _loading = false;
        });
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<LocationManagingController>();
    final social = context.watch<SocialController>();

    final theirMedia = <LocatedMedia>[];
    for (final location in controller.locations) {
      for (final media in location.mediaSet) {
        if (media.userId == widget.userId) {
          theirMedia.add(LocatedMedia(media: media, location: location));
        }
      }
    }

    theirMedia.sort((a, b) =>
        b.media.lastModification.compareTo(a.media.lastModification));

    final profile = _profile;
    final displayName = profile != null ? profile.fullName : 'Traveller';

    return Scaffold(
      appBar: AppBar(title: Text(displayName)),
      body: Column(
        children: [
          _buildHeader(context, profile, theirMedia.length, social),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : MediaResultsGrid(
                    items: theirMedia,
                    emptyIcon: Icons.photo_library_outlined,
                    emptyTitle: 'Nothing posted yet',
                    emptySubtitle:
                        'This traveller has not shared any memories so far.',
                    onChanged: () => setState(() {}),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    UserProfile? profile,
    int count,
    SocialController social,
  ) {
    final theme = Theme.of(context);

    // Admin-only moderation actions: hidden entirely for a normal
    // traveller, and never shown on the admin's own profile.
    final showAdminActions = social.isCurrentUserAdmin &&
        profile != null &&
        profile.id != social.myProfile?.id;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 30,
                backgroundColor: theme.colorScheme.primaryContainer,
                backgroundImage: (profile?.avatarUrl != null &&
                        profile!.avatarUrl!.isNotEmpty)
                    ? NetworkImage(profile.avatarUrl!)
                    : null,
                child: (profile?.avatarUrl == null ||
                        profile!.avatarUrl!.isEmpty)
                    ? Text(
                        profile?.initial ?? '?',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            profile != null
                                ? profile.fullName
                                : 'Unknown traveller',
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        if (profile?.isBlocked == true) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.errorContainer,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              'Blocked',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.onErrorContainer,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$count memor${count == 1 ? 'y' : 'ies'} shared',
                      style:
                          TextStyle(color: Colors.grey.shade600, fontSize: 13),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: profile == null
                    ? null
                    : () => showContactDialog(context, profile),
                icon: const Icon(Icons.mail_outline, size: 18),
                label: const Text('Contact'),
              ),
            ],
          ),
          if (showAdminActions) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.shield_outlined,
                    size: 16, color: theme.colorScheme.tertiary),
                const SizedBox(width: 6),
                Text(
                  'Admin actions',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.tertiary,
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: () => _showWarnDialog(context, profile),
                  icon: const Icon(Icons.report_outlined, size: 16),
                  label: const Text('Warn'),
                  style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () => _showBlockDialog(context, profile),
                  icon: Icon(
                    profile.isBlocked ? Icons.lock_open_outlined : Icons.block,
                    size: 16,
                  ),
                  label: Text(profile.isBlocked ? 'Unblock' : 'Block'),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    foregroundColor:
                        profile.isBlocked ? null : theme.colorScheme.error,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// Admin popup for a first-step warning, sent to the traveller's
  /// private mailbox before any blocking happens.
  Future<void> _showWarnDialog(
      BuildContext context, UserProfile profile) async {
    final controller = TextEditingController(
      text: 'This is a warning from the World Traveller team: some of your '
          'content does not respect our terms of use. Please review it, or '
          'your account may be blocked.',
    );

    final send = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Warn ${profile.firstName}'),
        content: SizedBox(
          width: 420,
          child: TextField(
            controller: controller,
            maxLines: 5,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Message',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Send warning'),
          ),
        ],
      ),
    );

    if (send != true || !context.mounted) return;
    final body = controller.text.trim();
    if (body.isEmpty) return;

    try {
      await context.read<SocialController>().warnUser(profile.id, body);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Warning sent to ${profile.firstName}.')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not send the warning: $e')),
      );
    }
  }

  /// Admin popup to block (or unblock) an account. A blocked traveller
  /// can no longer sign in, but their existing content stays visible —
  /// this is about stopping further activity, not erasing the past.
  Future<void> _showBlockDialog(
      BuildContext context, UserProfile profile) async {
    final willBlock = !profile.isBlocked;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(willBlock
            ? 'Block ${profile.firstName}?'
            : 'Unblock ${profile.firstName}?'),
        content: Text(
          willBlock
              ? '${profile.firstName} will no longer be able to sign in, '
                  'add pictures, or edit anything. Their existing pictures '
                  'stay visible in the General World.'
              : '${profile.firstName} will be able to sign in again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: willBlock
                ? FilledButton.styleFrom(backgroundColor: Colors.red)
                : null,
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(willBlock ? 'Block' : 'Unblock'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    try {
      await context
          .read<SocialController>()
          .setUserBlocked(profile.id, willBlock);
      if (!context.mounted) return;
      setState(() {
        _profile = UserProfile(
          id: profile.id,
          publicId: profile.publicId,
          firstName: profile.firstName,
          lastName: profile.lastName,
          avatarUrl: profile.avatarUrl,
          role: profile.role,
          email: profile.email,
          bio: profile.bio,
          createdAt: profile.createdAt,
          isBlocked: willBlock,
        );
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            willBlock
                ? '${profile.firstName} has been blocked.'
                : '${profile.firstName} has been unblocked.',
          ),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update this account: $e')),
      );
    }
  }
}

/// "Contact" popup (Phase 4 — Privacy e Sicurezza).
///
/// Checks the CURRENT state of the relationship before doing anything,
/// so the user can never spam the same person with duplicate requests:
///
///  * never contacted  → normal "do you want to ask?" dialog
///  * already sent     → informative popup ("request already pending")
///  * they contacted me first → point them to the Mailbox
///  * already accepted → show the shared email straight away, with Copy
Future<void> showContactDialog(
    BuildContext context, UserProfile profile) async {
  final theme = Theme.of(context);

  if (!await ensureLoggedIn(context)) return;
  if (!context.mounted) return;

  final social = context.read<SocialController>();
  if (social.myProfile?.id == profile.id) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text("You can't send a request to yourself.")),
    );
    return;
  }

  // Look up the existing relationship BEFORE opening any dialog.
  final status = await social.contactStatusWith(profile.id);
  if (!context.mounted) return;

  // --- Case 1: already accepted. Show the shared email and stop here.
  if (status?.status == 'accepted') {
    await _showAcceptedEmailDialog(context, profile, status?.email);
    return;
  }

  // --- Case 2: I already sent a pending request.
  if (status?.status == 'sent') {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Request already sent to ${profile.firstName}'),
        content: const Text(
          'You already asked this traveller to get in touch.\n\n'
          'You will get a notification in your Mailbox when they reply.\n\n'
          'You cannot send more than one request at a time.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
    return;
  }

  // --- Case 3: they already contacted me, I have not replied yet.
  if (status?.status == 'received') {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('${profile.firstName} already contacted you'),
        content: const Text(
          'This traveller has already sent you a contact request. '
          'Open your Mailbox to accept or decline it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
        ],
      ),
    );
    return;
  }

  // --- Case 4: never contacted each other. Show the send dialog.
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Padding(
          padding: const EdgeInsets.all(26),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: theme.colorScheme.primaryContainer,
                    backgroundImage: (profile.avatarUrl != null &&
                            profile.avatarUrl!.isNotEmpty)
                        ? NetworkImage(profile.avatarUrl!)
                        : null,
                    child: (profile.avatarUrl == null ||
                            profile.avatarUrl!.isEmpty)
                        ? Text(
                            profile.initial,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.onPrimaryContainer,
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      profile.fullNameWithId,
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(dialogContext).pop(false),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.lock_outline,
                      size: 18, color: theme.colorScheme.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'For privacy, email addresses are never shown on '
                      'World Traveller.',
                      style: TextStyle(
                          color: Colors.grey.shade600, fontSize: 12.5),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'Do you want to ask ${profile.firstName} to contact you?',
                style: const TextStyle(fontSize: 15),
              ),
              const SizedBox(height: 4),
              Text(
                "They'll get a private notification in their mailbox — "
                'nothing is shared with anyone else.',
                style:
                    TextStyle(color: Colors.grey.shade600, fontSize: 12.5),
              ),
              const SizedBox(height: 22),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(false),
                    child: const Text('No'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () => Navigator.of(dialogContext).pop(true),
                    child: const Text('Yes, ask them'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );

  if (confirmed != true) return;
  if (!context.mounted) return;

  try {
    final sent = await social.sendContactRequest(profile.id);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          sent
              ? 'Request sent to ${profile.firstName}.'
              : 'Could not send the request.',
        ),
      ),
    );
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Could not send the request: $e')),
    );
  }
}

/// Popup shown when the contact has already been accepted. Displays the
/// shared email address with a Copy button. If the accepter chose not to
/// share an address, explains that politely instead of leaving a blank.
Future<void> _showAcceptedEmailDialog(
  BuildContext context,
  UserProfile profile,
  String? email,
) async {
  final theme = Theme.of(context);
  final hasEmail = email != null && email.trim().isNotEmpty;

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Padding(
          padding: const EdgeInsets.all(26),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: theme.colorScheme.tertiaryContainer,
                    child: Icon(Icons.check_circle_outline,
                        color: theme.colorScheme.onTertiaryContainer),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      'You can contact ${profile.firstName}!',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(dialogContext).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              if (hasEmail) ...[
                Text(
                  "Here is ${profile.firstName}'s email:",
                  style:
                      TextStyle(color: Colors.grey.shade600, fontSize: 13),
                ),
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.tertiaryContainer
                        .withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.alternate_email,
                          size: 18,
                          color: theme.colorScheme.onTertiaryContainer),
                      const SizedBox(width: 10),
                      Expanded(
                        child: SelectableText(
                          email,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.onTertiaryContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      child: const Text('Close'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      icon: const Icon(Icons.copy, size: 16),
                      label: const Text('Copy'),
                      onPressed: () async {
                        final messenger = ScaffoldMessenger.of(context);
                        await Clipboard.setData(ClipboardData(text: email));
                        if (dialogContext.mounted) {
                          Navigator.of(dialogContext).pop();
                        }
                        messenger.showSnackBar(
                          const SnackBar(content: Text('Email copied')),
                        );
                      },
                    ),
                  ],
                ),
              ] else ...[
                const Text(
                  'This traveller accepted your request, but did not share '
                  'an email address. You can try reaching out through their '
                  'profile.',
                ),
                const SizedBox(height: 18),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: const Text('Got it'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}