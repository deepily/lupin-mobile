import 'package:equatable/equatable.dart';

/// Lifecycle state of a locally stored [Job]; never sent over the wire.
///
/// [JobLane] is the wire vocabulary and is not replaced by this enum. They
/// disagree on two of four members (`running`/`completed` here, `run`/`done`
/// there), and nothing maps between them. If a mapping is needed, write one named
/// adapter; do not assume the names match.
///
/// Decision: src/docs/decisions/README.md (JobStatus-kept).
enum JobStatus {
  /// Queued and not yet started.
  todo,
  /// In progress.
  running,
  /// Finished successfully.
  completed,
  /// Abandoned after a failure and not retried.
  dead,
}

/// One locally stored job and its outcome.
class Job extends Equatable {
  /// Unique job identifier.
  final String id;
  /// The request text the job carries.
  final String text;
  /// Current lifecycle state.
  final JobStatus status;
  /// When the job was created.
  final DateTime createdAt;
  /// When the job last changed, or null if it never has.
  final DateTime? updatedAt;
  /// The outcome text, or null until the job finishes.
  final String? result;
  /// The failure message, or null when the job has not failed.
  final String? error;
  /// Free-form extra fields, or null.
  final Map<String, dynamic>? metadata;

  /// Creates a job.
  const Job({
    required this.id,
    required this.text,
    required this.status,
    required this.createdAt,
    this.updatedAt,
    this.result,
    this.error,
    this.metadata,
  });

  /// Returns a copy with the given fields replaced.
  Job copyWith({
    String? id,
    String? text,
    JobStatus? status,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? result,
    String? error,
    Map<String, dynamic>? metadata,
  }) {
    return Job(
      id: id ?? this.id,
      text: text ?? this.text,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      result: result ?? this.result,
      error: error ?? this.error,
      metadata: metadata ?? this.metadata,
    );
  }

  /// Builds a job from its wire map; an unknown status becomes todo.
  factory Job.fromJson(Map<String, dynamic> json) {
    return Job(
      id: json['id'] as String,
      text: json['text'] as String,
      status: JobStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => JobStatus.todo,
      ),
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: json['updated_at'] != null 
          ? DateTime.parse(json['updated_at'] as String)
          : null,
      result: json['result'] as String?,
      error: json['error'] as String?,
      metadata: json['metadata'] as Map<String, dynamic>?,
    );
  }

  /// Returns the wire map for this job.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'text': text,
      'status': status.name,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
      'result': result,
      'error': error,
      'metadata': metadata,
    };
  }

  @override
  List<Object?> get props => [
        id,
        text,
        status,
        createdAt,
        updatedAt,
        result,
        error,
        metadata,
      ];
}