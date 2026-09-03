/// The two account types SafetyU supports.
///
/// [user] is a regular person using safety check-in sessions.
/// [emergencyResponder] is someone who monitors and responds to
/// other users' active sessions and SOS alerts.
enum UserRole { user, emergencyResponder }

extension UserRoleX on UserRole {
  String get label {
    switch (this) {
      case UserRole.user:
        return 'User';
      case UserRole.emergencyResponder:
        return 'Emergency Responder';
    }
  }

  String get description {
    switch (this) {
      case UserRole.user:
        return 'Start safety sessions and alert your trusted contacts.';
      case UserRole.emergencyResponder:
        return 'Monitor active sessions and respond to SOS alerts.';
    }
  }

  /// Route this role should land on after login/signup.
  String get homeRoute {
    switch (this) {
      case UserRole.user:
        return '/home';
      case UserRole.emergencyResponder:
        return '/emergency-home';
    }
  }
}
