/// Status of an Emergency Responder account.
///
/// IMPORTANT: SafetyU has no backend, so this app cannot itself verify that
/// a badge ID belongs to a real officer — that requires checking against a
/// real department directory. [pending] is the honest default for every
/// new responder signup; [verified] only flips via the demo-only
/// "Simulate Approval" action so the rest of the flow is testable.
enum VerificationStatus { pending, verified }
