import 'package:equatable/equatable.dart';

class RaceParticipant extends Equatable {
  final String userId;
  final String displayName;
  final String? avatarUrl;
  final String status; // 'joined', 'ready', 'racing', 'finished', 'dnf', 'disqualified'
  final DateTime joinedAt;
  final DateTime? readyAt;
  final double validatedDistanceM;
  final int? finishTimeMs;

  const RaceParticipant({
    required this.userId,
    required this.displayName,
    this.avatarUrl,
    required this.status,
    required this.joinedAt,
    this.readyAt,
    this.validatedDistanceM = 0.0,
    this.finishTimeMs,
  });

  factory RaceParticipant.fromJson(Map<String, dynamic> json) {
    String displayName = 'Racer';
    String? avatarUrl;
    final prof = json['profiles'];
    if (prof is Map) {
      displayName = prof['display_name'] as String? ?? 'Racer';
      avatarUrl = prof['avatar_url'] as String?;
    } else if (prof is List && prof.isNotEmpty && prof.first is Map) {
      displayName = (prof.first as Map)['display_name'] as String? ?? 'Racer';
      avatarUrl = (prof.first as Map)['avatar_url'] as String?;
    }

    final joined = json['joined_at'] != null ? (DateTime.tryParse(json['joined_at'] as String) ?? DateTime.now()) : DateTime.now();
    final ready = json['ready_at'] != null ? DateTime.tryParse(json['ready_at'] as String) : null;

    return RaceParticipant(
      userId: json['user_id'] as String,
      displayName: displayName,
      avatarUrl: avatarUrl,
      status: json['status'] as String? ?? 'joined',
      joinedAt: joined,
      readyAt: ready,
      validatedDistanceM: (json['validated_distance_m'] as num?)?.toDouble() ?? 0.0,
      finishTimeMs: (json['finish_time_ms'] as num?)?.toInt(),
    );
  }

  @override
  List<Object?> get props => [userId, displayName, status, validatedDistanceM, finishTimeMs];
}

class RaceModel extends Equatable {
  final String id;
  final String creatorId;
  final String sport;
  final String mode;
  final String visibility;
  final String status;
  final int participantLimit;
  final String? routeId;
  final Map<String, dynamic> configuration;
  final DateTime? scheduledStartAt;
  final DateTime? actualStartAt;
  final DateTime createdAt;
  final List<RaceParticipant> participants;

  const RaceModel({
    required this.id,
    required this.creatorId,
    required this.sport,
    required this.mode,
    required this.visibility,
    required this.status,
    required this.participantLimit,
    this.routeId,
    required this.configuration,
    this.scheduledStartAt,
    this.actualStartAt,
    required this.createdAt,
    this.participants = const [],
  });

  factory RaceModel.fromJson(Map<String, dynamic> json, {List<RaceParticipant> participants = const []}) {
    Map<String, dynamic> config = {};
    if (json['configuration'] is Map) {
      config = Map<String, dynamic>.from(json['configuration'] as Map);
    }

    return RaceModel(
      id: json['id'] as String,
      creatorId: json['creator_id'] as String,
      sport: json['sport'] as String,
      mode: json['mode'] as String,
      visibility: json['visibility'] as String? ?? 'public',
      status: json['status'] as String,
      participantLimit: (json['participant_limit'] as num?)?.toInt() ?? 4,
      routeId: json['route_id'] as String?,
      configuration: config,
      scheduledStartAt: json['scheduled_start_at'] != null ? DateTime.tryParse(json['scheduled_start_at'] as String) : null,
      actualStartAt: json['actual_start_at'] != null ? DateTime.tryParse(json['actual_start_at'] as String) : null,
      createdAt: json['created_at'] != null ? (DateTime.tryParse(json['created_at'] as String) ?? DateTime.now()) : DateTime.now(),
      participants: participants,
    );
  }

  @override
  List<Object?> get props => [id, creatorId, sport, mode, status, participantLimit, participants];
}
