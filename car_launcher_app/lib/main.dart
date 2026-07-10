import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

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
        scaffoldBackgroundColor: AppColors.bg,
        colorScheme: const ColorScheme.dark(
          primary: AppColors.accentBlue,
          secondary: AppColors.accentPurple,
        ),
      ),
      home: const CarLauncherPage(),
    );
  }
}

/// ---------------------------------------------------------------------
/// Design tokens — single source of truth for the dashboard's palette.
/// ---------------------------------------------------------------------
class AppColors {
  AppColors._();

  static const Color bg = Color(0xFF05070C);
  static const Color bgGradientTop = Color(0xFF0A0E17);
  static const Color bgGradientBottom = Color(0xFF0E141F);

  static const Color card = Color(0xFF0C1119);
  static const Color cardBorder = Color(0x1FFFFFFF);
  static const Color cardBorderStrong = Color(0x334CC3FF);

  static const Color accentBlue = Color(0xFF4CC3FF);
  static const Color accentPurple = Color(0xFF9B8CFF);
  static const Color accentAmber = Color(0xFFFFB74D);
  static const Color accentGreen = Color(0xFF4CD787);
  static const Color accentRed = Color(0xFFFF5C5C);
  static const Color accentYellow = Color(0xFFE8D24C);
  static const Color accentOrange = Color(0xFFFF9950);

  static const Color textPrimary = Color(0xFFF3F8FF);
  static const Color textSecondary = Color(0xFF8FA6BB);
  static const Color textMuted = Color(0xFF54697D);

  static const LinearGradient brandGradient = LinearGradient(
    colors: [accentBlue, accentPurple],
  );
}

/// ---------------------------------------------------------------------
/// Static placeholder weather/AQI data.
/// Swap this out for a live provider (e.g. OpenWeather) later — the UI
/// below already reads exclusively from this model, so wiring in live
/// data only means replacing these constants with fetched values.
/// ---------------------------------------------------------------------
class WeatherData {
  final double tempC;
  final String condition;
  final IconData conditionIcon;
  final double highC;
  final double lowC;
  final int humidityPct;
  final double windKmh;
  final int aqi;

  const WeatherData({
    required this.tempC,
    required this.condition,
    required this.conditionIcon,
    required this.highC,
    required this.lowC,
    required this.humidityPct,
    required this.windKmh,
    required this.aqi,
  });

  static const WeatherData placeholder = WeatherData(
    tempC: 24,
    condition: 'Partly Cloudy',
    conditionIcon: Icons.wb_cloudy_rounded,
    highC: 28,
    lowC: 18,
    humidityPct: 58,
    windKmh: 12,
    aqi: 42,
  );

  /// EPA-style AQI banding.
  String get aqiLabel {
    if (aqi <= 50) return 'Good';
    if (aqi <= 100) return 'Moderate';
    if (aqi <= 150) return 'Unhealthy (SG)';
    if (aqi <= 200) return 'Unhealthy';
    if (aqi <= 300) return 'Very Unhealthy';
    return 'Hazardous';
  }

  Color get aqiColor {
    if (aqi <= 50) return AppColors.accentGreen;
    if (aqi <= 100) return AppColors.accentYellow;
    if (aqi <= 150) return AppColors.accentOrange;
    if (aqi <= 200) return AppColors.accentRed;
    return const Color(0xFFB388FF);
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

  // Static for now — replace with a live weather/AQI fetch later.
  final WeatherData _weather = WeatherData.placeholder;

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
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppColors.bgGradientTop, AppColors.bgGradientBottom],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _BrandStatusBar(),
                      const SizedBox(height: 14),
                      _PremiumClockBlock(timeText: _timeFmt.format(_now), dateText: _dateFmt.format(_now)),
                      const SizedBox(height: 16),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: _PremiumSpeedometer(speedKmh: _speedKmh)),
                          const SizedBox(width: 12),
                          Expanded(child: _WeatherCard(weather: _weather)),
                        ],
                      ),
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
                        topRight: Radius.circular(20),
                        bottomRight: Radius.circular(20),
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

/// Reusable dashboard card shell — keeps borders, radii, and shadows
/// consistent across every widget on the left rail.
class _DashboardCard extends StatelessWidget {
  final Widget child;
  final Color accent;
  final EdgeInsetsGeometry padding;
  final Gradient? backgroundGradient;

  const _DashboardCard({
    required this.child,
    this.accent = AppColors.accentBlue,
    this.padding = const EdgeInsets.all(16),
    this.backgroundGradient,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: backgroundGradient == null ? AppColors.card : null,
        gradient: backgroundGradient,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
        boxShadow: [
          BoxShadow(color: accent.withValues(alpha: 0.12), blurRadius: 18, spreadRadius: -2),
          const BoxShadow(color: Colors.black45, blurRadius: 10, offset: Offset(0, 4)),
        ],
      ),
      child: child,
    );
  }
}

/// Small header row: brand mark + connectivity glyphs. Purely cosmetic,
/// gives the dashboard a "system" feel instead of a stack of widgets.
class _BrandStatusBar extends StatelessWidget {
  const _BrandStatusBar();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            gradient: AppColors.brandGradient,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.directions_car_filled_rounded, size: 16, color: Colors.white),
        ),
        const SizedBox(width: 8),
        const Text(
          'DRIVE OS',
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 2.4,
          ),
        ),
        const Spacer(),
        const Icon(Icons.bluetooth_rounded, size: 16, color: AppColors.textSecondary),
        const SizedBox(width: 10),
        const Icon(Icons.signal_cellular_alt_rounded, size: 16, color: AppColors.textSecondary),
        const SizedBox(width: 10),
        const Icon(Icons.battery_full_rounded, size: 16, color: AppColors.textSecondary),
      ],
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
    final Color statusColor = isReady ? AppColors.accentGreen : AppColors.accentRed;
    return _DashboardCard(
      accent: statusColor,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(
                  isReady ? Icons.gps_fixed_rounded : Icons.gps_off_rounded,
                  color: statusColor,
                  size: 16,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                isReady ? 'GPS ACTIVE' : 'NO LOCATION',
                style: TextStyle(
                  color: statusColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                ),
              ),
              const Spacer(),
              _IconGhostButton(icon: Icons.my_location_rounded, onPressed: onCenterPressed, tooltip: 'Center on my location'),
            ],
          ),
          if (isReady) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _StatChip(label: 'LAT', value: center.latitude.toStringAsFixed(4)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _StatChip(label: 'LNG', value: center.longitude.toStringAsFixed(4)),
                ),
              ],
            ),
          ] else
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                'Tap the GPS button to get your location',
                style: TextStyle(color: AppColors.textMuted, fontSize: 11),
              ),
            ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  const _StatChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 1)),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _IconGhostButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final String? tooltip;
  const _IconGhostButton({required this.icon, required this.onPressed, this.tooltip});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.04),
      shape: const CircleBorder(),
      child: IconButton(
        icon: Icon(icon, size: 16, color: AppColors.accentBlue),
        onPressed: onPressed,
        tooltip: tooltip,
        splashRadius: 18,
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
          shaderCallback: (bounds) => AppColors.brandGradient.createShader(bounds),
          child: Text(
            timeText,
            style: const TextStyle(
              fontSize: 40,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
              color: Colors.white,
              height: 1,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Container(
              width: 4,
              height: 4,
              decoration: const BoxDecoration(color: AppColors.textSecondary, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(dateText, style: const TextStyle(fontSize: 14, color: AppColors.textSecondary, fontWeight: FontWeight.w500)),
          ],
        ),
      ],
    );
  }
}

/// Premium speedometer — arc gauge with a digital readout in the center.
class _PremiumSpeedometer extends StatelessWidget {
  final double speedKmh;
  static const double maxSpeed = 220;

  const _PremiumSpeedometer({required this.speedKmh});

  @override
  Widget build(BuildContext context) {
    final intSpeed = speedKmh.isFinite ? speedKmh.round() : 0;

    return _DashboardCard(
      padding: const EdgeInsets.all(14),
      backgroundGradient: const RadialGradient(
        colors: [Color(0xFF10161F), Color(0xFF090C12)],
        center: Alignment.center,
        radius: 1.1,
      ),
      child: SizedBox(
        height: 148,
        child: Stack(
          alignment: Alignment.center,
          children: [
            CustomPaint(
              size: const Size.square(140),
              painter: _SpeedGaugePainter(speedKmh: speedKmh, maxSpeed: maxSpeed),
            ),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$intSpeed',
                  style: const TextStyle(
                    fontSize: 40,
                    fontWeight: FontWeight.w900,
                    color: AppColors.textPrimary,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'KM/H',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 2),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SpeedGaugePainter extends CustomPainter {
  final double speedKmh;
  final double maxSpeed;

  _SpeedGaugePainter({required this.speedKmh, required this.maxSpeed});

  static const double _startAngle = math.pi * 0.75; // 135°
  static const double _sweepAngle = math.pi * 1.5; // 270°

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 8;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final trackPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.06)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, _startAngle, _sweepAngle, false, trackPaint);

    final double progress = (speedKmh.isFinite ? speedKmh / maxSpeed : 0.0).clamp(0.0, 1.0).toDouble();
    if (progress > 0) {
      final progressPaint = Paint()
        ..shader = SweepGradient(
          colors: const [AppColors.accentBlue, AppColors.accentPurple],
          startAngle: _startAngle,
          endAngle: _startAngle + _sweepAngle,
          transform: const GradientRotation(0),
        ).createShader(rect)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 9
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(rect, _startAngle, _sweepAngle * progress, false, progressPaint);
    }

    // Tick marks every 10% around the track.
    final tickPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.18)
      ..strokeWidth = 2;
    for (int i = 0; i <= 10; i++) {
      final angle = _startAngle + _sweepAngle * (i / 10);
      final outer = Offset(center.dx + (radius + 6) * math.cos(angle), center.dy + (radius + 6) * math.sin(angle));
      final inner = Offset(center.dx + (radius - 2) * math.cos(angle), center.dy + (radius - 2) * math.sin(angle));
      canvas.drawLine(inner, outer, tickPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _SpeedGaugePainter oldDelegate) =>
      oldDelegate.speedKmh != speedKmh || oldDelegate.maxSpeed != maxSpeed;
}

/// Weather + AQI card. Reads entirely from [WeatherData] — currently a
/// static placeholder, ready to be swapped for a live provider.
class _WeatherCard extends StatelessWidget {
  final WeatherData weather;
  const _WeatherCard({required this.weather});

  @override
  Widget build(BuildContext context) {
    return _DashboardCard(
      accent: AppColors.accentAmber,
      padding: const EdgeInsets.all(14),
      child: SizedBox(
        height: 148,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: AppColors.accentAmber.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(weather.conditionIcon, size: 19, color: AppColors.accentAmber),
                ),
                const Spacer(),
                Text(
                  '${weather.tempC.round()}°',
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 30, fontWeight: FontWeight.w800, height: 1),
                ),
              ],
            ),
            Text(
              weather.condition,
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600),
            ),
            Row(
              children: [
                Icon(Icons.arrow_upward_rounded, size: 12, color: AppColors.textMuted),
                Text('${weather.highC.round()}°', style: const TextStyle(color: AppColors.textMuted, fontSize: 11, fontWeight: FontWeight.w600)),
                const SizedBox(width: 8),
                Icon(Icons.arrow_downward_rounded, size: 12, color: AppColors.textMuted),
                Text('${weather.lowC.round()}°', style: const TextStyle(color: AppColors.textMuted, fontSize: 11, fontWeight: FontWeight.w600)),
              ],
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: weather.aqiColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: weather.aqiColor.withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  Container(width: 6, height: 6, decoration: BoxDecoration(color: weather.aqiColor, shape: BoxShape.circle)),
                  const SizedBox(width: 6),
                  Text('AQI ${weather.aqi}', style: TextStyle(color: weather.aqiColor, fontSize: 10.5, fontWeight: FontWeight.w800)),
                  const Spacer(),
                  Text(weather.aqiLabel, style: TextStyle(color: weather.aqiColor, fontSize: 10, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ],
        ),
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
    return _DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.graphic_eq_rounded, size: 14, color: AppColors.textSecondary),
              const SizedBox(width: 6),
              const Text('MEDIA CONTROLS', style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w800, letterSpacing: 1.6, fontSize: 11)),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _MediaBtn(icon: Icons.skip_previous_rounded, label: 'PREV', onPressed: onPrevious),
              _MediaBtn(icon: Icons.play_arrow_rounded, label: 'PLAY', isPrimary: true, onPressed: onToggle),
              _MediaBtn(icon: Icons.skip_next_rounded, label: 'NEXT', onPressed: onNext),
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
  final bool isPrimary;
  final Future<void> Function() onPressed;

  const _MediaBtn({required this.icon, required this.label, required this.onPressed, this.isPrimary = false});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onPressed,
        child: Container(
          width: 74,
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          decoration: BoxDecoration(
            gradient: isPrimary ? AppColors.brandGradient : null,
            color: isPrimary ? null : Colors.white.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(16),
            border: isPrimary ? null : Border.all(color: AppColors.cardBorder),
            boxShadow: isPrimary
                ? [BoxShadow(color: AppColors.accentBlue.withValues(alpha: 0.35), blurRadius: 14, offset: const Offset(0, 4))]
                : null,
          ),
          child: Column(
            children: [
              Icon(icon, size: 26, color: Colors.white),
              const SizedBox(height: 6),
              Text(label, style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: Colors.white, letterSpacing: 1)),
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
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _CircularBtn(icon: Icons.add_rounded, onPressed: onZoomIn),
        const SizedBox(height: 8),
        _CircularBtn(icon: Icons.remove_rounded, onPressed: onZoomOut),
        const SizedBox(height: 8),
        _CircularBtn(icon: Icons.my_location_rounded, onPressed: onMyLocation),
      ],
    );
  }
}

class _CircularBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;

  const _CircularBtn({required this.icon, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFF0B0F17).withValues(alpha: 0.9),
        border: Border.all(color: AppColors.accentBlue.withValues(alpha: 0.5)),
        boxShadow: [BoxShadow(color: AppColors.accentBlue.withValues(alpha: 0.25), blurRadius: 10)],
      ),
      child: IconButton(icon: Icon(icon, color: AppColors.accentBlue, size: 20), onPressed: onPressed, splashRadius: 20),
    );
  }
}

class _DestinationBanner extends StatelessWidget {
  final latlong.LatLng? destination;
  final bool isLocationReady;

  const _DestinationBanner({required this.destination, required this.isLocationReady});

  @override
  Widget build(BuildContext context) {
    final bool alert = !isLocationReady;
    final bool hasDest = destination != null;
    final Color bannerColor = alert ? AppColors.accentRed : (hasDest ? AppColors.accentBlue : AppColors.textSecondary);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xFF0B0F17).withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: bannerColor.withValues(alpha: 0.55)),
        boxShadow: [BoxShadow(color: bannerColor.withValues(alpha: 0.25), blurRadius: 12)],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            alert ? Icons.warning_rounded : (hasDest ? Icons.location_on_rounded : Icons.touch_app_rounded),
            color: bannerColor,
            size: 16,
          ),
          const SizedBox(width: 8),
          Text(
            alert
                ? 'ALLOW LOCATION PERMISSION'
                : hasDest
                    ? 'DEST: ${destination!.latitude.toStringAsFixed(4)}, ${destination!.longitude.toStringAsFixed(4)}'
                    : 'TAP MAP TO SELECT DESTINATION',
            style: TextStyle(color: bannerColor, fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: 0.3),
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
            Polyline(points: widget.routePoints, color: AppColors.accentBlue, strokeWidth: 5),
          ]),
        if (widget.locationReady)
          MarkerLayer(markers: [
            Marker(point: widget.center, width: 44, height: 44, child: const Icon(Icons.navigation, color: AppColors.accentBlue, size: 44)),
            if (widget.destination != null)
              Marker(point: widget.destination!, width: 38, height: 38, child: const Icon(Icons.location_on, color: AppColors.accentRed, size: 38)),
          ]),
      ],
    );
  }
}