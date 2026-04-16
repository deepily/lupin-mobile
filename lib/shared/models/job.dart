import 'package:equatable/equatable.dart';

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