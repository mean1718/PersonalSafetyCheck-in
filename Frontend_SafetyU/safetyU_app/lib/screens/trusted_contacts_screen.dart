import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../widgets/app_bottom_nav.dart';
import '../models/contact.dart';
import '../services/app_session.dart';
import '../services/trusted_contact_service.dart';
import 'add_contact_screen.dart';
import 'alert_detail_screen.dart';

/// "Friends" tab — the people who'll actually be notified in an emergency.
/// A sent request sits under Requests as [ContactStatus.pending] until the
/// other person confirms; only then do they move to Your Friends and
/// become eligible to be notified, chatted with, or escalated to.
class TrustedContactsScreen extends StatefulWidget {
  const TrustedContactsScreen({super.key});

  @override
  State<TrustedContactsScreen> createState() => _TrustedContactsScreenState();
}

class _TrustedContactsScreenState extends State<TrustedContactsScreen> {
  final int _navIndex = 1;

  List<Contact> get _friends => AppSession.instance.friends;
  List<Contact> get _requests => AppSession.instance.pendingRequests;

  @override
  void initState() {
    super.initState();
    // A sent request can flip from pending -> friend on its own (the
    // simulated delay in AppSession.sendFriendRequest fires outside any tap
    // on this screen), so this screen needs to listen for that instead of
    // only relying on setState after its own button presses.
    AppSession.instance.addListener(_onSessionChanged);
  }

  @override
  void dispose() {
    AppSession.instance.removeListener(_onSessionChanged);
    super.dispose();
  }

  void _onSessionChanged() {
    if (mounted) setState(() {});
  }

  void _onNavTap(int index) {
    if (index == _navIndex) return;
    switch (index) {
      case 0:
        Navigator.pushReplacementNamed(context, '/home');
        break;
      case 2:
        Navigator.pushReplacementNamed(context, '/history');
        break;
      case 3:
        Navigator.pushReplacementNamed(context, '/profile');
        break;
    }
  }

  Future<void> _addContact() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const AddContactScreen()),
    );
    if (result is Contact) {
      setState(() => AppSession.instance.sendFriendRequest(result));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  'Request sent to ${result.fullName} — waiting for them to accept.')),
        );
      }
    }
  }

  Future<void> _openEditScreen(Contact contact) async {
    final result = await Navigator.pushNamed(
      context,
      '/edit-contact',
      arguments: contact,
    );
    if (result is Contact) {
      setState(() => AppSession.instance.upsertContact(result));
    }
  }

  void _delete(Contact contact) {
    setState(() => AppSession.instance.removeContact(contact.id));
    if (contact.tierAssigned) {
      // Only Main/Other contacts are ever mirrored to the backend — see
      // TrustedContactService — so only try to remove those there.
      TrustedContactService.removeByPhone(contact.phone)
          .catchError((e) => debugPrint('Trusted contact sync skipped: $e'));
    }
  }

  void _openChat(Contact contact) {
    Navigator.pushNamed(context, '/chat', arguments: contact);
  }

  void _openRespondFlow(Contact contact) {
    final request = AppSession.instance.buildHelpRequestFor(contact);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AlertDetailScreen(contact: contact, request: request),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final friends = _friends;
    final requests = _requests;
    final isEmpty = friends.isEmpty && requests.isEmpty;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Friends',
                style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary),
              ),
              const SizedBox(height: 6),
              Text(
                'People you trust and can notify in an emergency.',
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 18),
              Expanded(
                child: isEmpty
                    ? _EmptyFriendsState(onAdd: _addContact)
                    : ListView(
                        padding: const EdgeInsets.only(bottom: 20),
                        children: [
                          if (requests.isNotEmpty) ...[
                            Text(
                              'Requests',
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.textPrimary),
                            ),
                            const SizedBox(height: 10),
                            ...requests.map((c) => Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: _RequestCard(
                                    contact: c,
                                    onDelete: () => _delete(c),
                                    onEdit: () => _openEditScreen(c),
                                  ),
                                )),
                            const SizedBox(height: 8),
                          ],
                          if (friends.isNotEmpty) ...[
                            Text(
                              'Your Friends',
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.textPrimary),
                            ),
                            const SizedBox(height: 10),
                            ...friends.map((c) => Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: _FriendCard(
                                    contact: c,
                                    onUnfriend: () => _delete(c),
                                    onOpenChat: () => _openChat(c),
                                    onOpenRespond: () => _openRespondFlow(c),
                                    onEdit: () => _openEditScreen(c),
                                  ),
                                )),
                          ],
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: isEmpty
          ? null
          :FloatingActionButton(
            onPressed: _addContact,
            backgroundColor: AppColors.navy,
            shape: const CircleBorder(),
            child: const Icon(Icons.add, color: Colors.white, size: 28),
      ),
      bottomNavigationBar:
          AppBottomNav(currentIndex: _navIndex, onTap: _onNavTap),
    );
  }
}

class _EmptyFriendsState extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyFriendsState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.navy.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child:
                  Icon(Icons.person_add_alt_1, color: AppColors.navy, size: 32),
            ),
            const SizedBox(height: 16),
            Text(
              'No friends yet',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary),
            ),
            const SizedBox(height: 6),
            Text(
              'Add the real people who should be alerted — family, roommates, or a close friend — so a safety session actually has someone to notify.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 12.5, color: AppColors.textSecondary, height: 1.4),
            ),
            const SizedBox(height: 18),
            ElevatedButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add Contact'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.navy,
                minimumSize: const Size(0, 46),
                padding: const EdgeInsets.symmetric(horizontal: 20),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FriendCard extends StatelessWidget {
  final Contact contact;
  final VoidCallback onUnfriend;
  final VoidCallback onOpenChat;
  final VoidCallback onOpenRespond;
  final VoidCallback onEdit;

  const _FriendCard({
    required this.contact,
    required this.onUnfriend,
    required this.onOpenChat,
    required this.onOpenRespond,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: AppColors.navy.withValues(alpha: 0.1),
                child: Text(
                  contact.initials,
                  style: TextStyle(
                      color: AppColors.navy,
                      fontWeight: FontWeight.w700,
                      fontSize: 16),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            contact.fullName,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary),
                          ),
                        ),
                        if (contact.relationship.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.navy.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              contact.isMainContact
                                  ? 'Main'
                                  : contact.relationship,
                              style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.navy),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      contact.email.isNotEmpty ? contact.email : contact.phone,
                      style: TextStyle(
                          fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              GestureDetector(
                onTap: onOpenChat,
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: const BoxDecoration(
                    color: Color(0xFFF5F7FA),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.chat_bubble_outline,
                      size: 16, color: AppColors.navy),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: onOpenRespond,
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: const BoxDecoration(
                    color: Color(0xFFF5F7FA),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.notifications_active_outlined,
                      size: 16, color: AppColors.navy),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: onEdit,
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: const BoxDecoration(
                    color: Color(0xFFF5F7FA),
                    shape: BoxShape.circle,
                  ),
                  child:
                      Icon(Icons.edit_square, size: 16, color: AppColors.navy),
                ),
              ),
              const Spacer(),
              ElevatedButton(
                onPressed: onUnfriend,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.navy,
                  minimumSize: const Size(0, 36),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20)),
                  textStyle: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700),
                ),
                child: const Text('Unfriend'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RequestCard extends StatelessWidget {
  final Contact contact;
  final VoidCallback onDelete;
  final VoidCallback onEdit;

  const _RequestCard({
    required this.contact,
    required this.onDelete,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: AppColors.navy.withValues(alpha: 0.1),
                child: Text(
                  contact.initials,
                  style: TextStyle(
                      color: AppColors.navy,
                      fontWeight: FontWeight.w700,
                      fontSize: 14),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(contact.fullName,
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary)),
                    Text(
                        'Waiting for ${contact.fullName.split(' ').first} to accept',
                        style: TextStyle(
                            fontSize: 11.5, color: AppColors.textSecondary)),
                  ],
                ),
              ),
              GestureDetector(
                onTap: onEdit,
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: const BoxDecoration(
                    color: Color(0xFFF5F7FA),
                    shape: BoxShape.circle,
                  ),
                  child:
                      Icon(Icons.edit_square, size: 16, color: AppColors.navy),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: onDelete,
              style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 38),
                  foregroundColor: AppColors.textSecondary),
              child: const Text('Cancel Request'),
            ),
          ),
        ],
      ),
    );
  }
}
