import 'package:equatable/equatable.dart';

/// DISPOSITION (AC-S1.10, 2026-08-29): **LEFT ALONE — not superseded by
/// [JobLane], and not quarantined.**
///
/// Three lane vocabularies exist in this tree and this is one of them. They
/// are not redundant copies of each other:
///
///   * [JobLane] (`features/queue/domain/job_lifecycle.dart`) mirrors the
///     SERVER's `STATE_TO_UI_CONTAINER` verbatim and is the wire vocabulary.
///     Its member names are the correct ones for anything reading a
///     `job_state_transition` frame or a `/api/get-queue/{name}` listing.
///   * `JobStatus` (here) belongs to the LOCAL `Job` record persisted through
///     `JobRepository` (`core/repositories/impl/job_repository_impl.dart`,
///     wired in `use_case_registry.dart`). It never touches the wire.
///
/// ⚠️ They disagree on two of four members — `running`/`completed` here vs
/// `run`/`done` there. That is stated rather than silently tolerated: renaming
/// this enum to match would change a persisted local model's serialized values
/// for no gain, since nothing maps between the two. **If a mapping is ever
/// introduced, it goes in one named adapter — never by assuming the names
/// line up.**
enum JobStatus {
  todo,
  running,
  completed,
  dead,
}

class Job extends Equatable {
  final String id;
  final String text;
  final JobStatus status;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final String? result;
  final String? error;
  final Map<String, dynamic>? metadata;

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