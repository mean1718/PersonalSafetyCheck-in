import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../widgets/app_bottom_nav.dart';
import '../models/contact.dart';
import '../services/app_session.dart';
import '../services/trusted_contact_service.dart';
import '../services/notification_service.dart';
import 'add_contact_screen.dart';
import 'alert_detail_screen.dart';
import 'incoming_trust_request_card.dart';
import 'live_location_map_screen.dart';

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
  List<Map<String, dynamic>> _incomingRequests = [];
  List<Contact> _confirmedContacts = [];
  List<Map<String, dynamic>> _safetyAlerts = [];
  bool _loadingRequests = true;
  bool _loadingContacts = true;
  String? _requestLoadError;

  List<Contact> get _friends => _confirmedContacts;
  List<Contact> get _requests => AppSession.instance.pendingRequests;

  @override
  void initState() {
    super.initState();
    // A sent request can flip from pending -> friend on its own (the
    // simulated delay in AppSession.sendFriendRequest fires outside any tap
    // on this screen), so this screen needs to listen for that instead of
    // only relying on setState after its own button presses.
    AppSession.instance.addListener(_onSessionChanged);
    _loadIncomingRequests();
    _loadConfirmedContacts();
    _loadSafetyAlerts();
  }

  @override
  void dispose() {
    AppSession.instance.removeListener(_onSessionChanged);
    super.dispose();
  }

  void _onSessionChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadIncomingRequests() async {
    try {
      final requests = await TrustedContactService.receivedTrustRequests();
      if (mounted) {
        setState(() {
          _incomingRequests = requests;
          _requestLoadError = null;
          _loadingRequests = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _requestLoadError = 'Could not load Trust Requests.';
          _loadingRequests = false;
        });
      }
    }
  }

  Contact _contactFromApi(Map<String, dynamic> value) => Contact(
        id: value['_id']?.toString() ?? '',
        fullName: value['name']?.toString() ?? 'SafetyU user',
        phone: value['phone']?.toString() ?? '',
        email: value['email']?.toString() ?? '',
        relationship: value['relationship']?.toString() ?? 'Trusted Contact',
        isMainContact: value['priority'] == 'primary',
        isAvailable: value['availability'] != 'unavailable',
        status: ContactStatus.friend,
        tierAssigned: true,
      );

  Future<void> _loadConfirmedContacts() async {
    try {
      final contacts = await TrustedContactService.fetchAll();
      if (mounted)
        setState(() {
          _confirmedContacts = contacts.map(_contactFromApi).toList();
          _loadingContacts = false;
        });
    } catch (_) {
      if (mounted) setState(() => _loadingContacts = false);
    }
  }

  Future<void> _loadSafetyAlerts() async {
    try {
      final alerts = await NotificationService.activeSafetyAlerts();
      if (mounted) setState(() => _safetyAlerts = alerts);
    } catch (error) {
      debugPrint('Safety alert load skipped: $error');
    }
  }

  Future<void> _respondToSafetyAlert(
      Map<String, dynamic> alert, String responseStatus) async {
    final notificationId = alert['notificationId']?.toString();
    if (notificationId == null) return;
    try {
      await NotificationService.respondToSafetyAlert(
          notificationId, responseStatus);
      await _loadSafetyAlerts();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Safety alert response sent.')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Unable to send the safety alert response.')),
        );
      }
    }
  }

  Future<void> _respondToRequest(String id, bool accept) async {
    try {
      await TrustedContactService.respondToTrustRequest(id, accept: accept);
      await _loadIncomingRequests();
      if (accept) await _loadConfirmedContacts();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(accept
                ? 'Trust request accepted.'
                : 'Trust request rejected.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not update the Trust request.')),
      );
    }
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
      try {
        await TrustedContactService.sendTrustRequest(
          phone: result.phone,
          relationship: result.relationship,
        );
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not send the Trust request.')),
          );
        }
        return;
      }
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

  void _openLiveLocation(Contact contact) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LiveLocationMapScreen(focusContactId: contact.id),
      ),
    );
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
    final isEmpty = friends.isEmpty &&
        requests.isEmpty &&
        !_loadingRequests &&
        !_loadingContacts &&
        _incomingRequests.isEmpty &&
        _safetyAlerts.isEmpty;

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
                          if (_safetyAlerts.isNotEmpty) ...[
                            Text('Safety Alerts',
                                style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.textPrimary)),
                            const SizedBox(height: 10),
                            ..._safetyAlerts.map((alert) => Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: _SafetyAlertCard(
                                    alert: alert,
                                    onCanHelp: () => _respondToSafetyAlert(
                                        alert, 'can_help'),
                                    onCannotHelp: () => _respondToSafetyAlert(
                                        alert, 'cannot_help'),
                                  ),
                                )),
                          ],
                          if (_loadingRequests || _loadingContacts)
                            const Padding(
                              padding: EdgeInsets.all(20),
                              child: Center(child: CircularProgressIndicator()),
                            )
                          else if (_requestLoadError != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: TextButton(
                                onPressed: _loadIncomingRequests,
                                child: Text('Retry loading Trust Requests',
                                    style: TextStyle(color: AppColors.danger)),
                              ),
                            )
                          else ...[
                            Text('Trust Requests',
                                style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.textPrimary)),
                            const SizedBox(height: 10),
                            if (_incomingRequests.isEmpty)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 14),
                                child: Text('No pending Trust Requests',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: AppColors.textSecondary)),
                              )
                            else
                              ..._incomingRequests.map((request) => Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: IncomingTrustRequestCard(
                                      request: request,
                                      onConfirm: () => _respondToRequest(
                                          request['_id'].toString(), true),
                                      onReject: () => _respondToRequest(
                                          request['_id'].toString(), false),
                                    ),
                                  )),
                          ],
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
                                    onLocate: () => _openLiveLocation(c),
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
          : FloatingActionButton(
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

class _SafetyAlertCard extends StatelessWidget {
  final Map<String, dynamic> alert;
  final VoidCallback onCanHelp;
  final VoidCallback onCannotHelp;

  const _SafetyAlertCard({
    required this.alert,
    required this.onCanHelp,
    required this.onCannotHelp,
  });

  String _notifiedTime() {
    final at = DateTime.tryParse(alert['notifiedAt']?.toString() ?? '');
    if (at == null) return 'Just now';
    final difference = DateTime.now().difference(at.toLocal());
    if (difference.inMinutes < 1) return 'Just now';
    if (difference.inHours < 1) return '${difference.inMinutes}m ago';
    if (difference.inDays < 1) return '${difference.inHours}h ago';
    return '${difference.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    final ownerName = alert['ownerName']?.toString() ?? 'A trusted contact';
    final status = alert['responseStatus']?.toString() ?? 'pending';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.dangerLight,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.35)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.warning_amber_rounded, color: AppColors.danger),
          const SizedBox(width: 8),
          Text('Safety Alert',
              style: TextStyle(
                  fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
        ]),
        const SizedBox(height: 8),
        Text('$ownerName may need your help.',
            style: TextStyle(color: AppColors.textPrimary)),
        const SizedBox(height: 3),
        Text('Started ${_notifiedTime()}',
            style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary)),
        if ((alert['message']?.toString() ?? '').isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(alert['message'].toString(),
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        ],
        const SizedBox(height: 12),
        if (status == 'pending')
          Row(children: [
            Expanded(
                child: OutlinedButton(
                    onPressed: onCannotHelp,
                    child: const Text("I Can't Help"))),
            const SizedBox(width: 10),
            Expanded(
                child: ElevatedButton(
                    onPressed: onCanHelp, child: const Text('I Can Help'))),
          ])
        else
          Text(
            status == 'can_help'
                ? 'You responded: I Can Help'
                : "You responded: I Can't Help",
            style: TextStyle(
                fontWeight: FontWeight.w700, color: AppColors.textSecondary),
          ),
      ]),
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
  final VoidCallback onLocate;

  const _FriendCard({
    required this.contact,
    required this.onUnfriend,
    required this.onOpenChat,
    required this.onOpenRespond,
    required this.onEdit,
    required this.onLocate,
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
              const SizedBox(width: 8),
              GestureDetector(
                onTap: onLocate,
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: const BoxDecoration(
                    color: Color(0xFFF5F7FA),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.location_on_outlined,
                      size: 16, color: AppColors.navy),
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
