/// Models for POST /api/test-fix-expediter/resume-from.
library;

// ─────────────────────────────────────────────
// Request
// ─────────────────────────────────────────────

class TfeResumeFromRequest {
  /// Job ID (e.g. "tfe-abc123"), plan file path, or plain description.
  final String resumeFrom;

  const TfeResumeFromRequest( { required this.resumeFrom } );

  Map<String, dynamic> toJson() => { 'resume_from' : resumeFrom };
}
