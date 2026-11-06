import 'package:equatable/equatable.dart';

class NearbyPlayer extends Equatable {
  final String userId;
  final String displayName;
  final String? avatarUrl;
  final int approxDistanceM;
  final String sport;
  final bool isAvailable;
  final int rating;
  final bool isBot;

  const NearbyPlayer({
    required this.userId,
    required this.displayName,
    this.avatarUrl,
    required this.approxDistanceM,
    required this.sport,
    required this.isAvailable,
    required this.rating,
    this.isBot = false,
  });

  factory NearbyPlayer.fromJson(Map<String, dynamic> json, {bool isBot = false}) {
    return NearbyPlayer(
      userId: json['user_id']?.toString() ?? '',
      displayName: json['display_name'] as String? ?? 'Racer',
      avatarUrl: json['avatar_url'] as String?,
      approxDistanceM: (json['approx_distance_m'] as num?)?.toInt() ?? 0,
      sport: json['sport'] as String? ?? 'running',
      isAvailable: json['is_available'] as bool? ?? true,
      rating: (json['rating'] as num?)?.toInt() ?? 1200,
      isBot: isBot,
    );
  }

  @override
  List<Object?> get props => [userId, displayName, approxDistanceM, sport, isAvailable, rating, isBot];
}
