import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart' as latlong;

import 'media_channel.dart';

/// Landscape-only car stereo launcher.
///
/// IMPORTANT:
/// - Do NOT request/steal audio focus on Android.
/// - Background Bluetooth playback (Spotify/YouTube Music) must remain uninterrupted.
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

        textTheme: const TextTheme(
          headlineLarge: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.2,
          ),
          headlineMedium: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w800,
          ),
          headlineSmall: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
          titleLarge: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
          bodyLarge: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      home: const CarLauncherPage(),
    );
  }
}

/// Keeps orientation enforcement at the Flutter layer in addition to native settings.
/// This is defensive: the native Android activity will also force landscape.
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

  // Default center somewhere stable; will be overwritten by GPS.
  latlong.LatLng _mapCenter = const latlong.LatLng(37.4219999, -122.0840575);

  bool _locationReady = false;

  @override
  void initState() {
    super.initState();

    // Force orientation (best-effort; native enforces too).
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    // Start updating the clock every second.
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() {
        _now = DateTime.now();
      });
    });

    // Start GPS location updates for speed & map.
    _startLocation();
  }

  Future<void> _startLocation() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.deniedForever) {
        // Location disabled permanently.
        return;
      }

      // Use high accuracy for car driving.
      const LocationSettings settings = LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 1, // meters
        timeLimit: null,
      );

      _posSub = Geolocator.getPositionStream(locationSettings: settings)
          .listen((pos) {
        final kmh = (pos.speed.isFinite && pos.speed >= 0)
            ? pos.speed * 3.6
            : 0.0;

        setState(() {
          _speedKmh = kmh;
          _mapCenter = latlong.LatLng(pos.latitude, pos.longitude);
          _locationReady = true;
        });
      }, onError: (_) {
        // Keep UI alive even if GPS fails.
      });
    } catch (_) {
      // Keep UI alive.
    }
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
            // Left: clock, speedometer, media.
            Flexible(
              flex: 4, // 40%
              child: Container(
                color: const Color(0xFF070A0F),
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                child: Column(
                  children: [
                    _ClockBlock(
                      timeText: _timeFmt.format(_now),
                      dateText: _dateFmt.format(_now),
                    ),
                    const SizedBox(height: 14),
                    Expanded(
                      child: _Speedometer(speedKmh: _speedKmh),
                    ),
                    const SizedBox(height: 14),
                    _MediaCard(
                      onPrevious: MediaChannel.previous,
                      onToggle: MediaChannel.playPauseToggle,
                      onNext: MediaChannel.next,
                    ),
                    const SizedBox(height: 6),
                  ],
                ),
              ),
            ),

            // Right: continuous OSM map.
            Flexible(
              flex: 6, // 60%
              child: Container(
                color: const Color(0xFF05070C),
                child: ClipRRect(
                  borderRadius: const BorderRadius.only(
                    topRight: Radius.circular(12),
                    bottomRight: Radius.circular(12),
                  ),
                  child: _CarMap(
                    center: _mapCenter,
                    locationReady: _locationReady,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ClockBlock extends StatelessWidget {
  final String timeText;
  final String dateText;

  const _ClockBlock({required this.timeText, required this.dateText});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          timeText,
          style: const TextStyle(
            fontSize: 46,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.0,
            color: Color(0xFFEFF6FF),
            shadows: [
              Shadow(
                blurRadius: 8,
                color: Color(0x3304B3FF),
                offset: Offset(0, 0),
              )
            ],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          dateText,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Color(0xFF90A4AE),
          ),
        ),
      ],
    );
  }
}

class _Speedometer extends StatelessWidget {
  final double speedKmh;

  const _Speedometer({required this.speedKmh});

  @override
  Widget build(BuildContext context) {
    final display = speedKmh.isFinite ? speedKmh : 0.0;
    final intSpeed = display.round();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0B0F17),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x1A4CC3FF)),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'SPEED',
              style: TextStyle(
                color: Color(0xFF7AA6B9),
                fontWeight: FontWeight.w800,
                letterSpacing: 2.0,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '$intSpeed',
              style: const TextStyle(
                fontSize: 74,
                fontWeight: FontWeight.w900,
                color: Color(0xFFEFF6FF),
                letterSpacing: 1.0,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'KM/H',
              style: TextStyle(
                color: Color(0xFF90A4AE),
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MediaCard extends StatelessWidget {
  // Helper to create an alpha-blended color without using deprecated Color.alpha/red/green/blue.
  // (Flutter's Color component getters are deprecated in this SDK.)
  Color _withAlpha35(Color c) {
    // c is expected to be opaque; derive the RGB from its ARGB integer.
    final int rgb = c.value & 0x00FFFFFF;
    return Color((int) (0.35 * 255.0).round() << 24 | rgb);
  }

  final Future<void> Function() onPrevious;
  final Future<void> Function() onToggle;
  final Future<void> Function() onNext;

  const _MediaCard({
    required this.onPrevious,
    required this.onToggle,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    const Color primary = Color(0xFF4CC3FF);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0B0F17),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x1A4CC3FF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'MEDIA',
            style: TextStyle(
              color: Color(0xFF7AA6B9),
              fontWeight: FontWeight.w800,
              letterSpacing: 2.0,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _MediaButton(
                  icon: Icons.skip_previous_rounded,
                  label: 'Prev',
                  color: Colors.transparent,
                  borderColor: _withAlpha35(primary),
                  onPressed: onPrevious,


                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _MediaButton(
                  icon: Icons.play_arrow_rounded,
                  label: 'Play/Pause',
                  color: primary,
                  borderColor: primary,
                  onPressed: onToggle,
                  iconColor: Colors.black,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _MediaButton(
                  icon: Icons.skip_next_rounded,
                  label: 'Next',
                  color: Colors.transparent,
                  borderColor: _withAlpha35(primary),
                  onPressed: onNext,


                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MediaButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final Color borderColor;
  final Color? iconColor;
  final Future<void> Function() onPressed;

  const _MediaButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.borderColor,
    required this.onPressed,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onPressed,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: borderColor, width: 1.2),
          ),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 28,
                color: iconColor ?? const Color(0xFFEFF6FF),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: iconColor ?? const Color(0xFFEFF6FF),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }
}

class _CarMap extends StatefulWidget {
  final latlong.LatLng center;
  final bool locationReady;

  const _CarMap({required this.center, required this.locationReady});

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

  @override
  void didUpdateWidget(covariant _CarMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.locationReady) return;

    // Keep the map centered on the latest GPS location.
    _mapController.move(widget.center, 16.5);
  }

  @override
  Widget build(BuildContext context) {
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: widget.center,
        initialZoom: 16.5,
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
        ),
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.carapp.launcher',
        ),
        if (widget.locationReady)
          MarkerLayer(
            markers: [
              Marker(
                point: widget.center,
                width: 42,
                height: 42,
                child: const Icon(
                  Icons.navigation,
                  color: Color(0xFF4CC3FF),
                  size: 42,
                ),
              ),
            ],
          ),
      ],
    );
  }
}

