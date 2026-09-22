import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:world_traveller_project/main.dart';
import 'package:world_traveller_project/providers/social_controller.dart';
import 'package:world_traveller_project/services/profile_service.dart';
import 'package:world_traveller_project/services/supabase_storage_service.dart';
import 'package:world_traveller_project/views/mailbox_view.dart';

/// "My Account" (Fase 2, punto 9): a deliberately compact screen — short
/// rows, no full-width dividers or bars — for editing the traveller's
/// name and profile picture, and for signing out.
class MyAccountView extends StatefulWidget {
  const MyAccountView({super.key});

  @override
  State<MyAccountView> createState() => _MyAccountViewState();
}

class _MyAccountViewState extends State<MyAccountView> {
  final _profileService = ProfileService();
  final _storageService = SupabaseStorageService();
  final _picker = ImagePicker();

  late final TextEditingController _firstNameCtrl;
  late final TextEditingController _lastNameCtrl;

  bool _savingName = false;
  bool _uploadingAvatar = false;
  double? _avatarProgress;

  @override
  void initState() {
    super.initState();
    final me = context.read<SocialController>().myProfile;
    _firstNameCtrl = TextEditingController(text: me?.firstName ?? '');
    _lastNameCtrl = TextEditingController(text: me?.lastName ?? '');
  }

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveName() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    final first = _firstNameCtrl.text.trim();
    final last = _lastNameCtrl.text.trim();
    if (first.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('First name cannot be empty.')));
      return;
    }

    setState(() => _savingName = true);
    try {
      await _profileService.saveProfile(userId: userId, firstName: first, lastName: last);
      if (!mounted) return;
      await context.read<SocialController>().refreshForCurrentUser();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not save: $e')));
    } finally {
      if (mounted) setState(() => _savingName = false);
    }
  }

  Future<void> _changeAvatar() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    final picked = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked == null) return;

    setState(() {
      _uploadingAvatar = true;
      _avatarProgress = null;
    });

    try {
      final bytes = await picked.readAsBytes();
      final url = await _storageService.uploadAvatar(
        userId: userId,
        bytes: bytes,
        fileName: picked.name,
      );
      await _profileService.updateAvatar(userId: userId, avatarUrl: url);
      if (!mounted) return;
      await context.read<SocialController>().refreshForCurrentUser();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not update photo: $e')));
    } finally {
      if (mounted) setState(() => _uploadingAvatar = false);
    }
  }

  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Sign out'),
        content: Text('You are signed in as:\n${supabase.auth.currentUser?.email ?? ''}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await supabase.auth.signOut();
    if (!mounted) return;
    await context.read<SocialController>().refreshForCurrentUser();
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final social = context.watch<SocialController>();
    final me = social.myProfile;

    return Scaffold(
      appBar: AppBar(title: const Text('My Account')),
      body: ListView(
        // Compact everywhere: tight padding, small gaps, no long bars.
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          // --- Avatar + quick identity row -------------------------------
          Row(
            children: [
              Stack(
                alignment: Alignment.bottomRight,
                children: [
                  CircleAvatar(
                    radius: 34,
                    backgroundColor: theme.colorScheme.primaryContainer,
                    backgroundImage: (me?.avatarUrl != null && me!.avatarUrl!.isNotEmpty)
                        ? NetworkImage(me.avatarUrl!)
                        : null,
                    child: _uploadingAvatar
                        ? SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.4,
                              value: _avatarProgress,
                              color: theme.colorScheme.onPrimaryContainer,
                            ),
                          )
                        : (me?.avatarUrl == null || me!.avatarUrl!.isEmpty)
                            ? Text(
                                me?.initial ?? '?',
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  color: theme.colorScheme.onPrimaryContainer,
                                ),
                              )
                            : null,
                  ),
                  Tooltip(
                    message: 'Change profile picture',
                    child: Material(
                      color: theme.colorScheme.primary,
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: _uploadingAvatar ? null : _changeAvatar,
                        child: const Padding(
                          padding: EdgeInsets.all(5),
                          child: Icon(Icons.edit, size: 14, color: Colors.white),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      me?.fullName ?? 'Traveller',
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    if (me != null) ...[
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              me.publicId,
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          IconButton(
                            tooltip: 'Copy ID',
                            icon: const Icon(Icons.copy, size: 14),
                            visualDensity: VisualDensity.compact,
                            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                            padding: EdgeInsets.zero,
                            onPressed: () async {
                              await Clipboard.setData(ClipboardData(text: me.publicId));
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('ID copied.')),
                              );
                            },
                          ),
                          if (me.isAdmin)
                            Container(
                              margin: const EdgeInsets.only(left: 2),
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.tertiaryContainer,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                'Admin',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: theme.colorScheme.onTertiaryContainer,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),
          Text('Name', style: theme.textTheme.labelLarge?.copyWith(color: Colors.grey.shade600)),
          const SizedBox(height: 6),

          // --- Compact name fields side by side, not full-width bars -----
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _firstNameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'First name',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _lastNameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Last name',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: _savingName ? null : _saveName,
              icon: _savingName
                  ? const SizedBox(
                      width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.check, size: 18),
              label: const Text('Save'),
            ),
          ),

          const SizedBox(height: 24),

          // --- Short, self-contained rows instead of long dividers -------
          _CompactAccountRow(
            icon: Icons.mail_outline,
            label: 'Email',
            value: supabase.auth.currentUser?.email ?? '—',
            trailingNote: 'Only visible to you',
          ),
          const SizedBox(height: 8),
          _CompactAccountRow(
            icon: Icons.verified_user_outlined,
            label: 'Role',
            value: me?.isAdmin == true ? 'Administrator' : 'Standard traveller',
          ),

          const SizedBox(height: 8),
          // --- Mailbox shortcut ("buchetta della posta") -----------------
          Material(
            color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const MailboxView()),
                );
                if (mounted) setState(() {});
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(
                  children: [
                    Icon(Icons.markunread_mailbox_outlined,
                        size: 18, color: theme.colorScheme.primary),
                    const SizedBox(width: 10),
                    const Text('Mailbox', style: TextStyle(fontSize: 13)),
                    const Spacer(),
                    if (social.unreadMailboxCount > 0)
                      Container(
                        margin: const EdgeInsets.only(right: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.error,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${social.unreadMailboxCount}',
                          style: const TextStyle(
                            fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                      ),
                    Icon(Icons.chevron_right, size: 18, color: Colors.grey.shade500),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _signOut,
              icon: const Icon(Icons.logout, size: 18),
              label: const Text('Sign out'),
              style: OutlinedButton.styleFrom(foregroundColor: theme.colorScheme.error),
            ),
          ),
        ],
      ),
    );
  }
}

/// One short, self-contained info row — used instead of a long divider +
/// label + value stacked vertically, to keep the screen compact.
class _CompactAccountRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  /// Small grey hint shown under the value, e.g. to reassure the user
  /// that this particular piece of data (their own email) stays
  /// private and is never shown to other travellers (Phase 4).
  final String? trailingNote;

  const _CompactAccountRow({
    required this.icon,
    required this.label,
    required this.value,
    this.trailingNote,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 10),
          Text(label, style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
          const Spacer(),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  value,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                ),
                if (trailingNote != null)
                  Text(
                    trailingNote!,
                    style: TextStyle(fontSize: 10.5, color: Colors.grey.shade500),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
