import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:racezone/core/constants/app_colors.dart';
import 'package:racezone/core/constants/app_typography.dart';
import 'package:racezone/core/services/road_routing_service.dart';
import 'package:racezone/core/utils/geo_utils.dart';

class DestinationMapPickerScreen extends StatefulWidget {
  final LatLng initialUserLocation;
  final LatLng? initialTargetLocation;
  final String? initialName;
  final String sport;

  const DestinationMapPickerScreen({
    super.key,
    required this.initialUserLocation,
    this.initialTargetLocation,
    this.initialName,
    this.sport = 'running',
  });

  @override
  State<DestinationMapPickerScreen> createState() => _DestinationMapPickerScreenState();
}

class _DestinationMapPickerScreenState extends State<DestinationMapPickerScreen> {
  GoogleMapController? _mapController;
  late LatLng _targetLocation;
  late TextEditingController _nameController;
  MapType _currentMapType = MapType.normal;

  // Road Routing State
  List<LatLng> _routePoints = [];
  double _routeDistanceM = 0.0;
  bool _isLoadingRoute = false;
  bool _isStreetRoute = false;
  int _routeRequestId = 0;

  @override
  void initState() {
    super.initState();
    // Default target ~750m north-east of user location if none passed
    _targetLocation = widget.initialTargetLocation ??
        LatLng(
          widget.initialUserLocation.latitude + 0.0055,
          widget.initialUserLocation.longitude + 0.0040,
        );

    final defaultAirDist = GeoUtils.haversineDistanceMeters(
      widget.initialUserLocation.latitude,
      widget.initialUserLocation.longitude,
      _targetLocation.latitude,
      _targetLocation.longitude,
    );
    _routeDistanceM = defaultAirDist;

    _nameController = TextEditingController(
      text: widget.initialName ?? 'Custom Finish Point (${GeoUtils.formatDistance(defaultAirDist)})',
    );

    // Automatically calculate road route on opening
    _fetchRoadRoute(_targetLocation);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _fetchRoadRoute(LatLng target) async {
    final reqId = ++_routeRequestId;
    setState(() => _isLoadingRoute = true);

    try {
      final result = await RoadRoutingService.getRoadRoute(
        start: widget.initialUserLocation,
        destination: target,
        sport: widget.sport,
      );

      if (!mounted || reqId != _routeRequestId) return;

      setState(() {
        _isLoadingRoute = false;
        _routePoints = result.points;
        _routeDistanceM = result.distanceMeters;
        _isStreetRoute = result.isStreetRoute;
        _nameController.text = 'Custom Finish Point (${GeoUtils.formatDistance(result.distanceMeters)})';
      });
    } catch (_) {
      if (mounted && reqId == _routeRequestId) setState(() => _isLoadingRoute = false);
    }
  }

  Set<Marker> _buildMarkers() {
    return {
      // 1. Host Start Point
      Marker(
        markerId: const MarkerId('start_location'),
        position: widget.initialUserLocation,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        infoWindow: const InfoWindow(title: 'Race Start (Your Location)'),
      ),

      // 2. Destination Finish Pin
      Marker(
        markerId: const MarkerId('finish_destination'),
        position: _targetLocation,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueYellow),
        infoWindow: InfoWindow(
          title: '🏁 Finish: ${_nameController.text.trim()}',
          snippet: 'Road Distance: ${GeoUtils.formatDistance(_routeDistanceM)}',
        ),
      ),
    };
  }

  Set<Circle> _buildCircles() {
    return {
      Circle(
        circleId: const CircleId('finish_circle_zone'),
        center: _targetLocation,
        radius: 35.0,
        fillColor: AppColors.primaryGreen.withValues(alpha: 0.35),
        strokeColor: AppColors.primaryGreen,
        strokeWidth: 2,
      ),
    };
  }

  Set<Polyline> _buildPolylines() {
    final pointsToDraw = _routePoints.isNotEmpty
        ? _routePoints
        : [widget.initialUserLocation, _targetLocation];

    return {
      Polyline(
        polylineId: const PolylineId('picker_road_guideline'),
        points: pointsToDraw,
        color: AppColors.primaryCyan,
        width: 5,
        // If it's a real street route, solid path following roads; if fallback, dashed
        patterns: _isStreetRoute ? [] : [PatternItem.dash(15), PatternItem.gap(10)],
      ),
    };
  }

  void _onMapTapped(LatLng position) {
    setState(() {
      _targetLocation = position;
    });
    _fetchRoadRoute(position);
  }

  void _confirmSelection() {
    final name = _nameController.text.trim().isNotEmpty
        ? _nameController.text.trim()
        : 'Custom Finish Point (${GeoUtils.formatDistance(_routeDistanceM)})';

    Navigator.pop(context, {
      'lat': _targetLocation.latitude,
      'lng': _targetLocation.longitude,
      'name': name,
      'distance_m': _routeDistanceM,
      'route_points': _routePoints.map((p) => [p.latitude, p.longitude]).toList(),
      'is_street_route': _isStreetRoute,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.backgroundSecondary,
        elevation: 0,
        title: const Text('Pick Destination On Map', style: AppTypography.titleLarge),
        leading: IconButton(
          icon: const Icon(Icons.close, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: Icon(_currentMapType == MapType.normal ? Icons.satellite_alt : Icons.map, color: AppColors.primaryCyan),
            tooltip: 'Toggle Satellite',
            onPressed: () {
              setState(() {
                _currentMapType = _currentMapType == MapType.normal ? MapType.satellite : MapType.normal;
              });
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          // Google Map Engine
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: _targetLocation,
              zoom: 15,
            ),
            mapType: _currentMapType,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            compassEnabled: true,
            markers: _buildMarkers(),
            circles: _buildCircles(),
            polylines: _buildPolylines(),
            onMapCreated: (ctrl) => _mapController = ctrl,
            onTap: _onMapTapped,
          ),

          // Top Instruction & Name Input Card
          Positioned(
            top: 14,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.primaryCyan.withValues(alpha: 0.4)),
                boxShadow: AppColors.cardShadow,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: AppColors.primaryCyan.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.touch_app, color: AppColors.primaryCyan, size: 18),
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Tap map to set finish — routes along streets!',
                          style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.primaryGreen.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.primaryGreen.withValues(alpha: 0.4)),
                        ),
                        child: _isLoadingRoute
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primaryGreen),
                              )
                            : Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    GeoUtils.formatDistance(_routeDistanceM),
                                    style: const TextStyle(color: AppColors.primaryGreen, fontWeight: FontWeight.w900, fontSize: 13),
                                  ),
                                  if (_isStreetRoute) ...[
                                    const SizedBox(width: 4),
                                    const Text('🛣️ Road', style: TextStyle(color: AppColors.primaryCyan, fontSize: 10, fontWeight: FontWeight.bold)),
                                  ],
                                ],
                              ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _nameController,
                    style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600),
                    decoration: InputDecoration(
                      labelText: 'Checkpoint / Destination Name',
                      labelStyle: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                      filled: true,
                      fillColor: AppColors.surfaceElevated,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                      prefixIcon: const Icon(Icons.flag_outlined, color: AppColors.accentAmber, size: 18),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Floating Recenter Buttons
          Positioned(
            right: 16,
            bottom: 100,
            child: Column(
              children: [
                FloatingActionButton.small(
                  heroTag: 'center_target',
                  backgroundColor: AppColors.surface,
                  elevation: 3,
                  child: const Icon(Icons.flag, color: AppColors.accentAmber),
                  onPressed: () {
                    _mapController?.animateCamera(CameraUpdate.newLatLng(_targetLocation));
                  },
                ),
                const SizedBox(height: 8),
                FloatingActionButton.small(
                  heroTag: 'center_me',
                  backgroundColor: AppColors.surface,
                  elevation: 3,
                  child: const Icon(Icons.my_location, color: AppColors.primaryGreen),
                  onPressed: () {
                    _mapController?.animateCamera(CameraUpdate.newLatLng(widget.initialUserLocation));
                  },
                ),
              ],
            ),
          ),

          // Bottom Confirmation Bar
          Positioned(
            left: 16,
            right: 16,
            bottom: 20,
            child: Container(
              decoration: BoxDecoration(
                gradient: AppColors.greenGradient,
                borderRadius: BorderRadius.circular(14),
                boxShadow: AppColors.greenGlowShadow,
              ),
              child: ElevatedButton.icon(
                onPressed: _confirmSelection,
                icon: const Icon(Icons.check_circle_outline, size: 22, color: Colors.black),
                label: Text(
                  _isLoadingRoute
                      ? 'CALCULATING ROAD PATH...'
                      : 'CONFIRM DESTINATION (${GeoUtils.formatDistance(_routeDistanceM)}${_isStreetRoute ? " ROAD" : ""})',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: 0.5, color: Colors.black),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
