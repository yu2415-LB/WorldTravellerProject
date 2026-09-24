import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:world_traveller_project/main.dart';
import 'package:world_traveller_project/providers/social_controller.dart';
import 'package:world_traveller_project/services/profile_service.dart';
import 'package:world_traveller_project/services/supabase_storage_service.dart';
import 'package:world_traveller_project/views/mailbox_view.dart';

/// "My Account": a gradient hero header (avatar, name, ID, role badge)
/// over a couple of short, rounded cards — instead of the flat grey rows
/// on a bare background this screen used to be. Still compact: no long
/// full-width dividers, no wasted vertical space.
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
    final scheme = theme.colorScheme;
    final social = context.watch<SocialController>();
    final me = social.myProfile;

    return Scaffold(
      appBar: AppBar(title: const Text('My Account')),
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          // --- Hero header: a coloured gradient behind the avatar, instead
          // of a plain grey "?" circle sitting on the bare background.
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 28, 20, 28),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [scheme.primary, scheme.primaryContainer],
              ),
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(28),
                bottomRight: Radius.circular(28),
              ),
            ),
            child: Column(
              children: [
                Stack(
                  alignment: Alignment.bottomRight,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: CircleAvatar(
                        radius: 40,
                        backgroundColor: scheme.secondaryContainer,
                        backgroundImage: (me?.avatarUrl != null && me!.avatarUrl!.isNotEmpty)
                            ? NetworkImage(me.avatarUrl!)
                            : null,
                        child: _uploadingAvatar
                            ? SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.6,
                                  value: _avatarProgress,
                                  color: scheme.onSecondaryContainer,
                                ),
                              )
                            : (me?.avatarUrl == null || me!.avatarUrl!.isEmpty)
                                ? Text(
                                    me?.initial ?? '?',
                                    style: TextStyle(
                                      fontSize: 26,
                                      fontWeight: FontWeight.bold,
                                      color: scheme.onSecondaryContainer,
                                    ),
                                  )
                                : null,
                      ),
                    ),
                    Material(
                      color: scheme.secondary,
                      shape: const CircleBorder(),
                      elevation: 2,
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: _uploadingAvatar ? null : _changeAvatar,
                        child: const Padding(
                          padding: EdgeInsets.all(7),
                          child: Icon(Icons.edit, size: 16, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  me?.fullName ?? 'Traveller',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: scheme.onPrimary,
                  ),
                ),
                if (me != null) ...[
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: scheme.onPrimary.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              me.publicId,
                              style: TextStyle(
                                fontSize: 12,
                                color: scheme.onPrimary.withValues(alpha: 0.9),
                                fontFeatures: const [FontFeature.tabularFigures()],
                              ),
                            ),
                            const SizedBox(width: 4),
                            InkWell(
                              borderRadius: BorderRadius.circular(20),
                              onTap: () async {
                                await Clipboard.setData(ClipboardData(text: me.publicId));
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('ID copied.')),
                                );
                              },
                              child: Icon(Icons.copy,
                                  size: 13, color: scheme.onPrimary.withValues(alpha: 0.9)),
                            ),
                          ],
                        ),
                      ),
                      if (me.isAdmin) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: scheme.tertiary,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            'Admin',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: scheme.onTertiary,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SectionLabel('Your name', color: scheme.primary),
                const SizedBox(height: 10),
                _Card(
                  child: Column(
                    children: [
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
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton.icon(
                          onPressed: _savingName ? null : _saveName,
                          icon: _savingName
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.check, size: 18),
                          label: const Text('Save'),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),
                _SectionLabel('Account', color: scheme.secondary),
                const SizedBox(height: 10),
                _Card(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      _AccountRow(
                        icon: Icons.mail_outline,
                        iconColor: scheme.secondary,
                        label: 'Email',
                        value: supabase.auth.currentUser?.email ?? '—',
                        trailingNote: 'Only visible to you',
                      ),
                      Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.5)),
                      _AccountRow(
                        icon: Icons.verified_user_outlined,
                        iconColor: scheme.tertiary,
                        label: 'Role',
                        value: me?.isAdmin == true ? 'Administrator' : 'Standard traveller',
                      ),
                      Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.5)),
                      _AccountRow(
                        icon: Icons.markunread_mailbox_outlined,
                        iconColor: scheme.primary,
                        label: 'Mailbox',
                        value: social.unreadMailboxCount > 0
                            ? '${social.unreadMailboxCount} new'
                            : 'No new messages',
                        onTap: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const MailboxView()),
                          );
                          if (mounted) setState(() {});
                        },
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _signOut,
                    icon: const Icon(Icons.logout, size: 18),
                    label: const Text('Sign out'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: scheme.error,
                      side: BorderSide(color: scheme.error.withValues(alpha: 0.4)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A short, coloured section heading — a splash of the app's own accent
/// colours instead of the same flat grey label repeated everywhere.
class _SectionLabel extends StatelessWidget {
  final String text;
  final Color color;
  const _SectionLabel(this.text, {required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 16,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(width: 8),
        Text(
          text,
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color, letterSpacing: 0.2),
        ),
      ],
    );
  }
}

/// A softly elevated, rounded card — replaces the flat, barely-visible
/// grey boxes the screen used before.
class _Card extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  const _Card({required this.child, this.padding = const EdgeInsets.all(14)});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: child,
    );
  }
}

/// One row inside the "Account" card — a coloured icon badge instead of a
/// plain grey glyph, and tappable when [onTap] is given (the mailbox row).
class _AccountRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  final String? trailingNote;
  final VoidCallback? onTap;

  const _AccountRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    this.trailingNote,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(color: iconColor.withValues(alpha: 0.14), shape: BoxShape.circle),
            child: Icon(icon, size: 16, color: iconColor),
          ),
          const SizedBox(width: 12),
          Text(label, style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
          const Spacer(),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  value,
                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                ),
                if (trailingNote != null)
                  Text(trailingNote!, style: TextStyle(fontSize: 10.5, color: Colors.grey.shade500)),
              ],
            ),
          ),
          if (onTap != null) ...[
            const SizedBox(width: 6),
            Icon(Icons.chevron_right, size: 18, color: Colors.grey.shade500),
          ],
        ],
      ),
    );

    if (onTap == null) return content;
    return InkWell(borderRadius: BorderRadius.circular(16), onTap: onTap, child: content);
  }
}
