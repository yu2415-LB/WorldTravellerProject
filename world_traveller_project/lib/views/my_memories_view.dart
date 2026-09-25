import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:world_traveller_project/components/media_results_grid.dart';
import 'package:world_traveller_project/main.dart';
import 'package:world_traveller_project/providers/location_managing_controller.dart';
import 'package:world_traveller_project/providers/social_controller.dart';

/// Every picture the signed in traveller posted themselves.
class MyMemoriesView extends StatefulWidget {
  const MyMemoriesView({super.key});

  @override
  State<MyMemoriesView> createState() => _MyMemoriesViewState();
}

class _MyMemoriesViewState extends State<MyMemoriesView> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await context.read<SocialController>().refreshForCurrentUser();
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<LocationManagingController>();
    final social = context.watch<SocialController>();
    final currentUser = supabase.auth.currentUser;

    final mine = <LocatedMedia>[];
    if (currentUser != null) {
      for (final location in controller.locations) {
        for (final media in location.mediaSet) {
          if (media.userId == currentUser.id) {
            mine.add(LocatedMedia(media: media, location: location));
          }
        }
      }
    }

    // Newest first: the most recent memory is usually the interesting one.
    mine.sort((a, b) =>
        b.media.lastModification.compareTo(a.media.lastModification));

    final myName = social.myProfile?.fullName;

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.collections_bookmark_outlined),
            SizedBox(width: 8),
            Text('My memories'),
          ],
        ),
      ),
      body: currentUser == null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.lock_outline, size: 72, color: Colors.grey.shade400),
                    const SizedBox(height: 16),
                    Text(
                      'Sign in to see your own memories',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      icon: const Icon(Icons.login),
                      label: const Text('Sign in'),
                      onPressed: () async {
                        // Capture the controller BEFORE awaiting anything,
                        // so `context` is never used across an async gap.
                        final social = context.read<SocialController>();
                        await ensureLoggedIn(context);
                        if (!mounted) return;
                        await social.refreshForCurrentUser();
                        if (mounted) setState(() {});
                      },
                    ),
                  ],
                ),
              ),
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      myName != null && myName.trim().isNotEmpty
                          ? 'Posted as $myName \u00b7 ${mine.length} picture${mine.length == 1 ? '' : 's'}'
                          : '${mine.length} picture${mine.length == 1 ? '' : 's'}',
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                    ),
                  ),
                ),
                Expanded(
                  child: MediaResultsGrid(
                    items: mine,
                    emptyIcon: Icons.add_a_photo_outlined,
                    emptyTitle: 'You have not posted anything yet',
                    emptySubtitle:
                        'Tap a spot on the map to add your first travel memory.',
                    onChanged: () => setState(() {}),
                  ),
                ),
              ],
            ),
    );
  }
}