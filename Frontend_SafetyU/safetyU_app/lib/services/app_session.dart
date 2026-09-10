import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import '../models/contact.dart';
import '../models/user_role.dart';
import '../models/session_record.dart';
import '../models/app_notification.dart';
import '../models/incident.dart';
import '../models/verification_status.dart';
import '../models/chat_message.dart';
import '../models/help_request.dart';
import '../models/contact_response_state.dart';

/// Holds the currently signed-in person's real details, contacts, session
/// history, notifications, profile preferences, and (for the single-device
/// demo this app runs as) the shared incident feed the Responder Dashboard
/// reads from.
///
/// SafetyU has no backend in this build, so this in-memory singleton is what
/// every screen reads from instead of hardcoded placeholder data — whatever
/// the person types or does in the app is what shows up everywhere else.
class AppSession extends ChangeNotifier {
  AppSession._internal();
  static final AppSession instance = AppSession._internal();

  String fullName = '';
  String email = '';
  String phone = '';
  UserRole role = UserRole.user;

  // ---- Backend auth (see services/auth_service.dart) ----
  // Set once by AuthService.login after a successful /api/users/login
  // call; sent as "Authorization: Bearer <authToken>" on every
  // subsequent request by ApiClient. Null/empty means "not talking to
  // the real backend right now" — every backend-facing service treats
  // that as a signal to fail quietly rather than break the local demo
  // experience.
  String? authToken;
  String? backendUserId;
  // Backend identifier for the session currently being displayed on Home.
  // It lets the owner reload actual notification recipients and responses.
  String? activeCheckInId;

    // Local file path to the picture the person chose from their own camera
  // or gallery. SafetyU has no backend/cloud storage in this build, so
  // this only points at a file already on the device — nothing is
  // uploaded anywhere.
  String? profilePhotoPath;

  void updateProfilePhoto(String? path) {
    profilePhotoPath = path;
    notifyListeners();
  }

  // ---- Emergency Responder identity (see verification_status.dart for
  // an honest note on what this app can and can't actually verify) ----
  String badgeId = '';
  VerificationStatus responderStatus = VerificationStatus.pending;

  final List<Contact> contacts = [];
  final List<SessionRecord> sessionHistory = [];
  final List<AppNotification> notifications = [];

  // ---- Real-life uniqueness checks -------------------------------------
  // Two different people essentially never share the exact same phone
  // number or email address, so either being already saved on another
  // contact (or on the signed-in user's own identity) means this is a
  // duplicate, not a new person. Name matching is blunter — different real
  // people can share a full name — but it's included for the same
  // treatment, at the requester's request.
  String _normName(String s) => s.trim().toLowerCase();
  String _normEmail(String s) => s.trim().toLowerCase();
  String _normPhone(String s) => s.replaceAll(RegExp(r'[^0-9]'), '');

  /// True if [candidateName] already belongs to another saved contact, or
  /// to the signed-in user themselves. Pass [excludingId] when editing an
  /// existing contact so it doesn't collide with itself.
  bool isContactNameTaken(String candidateName, {String? excludingId}) {
    final n = _normName(candidateName);
    if (n.isEmpty) return false;
    if (n == _normName(fullName)) return true;
    return contacts
        .any((c) => c.id != excludingId && _normName(c.fullName) == n);
  }

  bool isContactPhoneTaken(String candidatePhone, {String? excludingId}) {
    final n = _normPhone(candidatePhone);
    if (n.isEmpty) return false;
    if (n == _normPhone(phone)) return true;
    return contacts.any((c) => c.id != excludingId && _normPhone(c.phone) == n);
  }

  bool isContactEmailTaken(String candidateEmail, {String? excludingId}) {
    final n = _normEmail(candidateEmail);
    if (n.isEmpty) return false;
    if (n == _normEmail(email)) return true;
    return contacts.any((c) => c.id != excludingId && _normEmail(c.email) == n);
  }

  /// The reverse direction — used when the signed-in user edits their own
  /// name/phone/email, to stop them taking on the identity of one of their
  /// own saved contacts.
  bool isOwnNameTakenByContact(String candidateName) =>
      contacts.any((c) => _normName(c.fullName) == _normName(candidateName));
  bool isOwnPhoneTakenByContact(String candidatePhone) =>
      contacts.any((c) => _normPhone(c.phone) == _normPhone(candidatePhone));
  bool isOwnEmailTakenByContact(String candidateEmail) =>
      contacts.any((c) => _normEmail(c.email) == _normEmail(candidateEmail));

  // Real chat threads, keyed by contact id. Only messages the person
  // actually sent from this device live here — no seeded conversations.
  final Map<String, List<ChatMessage>> _chatThreads = {};

  // Real escalated incidents, shared across the whole app instance so the
  // Responder Dashboard reflects sessions that actually reached final
  // escalation, instead of fabricated example people.
  final List<Incident> activeIncidents = [];

  // ---- Profile preferences ----
  bool notificationsEnabled = true;
  bool locationSharingEnabled = true;
  bool availableToHelp = false;
  String language = 'English';
  String themeName = 'Light';
  bool locationPermissionDeclined = false;

  // ---- Last-known-location cache ----
  // Updated continuously while a session has a live GPS fix. If live
  // location is lost (no signal / offline / permission revoked) right when
  // an alert needs to go out, this is the honest fallback — sent with a
  // clear "last known as of HH:MM" label rather than silently failing.
  LatLng? lastKnownPosition;
  DateTime? lastKnownPositionAt;

  bool get isLoggedIn => email.isNotEmpty;

  String get initials {
    final parts = fullName
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    } else if (parts.isNotEmpty) {
      return parts[0][0].toUpperCase();
    }
    return '?';
  }

  Contact? get mainContact {
    for (final c in contacts) {
      if (c.status == ContactStatus.friend && c.isMainContact) return c;
    }
    final friends = contacts.where((c) => c.status == ContactStatus.friend);
    return friends.isNotEmpty ? friends.first : null;
  }

  /// The next contact in line after the main contact — used for the
  /// main → secondary escalation stage. Just the next confirmed friend in
  /// the list that isn't the main one; there's no separate "secondary"
  /// flag on Contact, so order is what we have without adding a new field.
  Contact? get secondaryContact {
    final main = mainContact;
    for (final c in contacts) {
      if (c.status == ContactStatus.friend && c.id != main?.id) return c;
    }
    return null;
  }

  /// Confirmed friends only — pending requests can't be notified or
  /// escalated to until the other person actually confirms.
  List<Contact> get friends =>
      contacts.where((c) => c.status == ContactStatus.friend).toList();

  List<Contact> get pendingRequests =>
      contacts.where((c) => c.status == ContactStatus.pending).toList();

  /// Resolves the contact ids confirmed for a specific session (passed
  /// through from Setup Safety Session) back into real Contact objects,
  /// confirmed friends only.
  List<Contact> contactsByIds(List<String> ids) => contacts
      .where((c) => c.status == ContactStatus.friend && ids.contains(c.id))
      .toList();

  /// Simulates the other person accepting a friend request — this app has
  /// no backend to actually deliver/receive that confirmation, so this is
  /// the honest, demo-only stand-in for it. Only ever called internally by
  /// [sendFriendRequest]'s simulated delay — never directly from a button
  /// the *sender* taps, since confirming your own outgoing request isn't
  /// something the sender should be able to do.
  void _acceptFriendRequest(String id) {
    final index = contacts.indexWhere((c) => c.id == id);
    if (index != -1 && contacts[index].status == ContactStatus.pending) {
      contacts[index] = contacts[index].copyWith(status: ContactStatus.friend);
      addNotification(
        title: '${contacts[index].fullName} accepted your request',
        body:
            '${contacts[index].fullName} is now one of your trusted contacts.',
        kind: NotificationKind.trustedContact,
      );
      notifyListeners();
    }
  }

  /// Sends a friend request to a new contact. The contact is saved as
  /// [ContactStatus.pending] and stays that way until the *other* person
  /// accepts — there's no backend in this build to deliver a real request
  /// to their device, so acceptance is simulated after a short delay
  /// instead of letting the sender confirm their own request (which would
  /// defeat the point of a request in the first place).
  void sendFriendRequest(Contact contact) {
    upsertContact(contact);
    Future.delayed(const Duration(seconds: 6), () {
      _acceptFriendRequest(contact.id);
    });
  }

  // ---- Plan / paywall ----
  // SafetyU's free plan caps how many contacts can be notified per safety
  // session: up to 2 Main and 2 Other. Going over that shows the upgrade /
  // pay-per-contact paywall instead of silently notifying everyone.
  static const int freeMainContactLimit = 2;
  static const int freeOtherContactLimit = 1;

  bool isPro = false;
  int purchasedExtraMainSlots = 0;
  int purchasedExtraOtherSlots = 0;

  int get maxMainContacts =>
      isPro ? 1 << 30 : freeMainContactLimit + purchasedExtraMainSlots;
  int get maxOtherContacts =>
      isPro ? 1 << 30 : freeOtherContactLimit + purchasedExtraOtherSlots;

  void upgradeToPro() {
    isPro = true;
    notifyListeners();
  }

  /// Simulates a one-time "pay per extra contact" purchase — there's no
  /// real payment processor in this build, so this just grants the slots.
  void purchaseExtraSlots({int extraMain = 0, int extraOther = 0}) {
    purchasedExtraMainSlots += extraMain;
    purchasedExtraOtherSlots += extraOther;
    notifyListeners();
  }

  void signIn({
    required String fullName,
    required String email,
    required String phone,
    required UserRole role,
  }) {
    this.fullName = fullName;
    this.email = email;
    this.phone = phone;
    this.role = role;
    notifyListeners();
  }

  void signOut() {
    fullName = '';
    email = '';
    phone = '';
    role = UserRole.user;
    authToken = null;
    backendUserId = null;
    activeCheckInId = null;
    contacts.clear();
    profilePhotoPath = null;
    // Session history, notifications, and incidents intentionally persist
    // across sign-out in this local-only build so nothing the person did
    // is lost just from logging out again during testing.
    notifyListeners();
  }

  // ---- Chat ----

  List<ChatMessage> messagesFor(String contactId) =>
      List.unmodifiable(_chatThreads[contactId] ?? const []);

  ChatMessage sendChatMessage(
    String contactId,
    String text, {
    ChatMessageKind kind = ChatMessageKind.text,
    bool isMe = true,
  }) {
    final message = ChatMessage(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      text: text,
      isMe: isMe,
      sentAt: DateTime.now(),
      kind: kind,
    );
    _chatThreads.putIfAbsent(contactId, () => []).add(message);
    notifyListeners();
    return message;
  }

  // Any number of contacts can be marked as "Main" — the free-plan cap on
  // how many *notified* main contacts a session can use is enforced at
  // notify-selection time (see maxMainContacts / SelectContactsScreen),
  // not here. Marking a new contact as Main must never silently demote an
  // existing Main contact to Other.
  void upsertContact(Contact contact) {
    final index = contacts.indexWhere((c) => c.id == contact.id);
    if (index >= 0) {
      contacts[index] = contact;
    } else {
      contacts.add(contact);
    }
    notifyListeners();
  }

  void removeContact(String id) {
    contacts.removeWhere((c) => c.id == id);
    notifyListeners();
  }

  // ---- Session history ----

  void addSessionRecord(SessionRecord record) {
    sessionHistory.insert(0, record);
    notifyListeners();
  }

  // ---- Notifications ----

  void addNotification({
    required String title,
    required String body,
    required NotificationKind kind,
  }) {
    notifications.insert(
      0,
      AppNotification(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        title: title,
        body: body,
        kind: kind,
        createdAt: DateTime.now(),
      ),
    );
    notifyListeners();
  }

  void clearNotifications() {
    notifications.clear();
    notifyListeners();
  }

  int get unreadNotificationCount =>
      notifications.where((n) => !n.isRead).length;

  void markAllNotificationsRead() {
    if (notifications.isEmpty) return;
    for (final n in notifications) {
      n.isRead = true;
    }
    notifyListeners();
  }

  // ---- Trust respond flow ----
  /// Builds the real, current "can you help" context a given trusted
  /// [contact] would be shown — using this person's own actual latest
  /// session destination and last known position. The [contact] parameter
  /// is kept for callers that want to personalize the request per
  /// recipient later; nothing here is fabricated.
  HelpRequest buildHelpRequestFor(Contact contact) {
    final latestSession =
        sessionHistory.isNotEmpty ? sessionHistory.first : null;
    // SessionRecord only keeps the destination name, not its coordinates,
    // so there's no second real point to measure against — distance is
    // left null (shown as "unavailable") rather than guessed.
    return HelpRequest(
      requesterName: fullName.isEmpty ? 'You' : fullName,
      requesterPhone: phone,
      destination: latestSession?.destination ?? 'their destination',
      location: lastKnownPosition,
      distanceKm: null,
      requestedAt: latestSession?.startedAt ?? DateTime.now(),
    );
  }

  // ---- Current alert's per-contact response tracking ----
  // Reset at the start of every new session; lets Home show, in real
  // time, who was notified and whether they've responded yet.
  final List<ContactResponseState> currentAlertResponses = [];

  void clearCurrentAlertResponses() {
    currentAlertResponses.clear();
    notifyListeners();
  }

  void replaceAlertResponsesFromBackend(List<Map<String, dynamic>> contacts) {
    currentAlertResponses
      ..clear()
      ..addAll(contacts.map((contact) {
        final status = switch (contact['responseStatus']?.toString()) {
          'can_help' => ContactResponseStatus.canHelp,
          'cannot_help' => ContactResponseStatus.cantHelp,
          _ => ContactResponseStatus.pending,
        };
        final notifiedAt = DateTime.tryParse(contact['notifiedAt']?.toString() ?? '') ?? DateTime.now();
        return ContactResponseState(
          contactId: contact['userId']?.toString() ?? '',
          contactName: contact['name']?.toString() ?? 'Unknown contact',
          status: status,
          notifiedAt: notifiedAt,
        );
      }));
    notifyListeners();
  }

  void registerContactNotified(Contact contact) {
    final i =
        currentAlertResponses.indexWhere((r) => r.contactId == contact.id);
    if (i != -1) {
      currentAlertResponses[i].status = ContactResponseStatus.pending;
    } else {
      currentAlertResponses.add(ContactResponseState(
        contactId: contact.id,
        contactName: contact.fullName,
        status: ContactResponseStatus.pending,
        notifiedAt: DateTime.now(),
      ));
    }
    notifyListeners();
  }

  void recordContactOutcome(String contactId, ContactResponseStatus status) {
    final i = currentAlertResponses.indexWhere((r) => r.contactId == contactId);
    if (i != -1) {
      currentAlertResponses[i].status = status;
      notifyListeners();
    }
  }

  /// When one contact confirms they can help, let every other contact who
  /// was also notified in this same alert (and hasn't answered yet) know,
  /// so they don't all rush to the same place at once.
  void notifyOthersHelping(String helperContactId, String helperName) {
    for (final r in currentAlertResponses) {
      if (r.contactId == helperContactId) continue;
      if (r.status != ContactResponseStatus.pending) continue;
      sendChatMessage(
        r.contactId,
        "Update: $helperName confirmed they're on the way to help. You don't need to go unless asked.",
        kind: ChatMessageKind.text,
      );
      addNotification(
        title: r.contactName,
        body: '$helperName can help — you can stand by for now.',
        kind: NotificationKind.trustedContact,
      );
    }
  }

  void markContactTimedOut(String contactId) {
    final i = currentAlertResponses.indexWhere((r) => r.contactId == contactId);
    if (i != -1 &&
        currentAlertResponses[i].status == ContactResponseStatus.pending) {
      currentAlertResponses[i].status = ContactResponseStatus.timedOut;
      notifyListeners();
    }
  }

  // ---- Last-known-location cache ----

  void updateLastKnownPosition(LatLng position) {
    lastKnownPosition = position;
    lastKnownPositionAt = DateTime.now();
  }

  // ---- Incidents (final escalation to Emergency Responders) ----

  void addIncident(Incident incident) {
    activeIncidents.insert(0, incident);
    notifyListeners();
  }

  void resolveIncident(String id) =>
      setIncidentStatus(id, IncidentStatus.resolved);

  /// Single choke point for every responder-side status change — used by
  /// "Take Case", "Mark as Resolved", and "Cancel", from whichever screen
  /// triggers them. Flips the status *and* tells the actual people
  /// affected: an in-app notification for the requester, plus a real chat
  /// message to every trusted contact who was alerted about this case, so
  /// nobody is left wondering what happened after a status silently
  /// changes underneath them.
  void setIncidentStatus(String id, IncidentStatus status) {
    Incident? incident;
    for (final i in activeIncidents) {
      if (i.id == id) {
        incident = i;
        break;
      }
    }
    if (incident == null) return;

    final previousStatus = incident.status;
    incident.status = status;
    if (status == IncidentStatus.resolved) {
      incident.resolvedAt = DateTime.now();
    }

    if (previousStatus != status) {
      _notifyIncidentStatusChange(incident, status);
    }

    notifyListeners();
  }

  void _notifyIncidentStatusChange(Incident incident, IncidentStatus status) {
    final String requesterBody;
    final String contactMessage;
    switch (status) {
      case IncidentStatus.inProgress:
        requesterBody =
            'An Emergency Responder has taken your case and is on the way.';
        contactMessage =
            "Update: an Emergency Responder has taken ${incident.personName}'s case and is on the way.";
        break;
      case IncidentStatus.resolved:
        requesterBody = 'Your case has been marked resolved by a responder.';
        contactMessage =
            "Update: ${incident.personName}'s case has been marked resolved by an Emergency Responder.";
        break;
      case IncidentStatus.newCase:
        requesterBody =
            'Your case was reopened and is waiting for a responder again.';
        contactMessage =
            "Update: ${incident.personName}'s case was reopened and is waiting for a responder again.";
        break;
    }

    // The requester's own notification feed. This is a single-device demo
    // with no backend to push to the requester's phone specifically, so
    // this in-app feed is the honest stand-in for "tell the requester."
    addNotification(
      title: 'Emergency Responders',
      body: requesterBody,
      kind: NotificationKind.emergency,
    );

    // Every trusted contact who was actually alerted about this case
    // before it escalated — never the requester's whole friends list.
    for (final contactId in incident.notifiedContactIds) {
      sendChatMessage(contactId, contactMessage);
    }
  }
}
