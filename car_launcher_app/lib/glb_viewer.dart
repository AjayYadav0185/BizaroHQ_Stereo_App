import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// GLB (Binary glTF) 3D Model Viewer
///
/// Renders 3D models directly on Flutter canvas without WebView or WebGL.
/// This enables 360-degree car model viewing on any Android device including
/// the TopWay TS7 (SC7731E ARMv7) which has limited WebGL support.
///
/// Features:
/// - Reads standard GLB binary files with JSON + BIN chunks
/// - Software 3D rendering pipeline on Canvas
/// - 360-degree auto-rotation
/// - Touch-based rotation (swipe to rotate)
/// - Works on all Android versions (API 24+)
/// - No external plugin dependencies
class Model3D {
  List<ui.Offset> vertices = [];
  List<int> indices = [];
  List<ui.Offset> normals = [];
  List<ui.Color> vertexColors = [];
  double scale = 1.0;
  ui.Offset center = ui.Offset.zero;
  bool hasColors = false;

  Model3D();
}

/// GLB file parser and 3D software renderer.
class GLBViewer extends StatefulWidget {
  final String assetPath;
  final double height;
  final double width;
  final Color glowColor;

  const GLBViewer({
    super.key,
    required this.assetPath,
    this.height = 180,
    this.width = double.infinity,
    this.glowColor = const Color(0xFF4CC3FF),
  });

  @override
  State<GLBViewer> createState() => _GLBViewerState();
}

class _GLBViewerState extends State<GLBViewer>
    with SingleTickerProviderStateMixin {
  Model3D? _model;
  bool _isLoading = true;
  String? _error;

  // 360-degree rotation
  double _rotationAngle = 0.0;
  double _dragStartAngle = 0.0;
  double _dragStartRotation = 0.0;
  bool _isDragging = false;
  late AnimationController _rotationController;
  late Animation<double> _floatAnimation;
  late AnimationController _floatController;

  // Glow pulse
  late AnimationController _glowController;
  late Animation<double> _glowAnimation;

  @override
  void initState() {
    super.initState();

    // Auto-rotation animation (360 degrees)
    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..addListener(() {
        if (!_isDragging) {
          setState(() {
            _rotationAngle = _rotationController.value * 2 * pi;
          });
        }
      })
      ..repeat();

    // Floating animation
    _floatController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);
    _floatAnimation = Tween<double>(begin: -6, end: 6).animate(
      CurvedAnimation(parent: _floatController, curve: Curves.easeInOutSine),
    );
    _floatController.forward();

    // Glow pulse
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
    _glowAnimation = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _glowController, curve: Curves.easeInOutSine),
    );
    _glowController.forward();

    _loadModel();
  }

  Future<void> _loadModel() async {
    try {
      final bytes = await rootBundle.load(widget.assetPath);
      final model = await _parseGLB(bytes.buffer.asUint8List());
      if (mounted) {
        setState(() {
          _model = model;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  /// Parse a GLB (Binary glTF) file into a Model3D.
  Future<Model3D> _parseGLB(Uint8List glbData) async {
    if (glbData.length < 12) {
      throw FormatException('Invalid GLB file: too small');
    }

    // Parse header
    final magic = String.fromCharCodes(glbData.sublist(0, 4));
    if (magic != 'glTF') {
      throw FormatException('Invalid GLB magic: $magic');
    }

    final version = ByteData.sublistView(glbData, 4).getUint32(0, Endian.little);
    if (version != 2) {
      throw FormatException('Unsupported glTF version: $version');
    }

    // Parse chunks
    int offset = 12;
    String jsonStr = '';
    Uint8List binData = Uint8List(0);

    while (offset < glbData.length) {
      if (offset + 8 > glbData.length) break;
      final chunkView = ByteData.sublistView(glbData, offset);
      final chunkLength = chunkView.getUint32(0, Endian.little);
      final chunkType = chunkView.getUint32(4, Endian.little);

      if (offset + 8 + chunkLength > glbData.length) break;
      final chunkData = glbData.sublist(offset + 8, offset + 8 + chunkLength);

      if (chunkType == 0x4E4F534A) {
        jsonStr = utf8.decode(chunkData);
      } else if (chunkType == 0x004E4942) {
        binData = chunkData;
      }

      offset += 8 + chunkLength;
    }

    if (jsonStr.isEmpty) {
      throw FormatException('No JSON chunk found in GLB');
    }

    return _parseGLTFJson(jsonStr, binData);
  }

  /// Parse glTF JSON and extract mesh data from the BIN buffer.
  Model3D _parseGLTFJson(String jsonStr, Uint8List binData) {
    final gltf = json.decode(jsonStr) as Map<String, dynamic>;
    final model = Model3D();

    final accessors = gltf['accessors'] as List? ?? [];
    final bufferViews = gltf['bufferViews'] as List? ?? [];
    final meshes = gltf['meshes'] as List? ?? [];

    if (accessors.isEmpty || bufferViews.isEmpty || meshes.isEmpty) {
      throw FormatException('GLB file has no mesh data');
    }

    for (final mesh in meshes) {
      final primitives = mesh['primitives'] as List? ?? [];
      for (final primitive in primitives) {
        final attributes = primitive['attributes'] as Map<String, dynamic>? ?? {};
        final indicesAccessorIdx = primitive['indices'] as int?;

        if (indicesAccessorIdx != null) {
          final idxAccessor = accessors[indicesAccessorIdx] as Map<String, dynamic>;
          final idxBufferView = bufferViews[idxAccessor['bufferView'] as int] as Map<String, dynamic>;
          final idxByteOffset = (idxBufferView['byteOffset'] as int?) ?? 0;
          final idxCount = idxAccessor['count'] as int;
          final idxComponentType = idxAccessor['componentType'] as int;

          final idxData = _readBufferData(binData, idxByteOffset,
              idxCount * _componentSize(idxComponentType), idxComponentType);

          model.indices = List.generate(idxCount, (i) {
            if (idxComponentType == 5125) {
              return ByteData.sublistView(idxData, i * 4).getUint32(0, Endian.little);
            } else {
              return ByteData.sublistView(idxData, i * 2).getUint16(0, Endian.little);
            }
          });
        }

        final posAccessorIdx = attributes['POSITION'] as int?;
        if (posAccessorIdx != null) {
          final posAccessor = accessors[posAccessorIdx] as Map<String, dynamic>;
          final posBufferView = bufferViews[posAccessor['bufferView'] as int] as Map<String, dynamic>;
          final posByteOffset = (posBufferView['byteOffset'] as int?) ?? 0;
          final posCount = posAccessor['count'] as int;
          final posByteStride = (posBufferView['byteStride'] as int?) ?? 12;

          final posData = binData.sublist(posByteOffset);

          for (int i = 0; i < posCount; i++) {
            final baseOffset = i * posByteStride;
            if (baseOffset + 12 > posData.length) break;

            final v = ByteData.sublistView(posData, baseOffset);
            final x = v.getFloat32(0, Endian.little);
            final y = v.getFloat32(4, Endian.little);
            final z = v.getFloat32(8, Endian.little);
            model.vertices.add(ui.Offset(x, y) + ui.Offset(z, 0));
          }
        }
      }

      if (model.vertices.isNotEmpty) break;
    }

    if (model.vertices.isEmpty) {
      throw FormatException('No vertex data found in GLB');
    }

    double minX = double.infinity, maxX = double.negativeInfinity;
    double minY = double.infinity, maxY = double.negativeInfinity;

    for (final v in model.vertices) {
      final x = v.dx;
      final y = v.dy;
      if (x < minX) minX = x;
      if (x > maxX) maxX = x;
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;
    }

    model.center = ui.Offset((minX + maxX) / 2, (minY + maxY) / 2);

    final rangeX = maxX - minX;
    final rangeY = maxY - minY;
    final maxRange = max(rangeX, rangeY);
    model.scale = maxRange > 0 ? 1.0 / maxRange : 1.0;

    model.hasColors = false;
    model.vertexColors = List.generate(
      model.vertices.length,
      (_) => const Color(0xFF4CC3FF),
    );

    return model;
  }

  int _componentSize(int componentType) {
    switch (componentType) {
      case 5120: case 5121: return 1;
      case 5122: case 5123: return 2;
      case 5125: case 5126: return 4;
      default: return 1;
    }
  }

  Uint8List _readBufferData(Uint8List binData, int byteOffset, int length, int componentType) {
    final end = (byteOffset + length).clamp(0, binData.length);
    return binData.sublist(byteOffset, end);
  }

  @override
  void dispose() {
    _rotationController.dispose();
    _floatController.dispose();
    _glowController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return SizedBox(
        height: widget.height,
        child: const Center(child: CircularProgressIndicator(color: Color(0xFF4CC3FF))),
      );
    }

    if (_error != null || _model == null) {
      return _fallbackCarWidget();
    }

    return _GlassContainer3D(
      borderRadius: 20,
      glowColor: widget.glowColor,
      glowAnimation: _glowAnimation,
      child: SizedBox(
        height: widget.height,
        width: widget.width,
        child: GestureDetector(
          onPanStart: (details) {
            _isDragging = true;
            _dragStartAngle = details.localPosition.dx;
            _dragStartRotation = _rotationAngle;
            _rotationController.stop();
          },
          onPanUpdate: (details) {
            setState(() {
              final delta = (details.localPosition.dx - _dragStartAngle) / 100;
              _rotationAngle = _dragStartRotation + delta;
            });
          },
          onPanEnd: (details) {
            _isDragging = false;
            final currentProgress = (_rotationAngle % (2 * pi)) / (2 * pi);
            _rotationController.value = currentProgress.clamp(0.0, 1.0);
            _rotationController.repeat();
          },
          child: AnimatedBuilder(
            animation: Listenable.merge([_floatAnimation, _glowAnimation]),
            builder: (context, child) {
              return LayoutBuilder(
                builder: (context, constraints) {
                  return CustomPaint(
                    size: Size(constraints.maxWidth, constraints.maxHeight),
                    painter: _GLBCarPainter(
                      model: _model!,
                      rotationAngle: _rotationAngle,
                      floatOffset: _floatAnimation.value,
                      glowIntensity: _glowAnimation.value,
                      glowColor: widget.glowColor,
                    ),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _fallbackCarWidget() {
    return _GlassContainer3D(
      borderRadius: 20,
      glowColor: widget.glowColor,
      glowAnimation: _glowAnimation,
      child: SizedBox(
        height: widget.height,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 130, height: 130,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [
                  widget.glowColor.withValues(alpha: 0.15 * _glowAnimation.value),
                  const Color(0x00000000),
                ]),
              ),
            ),
            Transform.translate(
              offset: Offset(0, _floatAnimation.value),
              child: SizedBox(
                width: 140, height: 70,
                child: CustomPaint(painter: _FallbackCarPainter(glowIntensity: _glowAnimation.value)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GlassContainer3D extends StatelessWidget {
  final Widget child;
  final double borderRadius;
  final Color glowColor;
  final Animation<double> glowAnimation;

  const _GlassContainer3D({
    required this.child,
    required this.borderRadius,
    required this.glowColor,
    required this.glowAnimation,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(color: Colors.white.withValues(alpha: 0.18), width: 1.2),
            boxShadow: [BoxShadow(color: glowColor.withValues(alpha: 0.18), blurRadius: 26, spreadRadius: 1)],
            gradient: LinearGradient(colors: [Colors.white.withValues(alpha: 0.12), Colors.white.withValues(alpha: 0.02)], begin: Alignment.topLeft, end: Alignment.bottomRight),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Custom painter that renders the 3D GLB car model on Flutter canvas.
class _GLBCarPainter extends CustomPainter {
  final Model3D model;
  final double rotationAngle;
  final double floatOffset;
  final double glowIntensity;
  final Color glowColor;

  _GLBCarPainter({
    required this.model,
    required this.rotationAngle,
    required this.floatOffset,
    required this.glowIntensity,
    required this.glowColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (model.vertices.isEmpty) return;

    final centerX = size.width / 2;
    final centerY = size.height / 2 + floatOffset;
    final renderScale = min(size.width, size.height) * 0.6 * model.scale;

    final cosA = cos(rotationAngle);
    final sinA = sin(rotationAngle);

    final projected = <_ProjectedVertex>[];

    for (int i = 0; i < model.vertices.length; i++) {
      final v = model.vertices[i];
      final x = v.dx - model.center.dx;
      final y = -(v.dy - model.center.dy);
      final z = (v.distance - model.center.distance).abs() * 0.5;
      final rx = x * cosA - z * sinA;
      final rz = x * sinA + z * cosA;
      final ry = y;
      final perspective = 1.0 / (1.0 + rz * 0.5 + 1.0);
      final sx = centerX + rx * renderScale * perspective;
      final sy = centerY + ry * renderScale * perspective;
      projected.add(_ProjectedVertex(sx, sy, rz, glowColor));
    }

    final glowPaint = Paint()
      ..color = glowColor.withValues(alpha: 0.15 * glowIntensity)
      ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 20);
    canvas.drawCircle(Offset(centerX, centerY), renderScale * 0.8, glowPaint);

    if (model.indices.length >= 3) {
      final triangles = <_Triangle>[];
      for (int i = 0; i < model.indices.length - 2; i += 3) {
        final i0 = model.indices[i];
        final i1 = model.indices[i + 1];
        final i2 = model.indices[i + 2];
        if (i0 < projected.length && i1 < projected.length && i2 < projected.length) {
          final avgZ = (projected[i0].z + projected[i1].z + projected[i2].z) / 3;
          triangles.add(_Triangle(i0, i1, i2, avgZ));
        }
      }
      triangles.sort((a, b) => b.avgZ.compareTo(a.avgZ));

      for (final tri in triangles) {
        final p0 = projected[tri.i0];
        final p1 = projected[tri.i1];
        final p2 = projected[tri.i2];
        final edge1x = p1.x - p0.x;
        final edge1y = p1.y - p0.y;
        final edge2x = p2.x - p0.x;
        final edge2y = p2.y - p0.y;
        final normal = edge1x * edge2y - edge1y * edge2x;
        if (normal > 0) continue;

        final fillPaint = Paint()
          ..color = glowColor.withValues(alpha: 0.08 + 0.04 * glowIntensity)
          ..style = PaintingStyle.fill;
        final path = ui.Path()..moveTo(p0.x, p0.y)..lineTo(p1.x, p1.y)..lineTo(p2.x, p2.y)..close();
        canvas.drawPath(path, fillPaint);

        final edgePaint = Paint()
          ..color = glowColor.withValues(alpha: 0.3 + 0.2 * glowIntensity)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5;
        canvas.drawPath(path, edgePaint);
      }

      for (final tri in triangles) {
        final p0 = projected[tri.i0];
        final p1 = projected[tri.i1];
        final p2 = projected[tri.i2];
        final edge1x = p1.x - p0.x;
        final edge1y = p1.y - p0.y;
        final edge2x = p2.x - p0.x;
        final edge2y = p2.y - p0.y;
        final normal = edge1x * edge2y - edge1y * edge2x;
        if (normal > 0) continue;
        final brightPaint = Paint()
          ..color = Colors.white.withValues(alpha: 0.15 * glowIntensity)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8;
        final path = ui.Path()..moveTo(p0.x, p0.y)..lineTo(p1.x, p1.y)..lineTo(p2.x, p2.y)..close();
        canvas.drawPath(path, brightPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _GLBCarPainter oldDelegate) {
    return oldDelegate.rotationAngle != rotationAngle ||
        oldDelegate.floatOffset != floatOffset ||
        oldDelegate.glowIntensity != glowIntensity;
  }
}

class _ProjectedVertex {
  final double x, y, z;
  final Color color;
  _ProjectedVertex(this.x, this.y, this.z, this.color);
}

class _Triangle {
  final int i0, i1, i2;
  final double avgZ;
  _Triangle(this.i0, this.i1, this.i2, this.avgZ);
}

/// Fallback 2D car painter (kept for when GLB fails)
class _FallbackCarPainter extends CustomPainter {
  final double glowIntensity;
  _FallbackCarPainter({required this.glowIntensity});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..shader = const LinearGradient(colors: [Color(0xFF4CC3FF), Color(0xFF9B8CFF)], begin: Alignment.topLeft, end: Alignment.bottomRight)
          .createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..style = PaintingStyle.fill;

    final glowPaint = Paint()
      ..color = const Color(0xFF4CC3FF).withValues(alpha: 0.3)
      ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 5);

    final bodyPath = ui.Path();
    bodyPath.moveTo(size.width * 0.2, size.height * 0.35);
    bodyPath.cubicTo(size.width * 0.25, size.height * 0.05, size.width * 0.55, size.height * 0.05, size.width * 0.6, size.height * 0.35);
    bodyPath.cubicTo(size.width * 0.65, size.height * 0.35, size.width * 0.85, size.height * 0.3, size.width * 0.9, size.height * 0.55);
    bodyPath.cubicTo(size.width * 0.95, size.height * 0.6, size.width * 0.92, size.height * 0.75, size.width * 0.85, size.height * 0.75);
    bodyPath.lineTo(size.width * 0.72, size.height * 0.75);
    bodyPath.cubicTo(size.width * 0.7, size.height * 0.85, size.width * 0.6, size.height * 0.85, size.width * 0.58, size.height * 0.75);
    bodyPath.lineTo(size.width * 0.38, size.height * 0.75);
    bodyPath.cubicTo(size.width * 0.36, size.height * 0.85, size.width * 0.26, size.height * 0.85, size.width * 0.24, size.height * 0.75);
    bodyPath.lineTo(size.width * 0.15, size.height * 0.75);
    bodyPath.cubicTo(size.width * 0.08, size.height * 0.75, size.width * 0.05, size.height * 0.6, size.width * 0.1, size.height * 0.55);
    bodyPath.cubicTo(size.width * 0.12, size.height * 0.5, size.width * 0.15, size.height * 0.4, size.width * 0.2, size.height * 0.35);
    bodyPath.close();

    canvas.drawPath(bodyPath, glowPaint);
    canvas.drawPath(bodyPath, paint);

    final windshieldPaint = Paint()..color = Colors.white.withValues(alpha: 0.2)..style = PaintingStyle.fill;
    final windshieldPath = ui.Path();
    windshieldPath.moveTo(size.width * 0.22, size.height * 0.38);
    windshieldPath.lineTo(size.width * 0.28, size.height * 0.25);
    windshieldPath.lineTo(size.width * 0.5, size.height * 0.25);
    windshieldPath.lineTo(size.width * 0.55, size.height * 0.38);
    windshieldPath.close();
    canvas.drawPath(windshieldPath, windshieldPaint);

    final headlightPaint = Paint()..color = const Color(0xFFFFD700).withValues(alpha: 0.6 * glowIntensity)..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 4);
    canvas.drawCircle(Offset(size.width * 0.1, size.height * 0.6), 4 + glowIntensity * 2, headlightPaint);

    final tailLightPaint = Paint()..color = const Color(0xFFFF4444).withValues(alpha: 0.6 * glowIntensity)..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 3);
    canvas.drawCircle(Offset(size.width * 0.88, size.height * 0.6), 3 + glowIntensity * 1.5, tailLightPaint);

    final wheelPaint = Paint()..color = Colors.white.withValues(alpha: 0.3)..style = PaintingStyle.stroke..strokeWidth = 1.5;
    canvas.drawCircle(Offset(size.width * 0.3, size.height * 0.78), size.height * 0.07, wheelPaint);
    canvas.drawCircle(Offset(size.width * 0.65, size.height * 0.78), size.height * 0.07, wheelPaint);
  }

  @override
  bool shouldRepaint(covariant _FallbackCarPainter oldDelegate) => oldDelegate.glowIntensity != glowIntensity;
}