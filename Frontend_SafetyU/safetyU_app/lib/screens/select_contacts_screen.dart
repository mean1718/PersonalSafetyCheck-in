import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/contact.dart';
import '../services/app_session.dart';

/// Lets the person pick which of their real trusted contacts should be
/// notified for a specific safety session. Returns the selected [Contact]
/// list via Navigator.pop when "Okay" is tapped, or null on Cancel.
class SelectContactsScreen extends StatefulWidget {
  const SelectContactsScreen({super.key});

  @override
  State<SelectContactsScreen> createState() => _SelectContactsScreenState();
}

class _SelectContactsScreenState extends State<SelectContactsScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  late final Set<String> _selectedIds;

  @override
  void initState() {
    super.initState();
    _selectedIds = <String>{};
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final preselected = ModalRoute.of(context)?.settings.arguments;
      if (preselected is List<String>) {
        setState(() => _selectedIds.addAll(preselected));
      } else {
        // Default to notifying everyone already saved, so the session
        // always starts with someone covered.
        setState(() =>
            _selectedIds.addAll(AppSession.instance.contacts.map((c) => c.id)));
      }
    });
    _searchController.addListener(() {
      setState(() => _query = _searchController.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Contact> get _filteredContacts {
    final all = AppSession.instance.contacts;
    if (_query.isEmpty) return all;
    return all
        .where((c) =>
            c.fullName.toLowerCase().contains(_query) ||
            c.relationship.toLowerCase().contains(_query))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final contacts = _filteredContacts;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
        title: const Text('Search Contacts',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search your trusted contacts',
                  prefixIcon:
                      Icon(Icons.search, size: 20, color: AppColors.textMuted),
                ),
              ),
            ),
            Expanded(
              child: contacts.isEmpty
                  ? Center(
                      child: Text(
                        AppSession.instance.contacts.isEmpty
                            ? 'You have no trusted contacts to select yet.'
                            : 'No contacts match your search.',
                        style: TextStyle(
                            color: AppColors.textSecondary, fontSize: 13),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      itemCount: contacts.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final c = contacts[index];
                        final selected = _selectedIds.contains(c.id);
                        return InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () {
                            setState(() {
                              if (selected) {
                                _selectedIds.remove(c.id);
                              } else {
                                _selectedIds.add(c.id);
                              }
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppColors.card,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                  color: selected
                                      ? AppColors.navy
                                      : AppColors.border),
                            ),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 18,
                                  backgroundColor:
                                      AppColors.navy.withValues(alpha: 0.1),
                                  child: Text(c.initials,
                                      style: TextStyle(
                                          color: AppColors.navy,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 12.5)),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(c.fullName,
                                          style: const TextStyle(
                                              fontSize: 13.5,
                                              fontWeight: FontWeight.w700)),
                                      Text(
                                        c.isMainContact
                                            ? 'Main Contact'
                                            : c.relationship,
                                        style: TextStyle(
                                            fontSize: 11.5,
                                            color: AppColors.textSecondary),
                                      ),
                                    ],
                                  ),
                                ),
                                Icon(
                                  selected
                                      ? Icons.check_circle
                                      : Icons.radio_button_unchecked,
                                  color: selected
                                      ? AppColors.navy
                                      : AppColors.textMuted,
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: () {
                        final selected = AppSession.instance.contacts
                            .where((c) => _selectedIds.contains(c.id))
                            .toList();
                        Navigator.pop(context, selected);
                      },
                      style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.navy,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(25))),
                      child: const Text('Okay',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700)),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context, null),
                    child: Text('Cancel',
                        style: TextStyle(
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
