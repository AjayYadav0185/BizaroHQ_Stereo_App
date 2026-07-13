import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart' as latlong;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';

import 'media_channel.dart';
import 'tile_cache.dart';

/// Premium BizaroHQ Stereo with animated UI.
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
      title: 'BizaroHQ Stereo',
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
  bool _autoCenterMap = true;
  latlong.LatLng? _destination;
  List<latlong.LatLng> _routePoints = [];

  // Connectivity
  bool _isOnline = true;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  // Bluetooth media device connection state
  bool _btConnected = false;
  String _nowPlayingTitle = '';
  String _nowPlayingArtist = '';

  // Current compass heading (degrees, 0 = north) used to rotate the map.
  double _heading = 0.0;

  // Global key to access map state
  final GlobalKey<_CarMapState> _mapKey = GlobalKey<_CarMapState>();

  // Media polling timer (replaces doWhile for reliable scheduling)
  Timer? _mediaPollTimer;

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
    _startConnectivityMonitoring();
    _startBluetoothMonitoring();
    _startLocation();
  }

  /// Poll Bluetooth A2DP connection + now-playing metadata so the media card
  /// reflects the connected device and current track in real time.
  /// Uses a periodic Timer instead of doWhile for more reliable scheduling.
  Future<void> _startBluetoothMonitoring() async {
    await MediaChannel.requestBluetoothPermission();
    // Perform initial refresh
    await _refreshBluetooth();
    await _refreshNowPlaying();
    // Schedule periodic polling (every 2 seconds for responsive UI)
    _mediaPollTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (!mounted) {
        _mediaPollTimer?.cancel();
        return;
      }
      await _refreshBluetooth();
      await _refreshNowPlaying();
    });
  }

  Future<void> _refreshNowPlaying() async {
    final track = await MediaChannel.getNowPlaying();
    if (mounted &&
        (track.title != _nowPlayingTitle || track.artist != _nowPlayingArtist)) {
      setState(() {
        _nowPlayingTitle = track.title;
        _nowPlayingArtist = track.artist;
      });
    }
  }

  Future<void> _refreshBluetooth() async {
    final connected = await MediaChannel.isBluetoothConnected();
    if (mounted && connected != _btConnected) {
      setState(() => _btConnected = connected);
    }
  }

  Future<void> _startConnectivityMonitoring() async {
    // Check initial state
    final results = await Connectivity().checkConnectivity();
    setState(() => _isOnline = !results.contains(ConnectivityResult.none));

    // Listen for changes
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      setState(() => _isOnline = !results.contains(ConnectivityResult.none));
    });
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
        final h = (pos.heading.isFinite && pos.heading >= 0) ? pos.heading : _heading;
        setState(() {
          _speedKmh = kmh;
          _mapCenter = latlong.LatLng(pos.latitude, pos.longitude);
          _locationReady = true;
          _heading = h;
        });
        // Keep the map oriented to the direction of travel.
        _mapKey.currentState?.setRotation(h);
        // Auto-center map only if toggle is enabled. Pass the fresh position
        // directly because the child widget's `widget.center` has not been
        // rebuilt with the new value yet within this same frame.
        if (_autoCenterMap && mounted) {
          _mapKey.currentState?.centerOnLocation(_mapCenter);
        }
      }, onError: (_) {});
    } catch (_) {}
  }

  /// Get current location on demand and center map
  Future<void> _centerOnCurrentLocation() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
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
    if (_locationReady && _isOnline) {
      await _fetchRoute(_mapCenter, point);
    } else if (!_isOnline) {
      // Offline: show destination marker but no route line
      setState(() => _routePoints = []);
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

  /// Toggle auto-center behavior
  void _toggleAutoCenter(bool value) {
    setState(() {
      _autoCenterMap = value;
    });
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _posSub?.cancel();
    _connectivitySub?.cancel();
    _mediaPollTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Glassmorphism backdrop with soft glowing blobs
          const Positioned.fill(child: _BackgroundBlobs()),
          SafeArea(
            child: Row(
              children: [
                // Left Column - Premium glass widgets
                Flexible(
                  flex: 4,
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: _GlassContainer(
                                  child: _PremiumClockBlock(timeText: _timeFmt.format(_now), dateText: _dateFmt.format(_now)),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: _GlassContainer(
                                  tint: const Color(0xFF9B8CFF),
                                  child: _PremiumSpeedometer(speedKmh: _speedKmh),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          _RotatingCar3D(),
                          const SizedBox(height: 16),
                          _GlassContainer(
                            tint: const Color(0xFF4CC3FF),
                            child: _PremiumMediaCard(
                              isBluetoothConnected: _btConnected,
                              nowPlayingTitle: _nowPlayingTitle,
                              nowPlayingArtist: _nowPlayingArtist,
                              onPrevious: MediaChannel.previous,
                              onToggle: MediaChannel.playPauseToggle,
                              onNext: MediaChannel.next,
                              onVolumeUp: MediaChannel.volumeUp,
                              onVolumeDown: MediaChannel.volumeDown,
                            ),
                          ),
                          const SizedBox(height: 16),
                          _GlassContainer(
                            tint: const Color(0xFF91E0C0),
                            child: _LocationCard(
                              isReady: _locationReady,
                              center: _mapCenter,
                              autoCenterEnabled: _autoCenterMap,
                              onAutoCenterChanged: _toggleAutoCenter,
                              onCenterPressed: _centerOnCurrentLocation,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                // Right Column - Map
                Flexible(
                  flex: 6,
                  child: Stack(
                    children: [
                      ClipRRect(
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(24),
                          bottomLeft: Radius.circular(24),
                        ),
                        child: _CarMap(
                            key: _mapKey,
                            center: _mapCenter,
                            heading: _heading,
                            locationReady: _locationReady,
                            destination: _destination,
                            routePoints: _routePoints,
                            isOnline: _isOnline,
                            onMapTap: _setDestination,
                          ),
                        ),
                        // Offline badge
                        if (!_isOnline)
                          Positioned(
                            top: 16,
                            right: 16,
                            child: _GlassContainer(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              borderRadius: 20,
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.wifi_off, color: Color(0xFFFF9800), size: 16),
                                  SizedBox(width: 6),
                                  Text(
                                    'OFFLINE',
                                    style: TextStyle(
                                      color: Color(0xFFFF9800),
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 1,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        Positioned(
                          right: 16,
                          bottom: 16,
                          child: _GlassContainer(
                            padding: const EdgeInsets.all(8),
                            borderRadius: 18,
                            child: _MapControls(
                              onZoomIn: () => _mapKey.currentState?.zoomIn(),
                              onZoomOut: () => _mapKey.currentState?.zoomOut(),
                              onMyLocation: _centerOnCurrentLocation,
                            ),
                          ),
                        ),
                        Positioned(
                          top: 16,
                          left: 16,
                          child: _GlassContainer(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            borderRadius: 22,
                            child: _DestinationBanner(
                              destination: _destination,
                              isLocationReady: _locationReady,
                              isOnline: _isOnline,
                              onClear: () => setState(() {
                                _destination = null;
                                _routePoints = [];
                              }),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Reusable glassmorphism container (frosted glass effect).
class _GlassContainer extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double borderRadius;
  final Color tint;

  const _GlassContainer({
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.borderRadius = 20,
    this.tint = const Color(0xFF4CC3FF),
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(color: Colors.white.withValues(alpha: 0.18), width: 1.2),
            boxShadow: [
              BoxShadow(
                color: tint.withValues(alpha: 0.18),
                blurRadius: 26,
                spreadRadius: 1,
              ),
            ],
            gradient: LinearGradient(
              colors: [
                Colors.white.withValues(alpha: 0.12),
                Colors.white.withValues(alpha: 0.02),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Decorative animated-style background blobs for the glassmorphism backdrop.
class _BackgroundBlobs extends StatelessWidget {
  const _BackgroundBlobs();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF070A14), Color(0xFF0B1020)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -60,
            left: -40,
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [Color(0x554CC3FF), Color(0x00000000)],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -80,
            right: -30,
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [Color(0x559B8CFF), Color(0x00000000)],
                ),
              ),
            ),
          ),
          Positioned(
            top: 140,
            right: 70,
            child: Container(
              width: 170,
              height: 170,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [Color(0x3391E0C0), Color(0x00000000)],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Location card with center button and auto-center toggle.
class _LocationCard extends StatelessWidget {
  final bool isReady;
  final latlong.LatLng center;
  final bool autoCenterEnabled;
  final ValueChanged<bool> onAutoCenterChanged;
  final VoidCallback onCenterPressed;

  const _LocationCard({required this.isReady, required this.center, required this.autoCenterEnabled, required this.onAutoCenterChanged, required this.onCenterPressed});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
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
          const SizedBox(height: 12),
          // Auto-center toggle
          Row(
            children: [
              Switch(
                value: autoCenterEnabled,
                onChanged: onAutoCenterChanged,
                activeThumbColor: const Color(0xFF4CC3FF),
                inactiveThumbColor: const Color(0xFF7AA6B9),
                inactiveTrackColor: const Color(0xFF070A0F),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  autoCenterEnabled ? 'Auto-Follow Enabled' : 'Manual Drag Mode',
                  style: TextStyle(
                    color: autoCenterEnabled ? const Color(0xFF4CC3FF) : const Color(0xFF7AA6B9),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Icon(
                autoCenterEnabled ? Icons.autorenew : Icons.pan_tool,
                color: autoCenterEnabled ? const Color(0xFF4CC3FF) : const Color(0xFF7AA6B9),
                size: 16,
              ),
            ],
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

/// Premium 3D rotating car model that continuously rotates and floats.
class _RotatingCar3D extends StatefulWidget {
  const _RotatingCar3D();

  @override
  State<_RotatingCar3D> createState() => _RotatingCar3DState();
}

class _RotatingCar3DState extends State<_RotatingCar3D>
    with SingleTickerProviderStateMixin {
  late final AnimationController _floatController;
  late final Animation<double> _floatAnimation;

  // Embedded base64 data URI of the GLB. Loading it this way (instead of the
  // plugin's loopback HTTP proxy) guarantees the 3D model renders fully
  // offline with zero network dependency.
  String? _modelDataUri;

  @override
  void initState() {
    super.initState();
    _floatController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);
    _floatAnimation = Tween<double>(begin: -8, end: 8).animate(
      CurvedAnimation(parent: _floatController, curve: Curves.easeInOutSine),
    );
    _loadModelOffline();
  }

  /// Read the bundled GLB and embed it as a base64 data URI so the model is
  /// served directly to the `model-viewer` element with no network/proxy call.
  Future<void> _loadModelOffline() async {
    try {
      final ByteData bytes = await rootBundle.load('assets/models/car.glb');
      final String b64 = base64Encode(bytes.buffer.asUint8List());
      if (mounted) {
        setState(() => _modelDataUri = 'data:model/gltf-binary;base64,$b64');
      }
    } catch (_) {
      // If embedding fails, fall back to the standard asset path.
      if (mounted) setState(() => _modelDataUri = 'assets/models/car.glb');
    }
  }

  @override
  void dispose() {
    _floatController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _GlassContainer(
      padding: EdgeInsets.zero,
      borderRadius: 20,
      child: SizedBox(
        height: 180,
        width: double.infinity,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Soft glow behind the model
            Container(
              width: 150,
              height: 150,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [Color(0x3391E0C0), Color(0x00000000)],
                ),
              ),
            ),
            // Floating + continuously rotating model
            AnimatedBuilder(
              animation: _floatAnimation,
              builder: (context, child) {
                return Transform.translate(
                  offset: Offset(0, _floatAnimation.value),
                  child: child,
                );
              },
              child: ClipRRect(
                child: _modelDataUri == null
                    ? const Center(
                        child: CircularProgressIndicator(
                          semanticsLabel: 'Loading 3D Model',
                        ),
                      )
                    : ModelViewer(
                        src: _modelDataUri!,
                        alt: 'Rotating 3D Car Model',
                        ar: false,
                        autoRotate: true,
                        autoRotateDelay: 0,
                        rotationPerSecond: '24deg',
                        cameraControls: false,
                        disableZoom: true,
                        disablePan: true,
                        disableTap: true,
                        exposure: 1.1,
                        environmentImage: 'neutral',
                        shadowIntensity: 0.5,
                        shadowSoftness: 1,
                        backgroundColor: const Color(0x00000000),
                      ),
              ),
            ),
          ],
        ),
      ),
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
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          Text('$intSpeed', style: const TextStyle(fontSize: 56, fontWeight: FontWeight.w900, color: Color(0xFFEFF6FF), letterSpacing: 1)),
          const Text('SPEED - KM/H', style: TextStyle(color: Color(0xFF90A4AE), fontSize: 14, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

/// Scrolling "now playing" marquee that moves text from right to left when it
/// overflows the available width.
class _MarqueeText extends StatefulWidget {
  final String text;
  final TextStyle style;

  const _MarqueeText({
    required this.text,
    required this.style,
  });

  @override
  State<_MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<_MarqueeText>
    with SingleTickerProviderStateMixin {
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _textKey = GlobalKey();
  late final AnimationController _animController;
  double _viewWidth = 0;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..addListener(() {
        if (_scrollController.hasClients) {
          final max = _scrollController.position.maxScrollExtent;
          if (max > 0) {
            _scrollController.jumpTo(_animController.value * max);
          }
        }
      });
    // Measure after first layout, then start if needed.
    WidgetsBinding.instance.addPostFrameCallback((_) => _evaluate());
  }

  void _evaluate() {
    if (!mounted) return;
    final ctx = _textKey.currentContext;
    if (ctx != null) {
      final w = (ctx.findRenderObject() as RenderBox).size.width;
      if (w > _viewWidth && !_animController.isAnimating) {
        _animController.repeat();
      }
    }
  }

  @override
  void didUpdateWidget(covariant _MarqueeText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      _animController.stop();
      _animController.reset();
      WidgetsBinding.instance.addPostFrameCallback((_) => _evaluate());
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 22,
      child: LayoutBuilder(
        builder: (context, constraints) {
          _viewWidth = constraints.maxWidth;
          return SingleChildScrollView(
            controller: _scrollController,
            scrollDirection: Axis.horizontal,
            physics: const NeverScrollableScrollPhysics(),
            child: Container(
              constraints: BoxConstraints(minWidth: _viewWidth),
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  key: _textKey,
                  widget.text,
                  style: widget.style,
                  maxLines: 1,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Premium media card.
class _PremiumMediaCard extends StatelessWidget {
  final bool isBluetoothConnected;
  final String nowPlayingTitle;
  final String nowPlayingArtist;
  final Future<void> Function() onPrevious;
  final Future<void> Function() onToggle;
  final Future<void> Function() onNext;
  final Future<void> Function() onVolumeUp;
  final Future<void> Function() onVolumeDown;

  const _PremiumMediaCard({
    required this.isBluetoothConnected,
    required this.nowPlayingTitle,
    required this.nowPlayingArtist,
    required this.onPrevious,
    required this.onToggle,
    required this.onNext,
    required this.onVolumeUp,
    required this.onVolumeDown,
  });

  @override
  Widget build(BuildContext context) {
    const Color primary = Color(0xFF4CC3FF);
    final Color btColor = isBluetoothConnected ? const Color(0xFF4CC3FF) : const Color(0xFFFF5252);
    final String btLabel = isBluetoothConnected ? 'BT CONNECTED' : 'NO BLUETOOTH';

    final bool hasTrack = nowPlayingTitle.isNotEmpty || nowPlayingArtist.isNotEmpty;
    final String marqueeText = hasTrack
        ? '♫ ${nowPlayingTitle.isNotEmpty ? nowPlayingTitle : 'Unknown Track'}${nowPlayingArtist.isNotEmpty ? ' — $nowPlayingArtist' : ''}'
        : (isBluetoothConnected ? '♫ BLUETOOTH CONNECTED — NO TRACK' : 'NO BLUETOOTH DEVICE');

    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: const Text(
                  'MEDIA CONTROLS',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Color(0xFF7AA6B9), fontWeight: FontWeight.w800, letterSpacing: 2),
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.bluetooth, color: btColor, size: 16),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  btLabel,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: btColor,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Scrolling now-playing marquee under the controls
          _MarqueeText(
            text: marqueeText,
            style: TextStyle(
              color: hasTrack ? const Color(0xFFEFF6FF) : const Color(0xFF7AA6B9),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              Expanded(child: _MediaBtn(icon: Icons.volume_down_rounded, label: 'VOL -', color: primary, onPressed: onVolumeDown)),
              Expanded(child: _MediaBtn(icon: Icons.skip_previous_rounded, label: 'PREV', color: primary, onPressed: onPrevious)),
              Expanded(child: _MediaBtn(icon: Icons.play_arrow_rounded, label: 'PLAY', color: primary, isPrimary: true, onPressed: onToggle)),
              Expanded(child: _MediaBtn(icon: Icons.skip_next_rounded, label: 'NEXT', color: primary, onPressed: onNext)),
              Expanded(child: _MediaBtn(icon: Icons.volume_up_rounded, label: 'VOL +', color: primary, onPressed: onVolumeUp)),
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
  final bool isOnline;
  final VoidCallback? onClear;

  const _DestinationBanner({
    required this.destination,
    required this.isLocationReady,
    required this.isOnline,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final String message;
    final Color bgColor;

    if (!isLocationReady) {
      message = 'ALLOW LOCATION PERMISSION';
      bgColor = const Color(0xFFFF5252).withValues(alpha: 0.9);
    } else if (!isOnline && destination != null) {
      message = 'OFFLINE — ROUTE UNAVAILABLE';
      bgColor = const Color(0xFFFF9800).withValues(alpha: 0.9);
    } else if (!isOnline) {
      message = 'OFFLINE — CACHED MAPS & GPS ACTIVE';
      bgColor = const Color(0xFFFF9800).withValues(alpha: 0.9);
    } else if (destination != null) {
      message = 'DEST: ${destination!.latitude.toStringAsFixed(4)}, ${destination!.longitude.toStringAsFixed(4)}';
      bgColor = const Color(0xFFFF5252).withValues(alpha: 0.9);
    } else {
      message = 'TAP MAP TO SELECT DESTINATION';
      bgColor = const Color(0xFF4CC3FF).withValues(alpha: 0.85);
    }

    final Color iconColor = bgColor.computeLuminance() > 0.5 ? Colors.black : Colors.white;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: bgColor.withValues(alpha: 0.5), blurRadius: 12)],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            !isLocationReady
                ? Icons.warning
                : !isOnline
                    ? Icons.wifi_off
                    : destination != null
                        ? Icons.location_on
                        : Icons.touch_app,
            color: iconColor,
            size: 18,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              message,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: iconColor, fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
          if (destination != null) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: onClear,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.close, color: iconColor, size: 16),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Interactive map with offline awareness.
class _CarMap extends StatefulWidget {
  final latlong.LatLng center;
  final double heading;
  final bool locationReady;
  final latlong.LatLng? destination;
  final List<latlong.LatLng> routePoints;
  final bool isOnline;
  final Function(latlong.LatLng)? onMapTap;

  const _CarMap({
    super.key,
    required this.center,
    required this.heading,
    required this.locationReady,
    this.destination,
    required this.routePoints,
    required this.isOnline,
    this.onMapTap,
  });

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
  void centerOnLocation([latlong.LatLng? point]) {
    if (widget.locationReady && mounted) {
      _mapController.move(point ?? widget.center, 16.5);
    }
  }

  /// Rotate the map so "up" matches the current travel direction (degrees).
  void setRotation(double degrees) {
    if (mounted) _mapController.rotate(degrees);
  }

  @override
  void didUpdateWidget(covariant _CarMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.heading != widget.heading && mounted) {
      _mapController.rotate(widget.heading);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: widget.center,
            initialZoom: 16.5,
            initialRotation: widget.heading * pi / 180,
            interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
            onTap: (tapPosition, point) => widget.onMapTap?.call(point),
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.carapp.launcher',
              tileProvider: CachedTileProvider(),
            ),
            if (widget.routePoints.isNotEmpty)
              PolylineLayer(polylines: [
                Polyline(points: widget.routePoints, color: const Color(0xFF4CC3FF), strokeWidth: 5),
              ]),
            if (widget.locationReady)
              MarkerLayer(markers: [
                Marker(
                  point: widget.center,
                  width: 44,
                  height: 44,
                  child: Transform.rotate(
                    angle: -pi / 4,
                    child: const Icon(Icons.navigation, color: Color(0xFF4CC3FF), size: 44),
                  ),
                ),
                if (widget.destination != null)
                  Marker(point: widget.destination!, width: 38, height: 38, child: const Icon(Icons.location_on, color: Color(0xFFFF5252), size: 38)),
              ]),
          ],
        ),
        if (!widget.isOnline && widget.locationReady)
          Positioned(
            bottom: 80,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: const Color(0xFFFF9800).withValues(alpha: 0.5)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.navigation, color: Color(0xFF4CC3FF), size: 20),
                    SizedBox(width: 10),
                    Text(
                      'GPS TRACKING — OFFLINE MODE',
                      style: TextStyle(
                        color: Color(0xFFB0BEC5),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}