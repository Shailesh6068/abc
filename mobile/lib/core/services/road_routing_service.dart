import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:racezone/core/utils/geo_utils.dart';

class RoadRouteResult {
  final double distanceMeters;
  final List<LatLng> points;
  final bool isStreetRoute;

  const RoadRouteResult({
    required this.distanceMeters,
    required this.points,
    required this.isStreetRoute,
  });
}

class RoadRoutingService {
  static final HttpClient _httpClient = HttpClient()
    ..connectionTimeout = const Duration(seconds: 4);

  /// Fetch true street/road following path using OSRM walking/driving engine
  static Future<RoadRouteResult> getRoadRoute({
    required LatLng start,
    required LatLng destination,
    String sport = 'running',
  }) async {
    // Mode profile: foot for running/walking, driving for motorbike, foot/bike for cycling
    final profile = sport == 'motorbike' ? 'driving' : 'foot';
    final url = Uri.parse(
      'https://router.project-osrm.org/route/v1/$profile/'
      '${start.longitude},${start.latitude};${destination.longitude},${destination.latitude}'
      '?overview=full&geometries=geojson',
    );

    try {
      final request = await _httpClient.getUrl(url).timeout(const Duration(seconds: 4));
      request.headers.set('User-Agent', 'RaceZone-Mobile/1.0');
      final response = await request.close().timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final body = await response.transform(utf8.decoder).join();
        final data = jsonDecode(body) as Map<String, dynamic>;

        if (data['code'] == 'Ok' && (data['routes'] as List).isNotEmpty) {
          final route = data['routes'][0] as Map<String, dynamic>;
          final double distanceM = (route['distance'] as num).toDouble();
          final rawCoords = (route['geometry']['coordinates'] as List);

          final List<LatLng> points = [];
          for (final coord in rawCoords) {
            final c = coord as List;
            // GeoJSON coordinates are [longitude, latitude]
            points.add(LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()));
          }

          if (points.isNotEmpty) {
            return RoadRouteResult(
              distanceMeters: distanceM,
              points: points,
              isStreetRoute: true,
            );
          }
        }
      }
    } catch (e) {
      debugPrint('OSRM routing fallback to direct line: $e');
    }

    // Fallback: Haversine straight line if offline or server timeout
    final fallbackDist = GeoUtils.haversineDistanceMeters(
      start.latitude,
      start.longitude,
      destination.latitude,
      destination.longitude,
    );

    return RoadRouteResult(
      distanceMeters: fallbackDist,
      points: [start, destination],
      isStreetRoute: false,
    );
  }
}
