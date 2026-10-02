/// Models for POST /api/test-fix-expediter/resume-from.
library;

// ─────────────────────────────────────────────
// Request
// ─────────────────────────────────────────────

/// Request to resume a test-fix-expediter job from an earlier point.
class TfeResumeFromRequest {
  /// Job ID (e.g. "tfe-abc123"), plan file path, or plain description.
  final String resumeFrom;

  /// Creates a request that resumes from [resumeFrom].
  const TfeResumeFromRequest( { required this.resumeFrom } );

  /// Builds the JSON body of the resume endpoint.
  Map<String, dynamic> toJson() => { 'resume_from' : resumeFrom };
}
