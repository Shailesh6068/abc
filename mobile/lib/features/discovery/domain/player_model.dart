import 'package:equatable/equatable.dart';

class NearbyPlayer extends Equatable {
  final String userId;
  final String displayName;
  final String? avatarUrl;
  final int approxDistanceM;
  final String sport;
  final bool isAvailable;
  final int rating;

  const NearbyPlayer({
    required this.userId,
    required this.displayName,
    this.avatarUrl,
    required this.approxDistanceM,
    required this.sport,
    required this.isAvailable,
    required this.rating,
  });

  factory NearbyPlayer.fromJson(Map<String, dynamic> json) {
    return NearbyPlayer(
      userId: json['user_id'] as String,
      displayName: json['display_name'] as String? ?? 'Racer',
      avatarUrl: json['avatar_url'] as String?,
      approxDistanceM: json['approx_distance_m'] as int? ?? 0,
      sport: json['sport'] as String? ?? 'running',
      isAvailable: json['is_available'] as bool? ?? true,
      rating: json['rating'] as int? ?? 1200,
    );
  }

  @override
  List<Object?> get props => [userId, displayName, approxDistanceM, sport, isAvailable, rating];
}
