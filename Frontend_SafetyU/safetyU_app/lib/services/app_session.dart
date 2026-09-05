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

  // ---- Emergency Responder identity (see verification_status.dart for
  // an honest note on what this app can and can't actually verify) ----
  String badgeId = '';
  VerificationStatus responderStatus = VerificationStatus.pending;

  final List<Contact> contacts = [];
  final List<SessionRecord> sessionHistory = [];
  final List<AppNotification> notifications = [];

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
      if (c.isMainContact) return c;
    }
    return contacts.isNotEmpty ? contacts.first : null;
  }

  /// The next contact in line after the main contact — used for the
  /// main → secondary escalation stage. Just the next contact in the list
  /// that isn't the main one; there's no separate "secondary" flag on
  /// Contact, so order is what we have without adding a new field.
  Contact? get secondaryContact {
    final main = mainContact;
    for (final c in contacts) {
      if (c.id != main?.id) return c;
    }
    return null;
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
    contacts.clear();
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

  void upsertContact(Contact contact) {
    final index = contacts.indexWhere((c) => c.id == contact.id);
    if (index >= 0) {
      contacts[index] = contact;
    } else {
      contacts.add(contact);
    }
    if (contact.isMainContact) {
      for (var i = 0; i < contacts.length; i++) {
        if (contacts[i].id != contact.id) {
          contacts[i] = contacts[i].copyWith(isMainContact: false);
        }
      }
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

  void resolveIncident(String id) {
    for (final incident in activeIncidents) {
      if (incident.id == id) {
        incident.responded = true;
        break;
      }
    }
    notifyListeners();
  }
}
