import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:world_traveller_project/models/user_profile.dart';
import 'package:world_traveller_project/providers/social_controller.dart';
import 'package:world_traveller_project/views/user_profile_view.dart';

/// Search bar that finds other travellers by first/last name.
class UserSearchView extends StatefulWidget {
  const UserSearchView({super.key});

  @override
  State<UserSearchView> createState() => _UserSearchViewState();
}

class _UserSearchViewState extends State<UserSearchView> {
  final TextEditingController _controller = TextEditingController();
  Timer? _debounce;

  List<UserProfile> _results = [];
  bool _searching = false;
  bool _searchedOnce = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onQueryChanged(String query) {
    _debounce?.cancel();

    if (query.trim().isEmpty) {
      setState(() {
        _results = [];
        _searchedOnce = false;
        _searching = false;
      });
      return;
    }

    _debounce = Timer(
      const Duration(milliseconds: 300),
      () => _runSearch(query.trim()),
    );
  }

  Future<void> _runSearch(String query) async {
    setState(() => _searching = true);

    final results = await context.read<SocialController>().searchUsers(query);

    if (!mounted) return;
    setState(() {
      _results = results;
      _searching = false;
      _searchedOnce = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.travel_explore),
            SizedBox(width: 8),
            Text('Find travellers'),
          ],
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _controller,
              autofocus: true,
              onChanged: _onQueryChanged,
              decoration: InputDecoration(
                hintText: 'Search by name...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searching
                    ? const Padding(
                        padding: EdgeInsets.all(14),
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : (_controller.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear),
                            tooltip: 'Clear',
                            onPressed: () {
                              _controller.clear();
                              _onQueryChanged('');
                            },
                          )),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          Expanded(child: _buildResults()),
        ],
      ),
    );
  }

  Widget _buildResults() {
    if (!_searchedOnce && _results.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.group_outlined, size: 72, color: Colors.grey.shade400),
              const SizedBox(height: 16),
              Text(
                'Look for a fellow traveller',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Type a name to see everything they have posted.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
              ),
            ],
          ),
        ),
      );
    }

    if (_results.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.person_off_outlined, size: 72, color: Colors.grey.shade400),
              const SizedBox(height: 16),
              Text(
                'No traveller found',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Check the spelling, or try a shorter search.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
              ),
            ],
          ),
        ),
      );
    }

    // Two travellers with the same name are told apart by their unique
    // ID (brief point 4): whenever a name repeats in this result set, the
    // short ID is appended so the list itself is unambiguous.
    final nameCounts = <String, int>{};
    for (final p in _results) {
      nameCounts[p.fullName] = (nameCounts[p.fullName] ?? 0) + 1;
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: _results.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final profile = _results[index];
        final hasNameClash = (nameCounts[profile.fullName] ?? 0) > 1;
        final title = hasNameClash ? profile.fullNameWithId : profile.fullName;

        return ListTile(
          leading: CircleAvatar(
            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
            backgroundImage: (profile.avatarUrl != null && profile.avatarUrl!.isNotEmpty)
                ? NetworkImage(profile.avatarUrl!)
                : null,
            child: (profile.avatarUrl == null || profile.avatarUrl!.isEmpty)
                ? Text(
                    profile.initial,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  )
                : null,
          ),
          title: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: profile.bio != null && profile.bio!.isNotEmpty
              ? Text(profile.bio!, maxLines: 1, overflow: TextOverflow.ellipsis)
              : const Text('Tap to see their memories'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => UserProfileView(
                  userId: profile.id,
                  preloadedProfile: profile,
                ),
              ),
            );
          },
        );
      },
    );
  }
}
