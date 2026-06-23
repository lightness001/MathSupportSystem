import 'dart:io' as io;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../services/web_safe_file.dart';

class CropImageScreen extends StatefulWidget {
  final File imageFile;
  static bool isTesting = false;
  
  const CropImageScreen({super.key, required this.imageFile});

  @override
  State<CropImageScreen> createState() => _CropImageScreenState();
}

class _CropImageScreenState extends State<CropImageScreen> {
  late ui.Image _uiImage;
  bool _imageLoaded = false;
  Size _imageSize = Size.zero;
  bool _isCropping = false;

  Rect? _cropRect;
  Size? _lastContainerSize;

  String? _activeHandle; // 'TL', 'TR', 'BL', 'BR', 'MOVE'
  Offset _dragStartOffset = Offset.zero;
  Rect _dragStartRect = Rect.zero;
  
  static const double hitTestThreshold = 35.0; // Enlarged touch target for premium UX

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  Future<void> _loadImage() async {
    try {
      // Avoid hanging inside headless widget tests that lack a native C++ image codec decoder
      if (CropImageScreen.isTesting) {
        await Future.delayed(Duration.zero);
        if (mounted) {
          setState(() {
            _imageSize = const Size(800, 600);
            _imageLoaded = true;
          });
        }
        return;
      }

      final bytes = await widget.imageFile.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      if (mounted) {
        setState(() {
          _uiImage = frame.image;
          _imageSize = Size(_uiImage.width.toDouble(), _uiImage.height.toDouble());
          _imageLoaded = true;
        });
      }
    } catch (e) {
      debugPrint("Error loading image: $e");
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error loading image: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _onPanStart(DragStartDetails details, Rect imageRect) {
    final localPos = details.localPosition;
    if (_cropRect == null) return;

    final tl = _cropRect!.topLeft;
    final tr = _cropRect!.topRight;
    final bl = _cropRect!.bottomLeft;
    final br = _cropRect!.bottomRight;

    _dragStartRect = _cropRect!;
    _dragStartOffset = localPos;

    if ((localPos - tl).distance < hitTestThreshold) {
      _activeHandle = 'TL';
    } else if ((localPos - tr).distance < hitTestThreshold) {
      _activeHandle = 'TR';
    } else if ((localPos - bl).distance < hitTestThreshold) {
      _activeHandle = 'BL';
    } else if ((localPos - br).distance < hitTestThreshold) {
      _activeHandle = 'BR';
    } else if (_cropRect!.contains(localPos)) {
      _activeHandle = 'MOVE';
    } else {
      _activeHandle = null;
    }
  }

  void _onPanUpdate(DragUpdateDetails details, Rect imageRect) {
    if (_activeHandle == null || _cropRect == null) return;

    final currentPos = details.localPosition;
    final delta = currentPos - _dragStartOffset;

    double left = _dragStartRect.left;
    double top = _dragStartRect.top;
    double right = _dragStartRect.right;
    double bottom = _dragStartRect.bottom;

    const double minSize = 80.0; // Maintain readable area

    if (_activeHandle == 'TL') {
      left = (_dragStartRect.left + delta.dx).clamp(imageRect.left, right - minSize);
      top = (_dragStartRect.top + delta.dy).clamp(imageRect.top, bottom - minSize);
    } else if (_activeHandle == 'TR') {
      right = (_dragStartRect.right + delta.dx).clamp(left + minSize, imageRect.right);
      top = (_dragStartRect.top + delta.dy).clamp(imageRect.top, bottom - minSize);
    } else if (_activeHandle == 'BL') {
      left = (_dragStartRect.left + delta.dx).clamp(imageRect.left, right - minSize);
      bottom = (_dragStartRect.bottom + delta.dy).clamp(top + minSize, imageRect.bottom);
    } else if (_activeHandle == 'BR') {
      right = (_dragStartRect.right + delta.dx).clamp(left + minSize, imageRect.right);
      bottom = (_dragStartRect.bottom + delta.dy).clamp(top + minSize, imageRect.bottom);
    } else if (_activeHandle == 'MOVE') {
      double dx = delta.dx;
      double dy = delta.dy;

      // Constrain completely inside visible image boundaries
      if (left + dx < imageRect.left) dx = imageRect.left - left;
      if (right + dx > imageRect.right) dx = imageRect.right - right;
      if (top + dy < imageRect.top) dy = imageRect.top - top;
      if (bottom + dy > imageRect.bottom) dy = imageRect.bottom - bottom;

      left += dx;
      right += dx;
      top += dy;
      bottom += dy;
    }

    setState(() {
      _cropRect = Rect.fromLTRB(left, top, right, bottom);
    });
  }

  void _onPanEnd(DragEndDetails details) {
    _activeHandle = null;
  }

  Future<void> _cropAndSave() async {
    if (_cropRect == null || _lastContainerSize == null || !_imageLoaded) return;

    setState(() => _isCropping = true);

    try {
      final fitSize = applyBoxFit(BoxFit.contain, _imageSize, _lastContainerSize!);
      final renderWidth = fitSize.destination.width;
      final renderHeight = fitSize.destination.height;
      final offsetX = (_lastContainerSize!.width - renderWidth) / 2;
      final offsetY = (_lastContainerSize!.height - renderHeight) / 2;

      // Calculate relative coordinate scale on the actual original image
      final relativeLeft = ((_cropRect!.left - offsetX) / renderWidth * _imageSize.width).clamp(0.0, _imageSize.width);
      final relativeTop = ((_cropRect!.top - offsetY) / renderHeight * _imageSize.height).clamp(0.0, _imageSize.height);

      final relativeWidth = (_cropRect!.width / renderWidth * _imageSize.width).clamp(1.0, _imageSize.width - relativeLeft);
      final relativeHeight = (_cropRect!.height / renderHeight * _imageSize.height).clamp(1.0, _imageSize.height - relativeTop);

      // Render the sub-image using Canvas high-performance scaling API
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final paint = Paint()
        ..isAntiAlias = true
        ..filterQuality = ui.FilterQuality.high;

      final srcRect = Rect.fromLTWH(relativeLeft, relativeTop, relativeWidth, relativeHeight);
      final destRect = Rect.fromLTWH(0, 0, relativeWidth, relativeHeight);

      canvas.drawImageRect(_uiImage, srcRect, destRect, paint);

      final picture = recorder.endRecording();
      final croppedUiImage = await picture.toImage(relativeWidth.toInt(), relativeHeight.toInt());

      final byteData = await croppedUiImage.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) throw Exception("Failed to crop image.");

      final croppedBytes = byteData.buffer.asUint8List();

      final tempDir = Directory.systemTemp;
      final croppedFile = File('${tempDir.path}/cropped_${DateTime.now().millisecondsSinceEpoch}.png');
      await croppedFile.writeAsBytes(croppedBytes);

      if (mounted) {
        Navigator.pop(context, croppedFile);
      }
    } catch (e) {
      debugPrint("Cropping failed: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to crop image: $e"), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isCropping = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const Color darkSlate = Color(0xFF1E272C);
    const Color primaryBlue = Color(0xFF0D47A1);

    return Scaffold(
      backgroundColor: darkSlate,
      appBar: AppBar(
        title: const Text("Crop Homework Sheet", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (_imageLoaded && !_isCropping)
            TextButton.icon(
              onPressed: _cropAndSave,
              icon: const Icon(Icons.check, color: Colors.greenAccent),
              label: const Text("DONE", style: TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 16)),
            ),
        ],
      ),
      body: _isCropping
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: Colors.white),
                  SizedBox(height: 16),
                  Text("Cropping image worksheet...", style: TextStyle(color: Colors.white70, fontSize: 15)),
                ],
              ),
            )
          : !_imageLoaded
              ? const Center(child: CircularProgressIndicator(color: Colors.white))
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final containerSize = Size(constraints.maxWidth, constraints.maxHeight);
                    final fitSize = applyBoxFit(BoxFit.contain, _imageSize, containerSize);
                    final renderWidth = fitSize.destination.width;
                    final renderHeight = fitSize.destination.height;
                    final offsetX = (containerSize.width - renderWidth) / 2;
                    final offsetY = (containerSize.height - renderHeight) / 2;

                    final imageRect = Rect.fromLTWH(offsetX, offsetY, renderWidth, renderHeight);

                    // Initialize cropRect to centered inset on first build
                    if (_cropRect == null || _lastContainerSize != containerSize) {
                      _lastContainerSize = containerSize;
                      _cropRect = imageRect.deflate(MediaQuery.of(context).size.shortestSide * 0.08);
                    }

                    return Stack(
                      children: [
                        // Background image preview
                        Positioned.fill(
                          child: Center(
                            child: SizedBox(
                              width: renderWidth,
                              height: renderHeight,
                              child: !CropImageScreen.isTesting
                                  ? (kIsWeb
                                      ? Image.network(widget.imageFile.path, fit: BoxFit.fill)
                                      : Image.file(io.File(widget.imageFile.path), fit: BoxFit.fill))
                                  : Container(color: const Color(0xFF1E272C)),
                            ),
                          ),
                        ),
                        // Dark translucent Crop overlay & corner handles
                        Positioned.fill(
                          child: CustomPaint(
                            painter: CropOverlayPainter(
                              cropRect: _cropRect!,
                              imageRect: imageRect,
                            ),
                          ),
                        ),
                        // Touch responder for panning handles and center movement
                        Positioned.fill(
                          child: GestureDetector(
                            onPanStart: (details) => _onPanStart(details, imageRect),
                            onPanUpdate: (details) => _onPanUpdate(details, imageRect),
                            onPanEnd: _onPanEnd,
                          ),
                        ),
                        // Top/Bottom Instruction Banners
                        Positioned(
                          bottom: 24,
                          left: 20,
                          right: 20,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.85),
                              borderRadius: BorderRadius.circular(30),
                            ),
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.crop_free, color: Colors.blueAccent, size: 20),
                                SizedBox(width: 8),
                                Text(
                                  "Drag corners to crop your homework questions",
                                  style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
    );
  }
}

class CropOverlayPainter extends CustomPainter {
  final Rect cropRect;
  final Rect imageRect;

  CropOverlayPainter({required this.cropRect, required this.imageRect});

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Draw dark mask outside the crop rect, constrained strictly to the image size
    final maskPaint = Paint()
      ..color = Colors.black.withOpacity(0.55)
      ..style = PaintingStyle.fill;

    final backgroundPath = Path()..addRect(imageRect);
    final cropPath = Path()..addRect(cropRect);
    final finalPath = Path.combine(PathOperation.difference, backgroundPath, cropPath);

    canvas.drawPath(finalPath, maskPaint);

    // 2. Draw border lines
    final borderPaint = Paint()
      ..color = Colors.white.withOpacity(0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8;

    canvas.drawRect(cropRect, borderPaint);

    // 3. Draw high-end corner handles
    final handlePaint = Paint()
      ..color = Colors.blueAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.5
      ..strokeCap = StrokeCap.round;

    const double length = 20.0;

    // Top-Left
    canvas.drawPath(
      Path()
        ..moveTo(cropRect.left, cropRect.top + length)
        ..lineTo(cropRect.left, cropRect.top)
        ..lineTo(cropRect.left + length, cropRect.top),
      handlePaint,
    );

    // Top-Right
    canvas.drawPath(
      Path()
        ..moveTo(cropRect.right - length, cropRect.top)
        ..lineTo(cropRect.right, cropRect.top)
        ..lineTo(cropRect.right, cropRect.top + length),
      handlePaint,
    );

    // Bottom-Left
    canvas.drawPath(
      Path()
        ..moveTo(cropRect.left, cropRect.bottom - length)
        ..lineTo(cropRect.left, cropRect.bottom)
        ..lineTo(cropRect.left + length, cropRect.bottom),
      handlePaint,
    );

    // Bottom-Right
    canvas.drawPath(
      Path()
        ..moveTo(cropRect.right - length, cropRect.bottom)
        ..lineTo(cropRect.right, cropRect.bottom)
        ..lineTo(cropRect.right, cropRect.bottom - length),
      handlePaint,
    );
  }

  @override
  bool shouldRepaint(covariant CropOverlayPainter oldDelegate) {
    return oldDelegate.cropRect != cropRect || oldDelegate.imageRect != imageRect;
  }
}
