import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart' as latlong;

import 'media_channel.dart';

/// Premium Car Stereo Launcher with animated UI.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Car Stereo Launcher',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF070A0F),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF4CC3FF),
          secondary: Color(0xFF9B8CFF),
        ),
      ),
      home: const CarLauncherPage(),
    );
  }
}

/// Main page with animated premium design.
class CarLauncherPage extends StatefulWidget {
  const CarLauncherPage({super.key});

  @override
  State<CarLauncherPage> createState() => _CarLauncherPageState();
}

class _CarLauncherPageState extends State<CarLauncherPage> {
  Timer? _clockTimer;
  final DateFormat _timeFmt = DateFormat('hh:mm a');
  final DateFormat _dateFmt = DateFormat('EEE, MMM d');
  DateTime _now = DateTime.now();

  double _speedKmh = 0.0;
  StreamSubscription<Position>? _posSub;

  latlong.LatLng _mapCenter = const latlong.LatLng(37.4219999, -122.0840575);
  bool _locationReady = false;
  latlong.LatLng? _destination;
  List<latlong.LatLng> _routePoints = [];

  // Global key to access map state
  final GlobalKey<_CarMapState> _mapKey = GlobalKey<_CarMapState>();

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _now = DateTime.now());
    });
    _startLocation();
  }

  Future<void> _startLocation() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) return;

      _posSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
          distanceFilter: 1,
        ),
      ).listen((pos) {
        final kmh = (pos.speed.isFinite && pos.speed >= 0) ? pos.speed * 3.6 : 0.0;
        setState(() {
          _speedKmh = kmh;
          _mapCenter = latlong.LatLng(pos.latitude, pos.longitude);
          _locationReady = true;
        });
      }, onError: (_) {});
    } catch (_) {}
  }

  /// Get current location on demand and center map
  Future<void> _centerOnCurrentLocation() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      final newCenter = latlong.LatLng(position.latitude, position.longitude);
      setState(() {
        _mapCenter = newCenter;
        _locationReady = true;
      });
      // Center the map using the global key
      _mapKey.currentState?.centerOnLocation();
    } catch (_) {}
  }

  void _setDestination(latlong.LatLng point) async {
    setState(() => _destination = point);
    if (_locationReady) {
      await _fetchRoute(_mapCenter, point);
    }
  }

  Future<void> _fetchRoute(latlong.LatLng start, latlong.LatLng end) async {
    try {
      final url = 'https://router.project-osrm.org/route/v1/driving/${start.longitude},${start.latitude};${end.longitude},${end.latitude}?geometries=geojson';
      final response = await http.get(Uri.parse(url));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['code'] == 'Ok' && data['routes'].isNotEmpty) {
          final coords = data['routes'][0]['geometry']['coordinates'] as List;
          setState(() {
            _routePoints = coords.map((c) => latlong.LatLng(c[1].toDouble(), c[0].toDouble())).toList();
          });
        }
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _posSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            // Left Column - Premium widgets
            Flexible(
              flex: 4,
              child: Container(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF0A0E17), Color(0xFF0F1722)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
                padding: const EdgeInsets.all(16),
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      _PremiumClockBlock(timeText: _timeFmt.format(_now), dateText: _dateFmt.format(_now)),
                      const SizedBox(height: 16),
                      _PremiumSpeedometer(speedKmh: _speedKmh),
                      const SizedBox(height: 16),
                      _PremiumMediaCard(
                        onPrevious: MediaChannel.previous,
                        onToggle: MediaChannel.playPauseToggle,
                        onNext: MediaChannel.next,
                      ),
                      const SizedBox(height: 16),
                      // Location status and center button
                      _LocationCard(
                        isReady: _locationReady,
                        center: _mapCenter,
                        onCenterPressed: _centerOnCurrentLocation,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // Right Column - Map
            Flexible(
              flex: 6,
              child: Container(
                color: const Color(0xFF05070C),
                child: Stack(
                  children: [
                    ClipRRect(
                      borderRadius: const BorderRadius.only(
                        topRight: Radius.circular(16),
                        bottomRight: Radius.circular(16),
                      ),
                      child: _CarMap(
                        key: _mapKey,
                        center: _mapCenter,
                        locationReady: _locationReady,
                        destination: _destination,
                        routePoints: _routePoints,
                        onMapTap: _setDestination,
                      ),
                    ),
                    Positioned(
                      right: 16,
                      bottom: 16,
                      child: _MapControls(
                        onZoomIn: () => _mapKey.currentState?.zoomIn(),
                        onZoomOut: () => _mapKey.currentState?.zoomOut(),
                        onMyLocation: _centerOnCurrentLocation,
                      ),
                    ),
                    Positioned(
                      top: 16,
                      left: 16,
                      child: _DestinationBanner(destination: _destination, isLocationReady: _locationReady),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Location card with center button.
class _LocationCard extends StatelessWidget {
  final bool isReady;
  final latlong.LatLng center;
  final VoidCallback onCenterPressed;

  const _LocationCard({required this.isReady, required this.center, required this.onCenterPressed});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0B0F17),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF4CC3FF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isReady ? Icons.gps_fixed : Icons.gps_off,
                color: isReady ? const Color(0xFF4CC3FF) : const Color(0xFFFF5252),
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                isReady ? 'GPS ACTIVE' : 'NO LOCATION',
                style: TextStyle(
                  color: isReady ? const Color(0xFF4CC3FF) : const Color(0xFFFF5252),
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.my_location, size: 18, color: Color(0xFF4CC3FF)),
                onPressed: onCenterPressed,
                tooltip: 'Center on my location',
              ),
            ],
          ),
          if (isReady) ...[
            const SizedBox(height: 6),
            Text(
              'Lat: ${center.latitude.toStringAsFixed(4)}',
              style: const TextStyle(color: Color(0xFF90A4AE), fontSize: 10),
            ),
            Text(
              'Lng: ${center.longitude.toStringAsFixed(4)}',
              style: const TextStyle(color: Color(0xFF90A4AE), fontSize: 10),
            ),
          ] else
            const Text(
              'Tap GPS button to get location',
              style: TextStyle(color: Color(0xFF7AA6B9), fontSize: 10),
            ),
        ],
      ),
    );
  }
}

/// Premium clock with gradient.
class _PremiumClockBlock extends StatelessWidget {
  final String timeText;
  final String dateText;
  
  const _PremiumClockBlock({required this.timeText, required this.dateText});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            colors: [Color(0xFF4CC3FF), Color(0xFF9B8CFF)],
            tileMode: TileMode.clamp,
          ).createShader(bounds),
          child: Text(
            timeText,
            style: const TextStyle(
              fontSize: 42,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.5,
              color: Colors.white,
              shadows: [Shadow(blurRadius: 10, color: Color(0x664CC3FF))],
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(dateText, style: const TextStyle(fontSize: 16, color: Color(0xFF7AA6B9), fontWeight: FontWeight.w500)),
      ],
    );
  }
}

/// Premium speedometer.
class _PremiumSpeedometer extends StatelessWidget {
  final double speedKmh;
  
  const _PremiumSpeedometer({required this.speedKmh});

  @override
  Widget build(BuildContext context) {
    final intSpeed = speedKmh.isFinite ? speedKmh.round() : 0;
    
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const RadialGradient(
          colors: [Color(0xFF0B0F17), Color(0xFF05070C)],
          center: Alignment.center,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF4CC3FF), width: 2),
        boxShadow: const [
          BoxShadow(color: Color(0x334CC3FF), blurRadius: 20, spreadRadius: 2),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('SPEED', style: TextStyle(color: Color(0xFF7AA6B9), fontWeight: FontWeight.w800, letterSpacing: 3)),
          const SizedBox(height: 8),
          Text('$intSpeed', style: const TextStyle(fontSize: 56, fontWeight: FontWeight.w900, color: Color(0xFFEFF6FF), letterSpacing: 1)),
          const Text('KM/H', style: TextStyle(color: Color(0xFF90A4AE), fontSize: 14, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

/// Premium media card.
class _PremiumMediaCard extends StatelessWidget {
  final Future<void> Function() onPrevious;
  final Future<void> Function() onToggle;
  final Future<void> Function() onNext;

  const _PremiumMediaCard({required this.onPrevious, required this.onToggle, required this.onNext});

  @override
  Widget build(BuildContext context) {
    const Color primary = Color(0xFF4CC3FF);
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0B0F17),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: primary),
        boxShadow: const [BoxShadow(color: Color(0x334CC3FF), blurRadius: 15)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('MEDIA CONTROLS', style: TextStyle(color: Color(0xFF7AA6B9), fontWeight: FontWeight.w800, letterSpacing: 2)),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _MediaBtn(icon: Icons.skip_previous_rounded, label: 'PREV', color: primary, onPressed: onPrevious),
              _MediaBtn(icon: Icons.play_arrow_rounded, label: 'PLAY', color: primary, isPrimary: true, onPressed: onToggle),
              _MediaBtn(icon: Icons.skip_next_rounded, label: 'NEXT', color: primary, onPressed: onNext),
            ],
          ),
        ],
      ),
    );
  }
}

class _MediaBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool isPrimary;
  final Future<void> Function() onPressed;

  const _MediaBtn({required this.icon, required this.label, required this.color, required this.onPressed, this.isPrimary = false});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onPressed,
        child: Container(
          width: 70,
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          decoration: BoxDecoration(
            gradient: isPrimary ? RadialGradient(colors: [color, color.withValues(alpha: 0.3)]) : null,
            color: isPrimary ? null : const Color(0xFF070A0F),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color, width: isPrimary ? 2 : 1),
          ),
          child: Column(
            children: [
              Icon(icon, size: 28, color: Colors.white),
              const SizedBox(height: 6),
              Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white, letterSpacing: 1)),
            ],
          ),
        ),
      ),
    );
  }
}

class _MapControls extends StatelessWidget {
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onMyLocation;

  const _MapControls({required this.onZoomIn, required this.onZoomOut, required this.onMyLocation});

  @override
  Widget build(BuildContext context) {
    const Color accent = Color(0xFF4CC3FF);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _CircularBtn(icon: Icons.add, onPressed: onZoomIn, color: accent),
        const SizedBox(height: 8),
        _CircularBtn(icon: Icons.remove, onPressed: onZoomOut, color: accent),
        const SizedBox(height: 8),
        _CircularBtn(icon: Icons.my_location, onPressed: onMyLocation, color: accent),
      ],
    );
  }
}

class _CircularBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final Color color;

  const _CircularBtn({required this.icon, required this.onPressed, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFF0B0F17).withValues(alpha: 0.85),
        border: Border.all(color: color),
        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.3), blurRadius: 10)],
      ),
      child: IconButton(icon: Icon(icon, color: color, size: 22), onPressed: onPressed),
    );
  }
}

class _DestinationBanner extends StatelessWidget {
  final latlong.LatLng? destination;
  final bool isLocationReady;

  const _DestinationBanner({required this.destination, required this.isLocationReady});

  @override
  Widget build(BuildContext context) {
    final Color bannerColor = !isLocationReady || destination != null
        ? const Color(0xFFFF5252)
        : const Color(0xFF4CC3FF);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: (!isLocationReady || destination != null)
            ? const Color(0xFFFF5252).withValues(alpha: 0.9)
            : const Color(0xFF4CC3FF).withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: bannerColor.withValues(alpha: 0.5), blurRadius: 12)],
      ),
      child: Row(
        children: [
          Icon(
            !isLocationReady
                ? Icons.warning
                : destination != null ? Icons.location_on : Icons.touch_app,
            color: Colors.white,
            size: 18,
          ),
          const SizedBox(width: 8),
          Text(
            !isLocationReady
                ? 'ALLOW LOCATION PERMISSION'
                : destination != null
                    ? 'DEST: ${destination!.latitude.toStringAsFixed(4)}, ${destination!.longitude.toStringAsFixed(4)}'
                    : 'TAP MAP TO SELECT DESTINATION',
            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

/// Interactive map.
class _CarMap extends StatefulWidget {
  final latlong.LatLng center;
  final bool locationReady;
  final latlong.LatLng? destination;
  final List<latlong.LatLng> routePoints;
  final Function(latlong.LatLng)? onMapTap;

  const _CarMap({super.key, required this.center, required this.locationReady, this.destination, required this.routePoints, this.onMapTap});

  @override
  State<_CarMap> createState() => _CarMapState();
}

class _CarMapState extends State<_CarMap> {
  late final MapController _mapController;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
  }

  void zoomIn() => _mapController.move(_mapController.camera.center, _mapController.camera.zoom + 1);
  void zoomOut() => _mapController.move(_mapController.camera.center, _mapController.camera.zoom - 1);
  void centerOnLocation() {
    if (widget.locationReady && mounted) {
      _mapController.move(widget.center, 16.5);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: widget.center,
        initialZoom: 16.5,
        interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
        onTap: (tapPosition, point) => widget.onMapTap?.call(point),
      ),
      children: [
        TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.carapp.launcher'),
        if (widget.routePoints.isNotEmpty)
          PolylineLayer(polylines: [
            Polyline(points: widget.routePoints, color: const Color(0xFF4CC3FF), strokeWidth: 5),
          ]),
        if (widget.locationReady)
          MarkerLayer(markers: [
            Marker(point: widget.center, width: 44, height: 44, child: const Icon(Icons.navigation, color: Color(0xFF4CC3FF), size: 44)),
            if (widget.destination != null)
              Marker(point: widget.destination!, width: 38, height: 38, child: const Icon(Icons.location_on, color: Color(0xFFFF5252), size: 38)),
          ]),
      ],
    );
  }
}