enum SessionOutcome { safe, delayed, sos }

extension SessionOutcomeX on SessionOutcome {
  String get label {
    switch (this) {
      case SessionOutcome.safe:
        return 'Safe';
      case SessionOutcome.delayed:
        return 'Delayed';
      case SessionOutcome.sos:
        return 'SOS';
    }
  }
}

/// A completed (or ongoing) safety session, logged for real from actual
/// app events — not seeded example data. Created when a session starts,
/// and finalized when the person taps "I'm Safe" or an SOS goes out.
class SessionRecord {
  final String id;
  final String destination;
  final DateTime startedAt;
  final DateTime? endedAt;
  final SessionOutcome outcome;
  final bool hadDelay;

  const SessionRecord({
    required this.id,
    required this.destination,
    required this.startedAt,
    required this.endedAt,
    required this.outcome,
    this.hadDelay = false,
  });
}
