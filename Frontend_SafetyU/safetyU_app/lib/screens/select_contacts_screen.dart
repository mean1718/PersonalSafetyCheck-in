import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/contact.dart';
import '../services/app_session.dart';
import '../services/trusted_contact_service.dart';
import '../services/check_in_service.dart';
import '../widgets/paywall_dialogs.dart';
import 'add_contact_screen.dart';

/// Lets the person pick which of their confirmed friends should be
/// notified for a specific safety session, split into Main and Other
/// tiers. The tier itself is also set here — each tile has a Main/Other
/// toggle — since Add Contact no longer asks for it. You cannot get
/// through this screen with zero people selected — if there isn't a
/// single confirmed friend yet, session_setup_screen routes to the
/// Friends screen before ever opening this one, and the Confirm button
/// here stays disabled until at least one is selected.
class SelectContactsScreen extends StatefulWidget {
  const SelectContactsScreen({super.key});

  @override
  State<SelectContactsScreen> createState() => _SelectContactsScreenState();
}

class _SelectContactsScreenState extends State<SelectContactsScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  late Set<String> _selectedIds;

  @override
  void initState() {
    super.initState();
    _selectedIds = <String>{};
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final preselected = ModalRoute.of(context)?.settings.arguments;
      if (preselected is List<String>) {
        setState(() => _selectedIds.addAll(preselected));
      }
      // No longer defaults to every confirmed friend — silently
      // pre-selecting people meant every friend got a real "you were
      // notified" alert the moment this screen was even opened, with
      // nothing tapped. Notifying someone should always be a deliberate
      // choice; the Confirm button below already stays disabled until at
      // least one person is actually picked.
    });
    _searchController.addListener(() {
      setState(() => _query = _searchController.text.trim().toLowerCase());
    });
    // A friend added from this screen's empty state can flip from pending
    // to confirmed on its own (AppSession.sendFriendRequest simulates the
    // other person accepting after a delay) — listen so the list and the
    // "add a friend" empty state update the moment that happens, without
    // needing another tap.
    AppSession.instance.addListener(_onSessionChanged);
    _loadConfirmedTrustContacts();
  }

  Future<void> _loadConfirmedTrustContacts() async {
    try {
      final contacts = await CheckInService.trustedContacts();
      for (final contact in contacts) {
        final userId = contact['userId']?.toString();
        if (userId == null || userId.isEmpty) continue;
        AppSession.instance.upsertContact(Contact(
          id: userId,
          fullName: contact['name']?.toString() ?? 'SafetyU user',
          phone: contact['phone']?.toString() ?? '',
          email: contact['email']?.toString() ?? '',
          relationship: 'Trusted Contact',
          status: ContactStatus.friend,
          tierAssigned: false,
        ));
      }
      if (mounted) setState(() {});
    } catch (error) {
      debugPrint('Could not load confirmed trust contacts: $error');
    }
  }

  void _onSessionChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    AppSession.instance.removeListener(_onSessionChanged);
    _searchController.dispose();
    super.dispose();
  }

  // Contacts that have never been explicitly tagged Main or Other sit in
  // their own group above both sections. Tagging one moves it out of here
  // and into the matching section below, for the rest of this list.
  List<Contact> get _unassignedFriends =>
      AppSession.instance.friends.where((c) => !c.tierAssigned).toList();
  List<Contact> get _mainFriends => AppSession.instance.friends
      .where((c) => c.tierAssigned && c.isMainContact)
      .toList();
  List<Contact> get _otherFriends => AppSession.instance.friends
      .where((c) => c.tierAssigned && !c.isMainContact)
      .toList();

  List<Contact> _filtered(List<Contact> list) {
    if (_query.isEmpty) return list;
    return list
        .where((c) =>
            c.fullName.toLowerCase().contains(_query) ||
            c.relationship.toLowerCase().contains(_query))
        .toList();
  }

  int get _selectedMainCount =>
      _mainFriends.where((c) => _selectedIds.contains(c.id)).length;
  int get _selectedOtherCount =>
      _otherFriends.where((c) => _selectedIds.contains(c.id)).length;

  bool get _hasUnassignedSelectedContacts => AppSession.instance.friends.any(
        (c) => _selectedIds.contains(c.id) && !c.tierAssigned,
      );

  bool get _overMainLimit =>
      _selectedMainCount > AppSession.instance.maxMainContacts;
  bool get _overOtherLimit =>
      _selectedOtherCount > AppSession.instance.maxOtherContacts;

  /// Tags a contact as Main or Other, or — if it's already tagged that way
  /// — untags it and sends it back to Unassigned. This is a change to the
  /// contact's saved profile (not just this session), so it persists the
  /// next time this screen — or anywhere else Main/Other is used — is
  /// opened. Tapping the *other* chip (the one not currently active) just
  /// switches which of the two tiers it's in, same as before.
  void _setTier(Contact contact, bool isMain) {
    if (contact.tierAssigned && contact.isMainContact == isMain) {
      // Tapping the already-active chip again clears the tag.
      AppSession.instance.upsertContact(contact.copyWith(tierAssigned: false));
      return;
    }
    AppSession.instance.upsertContact(
        contact.copyWith(isMainContact: isMain, tierAssigned: true));

    // Best-effort mirror to the backend — see TrustedContactService for
    // why only Main/Other (not every contact) is synced. Never blocks or
    // errors onto this screen if the backend is offline.
    TrustedContactService.upsertPriorityContact(
      priority: isMain ? 'primary' : 'secondary',
      name: contact.fullName,
      phone: contact.phone,
      email: contact.email,
      relationship: contact.relationship,
      isAvailable: contact.isAvailable,
    ).catchError((e) => debugPrint('Trusted contact sync skipped: $e'));
  }

  Future<void> _addFriend() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const AddContactScreen()),
    );
    if (result is Contact) {
      AppSession.instance.sendFriendRequest(result);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  'Request sent to ${result.fullName} — waiting for them to accept.')),
        );
      }
    }
  }

  Future<void> _onConfirm() async {
    // Belt-and-suspenders: the button itself is disabled at 0 selected,
    // but never allow a pop with nobody chosen even if this gets called
    // some other way.
    if (_selectedIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Select at least one friend to notify before confirming.')),
      );
      return;
    }
    if (_hasUnassignedSelectedContacts) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please assign every selected contact as Main or Other before confirming.',
          ),
        ),
      );
      return;
    }

    if (!_overMainLimit && !_overOtherLimit) {
      final selected = AppSession.instance.friends
          .where((c) => _selectedIds.contains(c.id))
          .toList();
      Navigator.pop(context, selected);
      return;
    }

    final choice = await showLimitReachedDialog(
      context,
      selectedMain: _selectedMainCount,
      selectedOther: _selectedOtherCount,
    );

    if (!mounted) return;

    if (choice == 'pro') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text("You're on Pro now — unlimited contacts.")),
      );

      final selected = AppSession.instance.friends
          .where((c) => _selectedIds.contains(c.id))
          .toList();
      Navigator.pop(context, selected);
      return;
    }

    if (choice == 'pay') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Extra contact added.'),
        ),
      );

      final selected = AppSession.instance.friends
          .where((c) => _selectedIds.contains(c.id))
          .toList();
      Navigator.pop(context, selected);
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasFriends = AppSession.instance.friends.isNotEmpty;
    final main = _filtered(_mainFriends);
    final other = _filtered(_otherFriends);
    final isPro = AppSession.instance.isPro;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
        title: const Text('Notify Contacts',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (hasFriends)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search contacts',
                    prefixIcon: Icon(Icons.search,
                        size: 20, color: AppColors.textMuted),
                  ),
                ),
              ),
            Expanded(
              child: !hasFriends
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.person_add_alt_1,
                                size: 40, color: AppColors.textMuted),
                            const SizedBox(height: 10),
                            Text(
                              'You need at least one confirmed friend to start a safety session.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13),
                            ),
                            const SizedBox(height: 14),
                            ElevatedButton.icon(
                              onPressed: _addFriend,
                              icon: const Icon(Icons.add, size: 18),
                              label: const Text('Add a Friend'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.navy,
                                minimumSize: const Size(0, 46),
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 20),
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      children: [
                        if (_filtered(_unassignedFriends).isNotEmpty) ...[
                          Text(
                            'UNASSIGNED — TAG AS MAIN OR OTHER',
                            style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textSecondary,
                                letterSpacing: 0.4),
                          ),
                          const SizedBox(height: 10),
                          ..._filtered(_unassignedFriends).map((c) => Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: _ContactTile(
                                  contact: c,
                                  selected: _selectedIds.contains(c.id),
                                  onTap: () => setState(() {
                                    if (_selectedIds.contains(c.id)) {
                                      _selectedIds.remove(c.id);
                                    } else {
                                      _selectedIds.add(c.id);
                                    }
                                  }),
                                  onSetTier: (isMain) => _setTier(c, isMain),
                                ),
                              )),
                          const SizedBox(height: 20),
                        ],
                        _sectionHeader('Main Contacts', _selectedMainCount,
                            AppSession.instance.maxMainContacts, isPro,
                            over: _overMainLimit),
                        const SizedBox(height: 10),
                        if (main.isEmpty)
                          _emptyTierNote('No main contacts yet.')
                        else
                          ...main.map((c) => Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: _ContactTile(
                                  contact: c,
                                  selected: _selectedIds.contains(c.id),
                                  onTap: () => setState(() {
                                    if (_selectedIds.contains(c.id)) {
                                      _selectedIds.remove(c.id);
                                    } else {
                                      _selectedIds.add(c.id);
                                    }
                                  }),
                                  onSetTier: (isMain) => _setTier(c, isMain),
                                ),
                              )),
                        const SizedBox(height: 18),
                        _sectionHeader('Other Contacts', _selectedOtherCount,
                            AppSession.instance.maxOtherContacts, isPro,
                            over: _overOtherLimit),
                        const SizedBox(height: 10),
                        if (other.isEmpty)
                          _emptyTierNote('No other contacts yet.')
                        else
                          ...other.map((c) => Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: _ContactTile(
                                  contact: c,
                                  selected: _selectedIds.contains(c.id),
                                  onTap: () => setState(() {
                                    if (_selectedIds.contains(c.id)) {
                                      _selectedIds.remove(c.id);
                                    } else {
                                      _selectedIds.add(c.id);
                                    }
                                  }),
                                  onSetTier: (isMain) => _setTier(c, isMain),
                                ),
                              )),
                        const SizedBox(height: 12),
                      ],
                    ),
            ),
            if (hasFriends && (_overMainLimit || _overOtherLimit))
              Container(
                margin: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.dangerLight,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.danger),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        color: AppColors.danger, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'You can only notify up to ${AppSession.instance.maxMainContacts} main and ${AppSession.instance.maxOtherContacts} other contacts on the free plan.',
                        style: TextStyle(
                            fontSize: 11.5,
                            color: AppColors.danger,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            if (hasFriends && _selectedIds.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                child: Text(
                  'Select at least one friend to notify.',
                  style: TextStyle(fontSize: 11.5, color: AppColors.danger),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(
                children: [
                  if (_selectedIds.isNotEmpty &&
                      _hasUnassignedSelectedContacts) ...[
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.info_outline,
                          size: 16,
                          color: AppColors.danger,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Please assign every selected contact as Main or Other before confirming.',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.danger,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (hasFriends)
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _selectedIds.isNotEmpty &&
                                !_hasUnassignedSelectedContacts
                            ? _onConfirm
                            : null,
                        style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.navy,
                            disabledBackgroundColor:
                                AppColors.navy.withValues(alpha: 0.35),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(25))),
                        child: Text('Confirm (${_selectedIds.length})',
                            style: const TextStyle(
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

  Widget _sectionHeader(String label, int selected, int max, bool isPro,
      {required bool over}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isPro ? '$label ($selected)' : '$label ($selected/$max)',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary),
              ),
              if (over)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text('Free plan allows up to $max friends',
                      style: TextStyle(
                          fontSize: 11,
                          color: AppColors.danger,
                          fontWeight: FontWeight.w600)),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _emptyTierNote(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text,
          style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
    );
  }
}

class _ContactTile extends StatelessWidget {
  final Contact contact;
  final bool selected;
  final VoidCallback onTap;
  final ValueChanged<bool> onSetTier;

  const _ContactTile({
    required this.contact,
    required this.selected,
    required this.onTap,
    required this.onSetTier,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: selected ? AppColors.navy : AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top row: select-for-this-session (tap anywhere here to toggle).
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: onTap,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: AppColors.navy.withValues(alpha: 0.1),
                  child: Text(contact.initials,
                      style: TextStyle(
                          color: AppColors.navy,
                          fontWeight: FontWeight.w700,
                          fontSize: 12.5)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(contact.fullName,
                          style: const TextStyle(
                              fontSize: 13.5, fontWeight: FontWeight.w700)),
                      Text(
                        contact.relationship.isEmpty
                            ? ' '
                            : contact.relationship,
                        style: TextStyle(
                            fontSize: 11.5, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  selected ? Icons.check_circle : Icons.radio_button_unchecked,
                  color: selected ? AppColors.navy : AppColors.textMuted,
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          // Tier toggle sits right under the select row — tapping a chip
          // reassigns the contact's saved tier and moves the tile into the
          // matching section immediately. This is its own gesture area, so
          // it doesn't also toggle the session-selection above.
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _TierChip(
                label: 'Main',
                // Neither chip shows as selected until the contact has
                // actually been tagged, so an unassigned tile doesn't
                // look like it's already "Other" by default.
                selected: contact.tierAssigned && contact.isMainContact,
                onTap: () => onSetTier(true),
              ),
              const SizedBox(width: 6),
              _TierChip(
                label: 'Other',
                selected: contact.tierAssigned && !contact.isMainContact,
                onTap: () => onSetTier(false),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TierChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _TierChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? AppColors.navy : AppColors.background,
          borderRadius: BorderRadius.circular(20),
          border:
              Border.all(color: selected ? AppColors.navy : AppColors.border),
        ),
        child: Text(
          label,
          style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: selected ? Colors.white : AppColors.textSecondary),
        ),
      ),
    );
  }
}
