import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_image_labeling/google_mlkit_image_labeling.dart';

late List<CameraDescription> _cameras;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    _cameras = await availableCameras();
  } catch (e) {
    debugPrint("Failed to get cameras: $e");
    _cameras = [];
  }
  
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'AR Demo',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.cyanAccent,
          brightness: Brightness.dark,
        ),
      ),
      home: const ImageRecognitionDemo(),
    );
  }
}

class ImageRecognitionDemo extends StatefulWidget {
  const ImageRecognitionDemo({super.key});

  @override
  State<ImageRecognitionDemo> createState() => _ImageRecognitionDemoState();
}

class _ImageRecognitionDemoState extends State<ImageRecognitionDemo> with SingleTickerProviderStateMixin {
  CameraController? _controller;
  ImageLabeler? _imageLabeler;
  bool _isProcessing = false;
  bool _imageDetected = false;
  String? _errorMessage;
  XFile? _lastCapturedImage;
  
  late AnimationController _scanController;

  // The text to display when the image is detected
  final String _overlayText = "this testing image test for ar";

  @override
  void initState() {
    super.initState();
    _initializeCamera();
    if (!kIsWeb) {
      _initializeLabeler();
    }
    
    _scanController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  void _initializeCamera() async {
    if (_cameras.isEmpty) {
      setState(() {
        _errorMessage = "No camera found on this device.";
      });
      return;
    }
    
    final camera = _cameras.firstWhere(
      (cam) => cam.lensDirection == CameraLensDirection.back,
      orElse: () => _cameras.first,
    );

    _controller = CameraController(
      camera,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: kIsWeb 
          ? ImageFormatGroup.jpeg 
          : (Platform.isAndroid ? ImageFormatGroup.nv21 : ImageFormatGroup.bgra8888),
    );

    try {
      await _controller?.initialize();
      if (!mounted) return;

      if (!kIsWeb) {
        _controller?.startImageStream((CameraImage image) {
          if (!_isProcessing) {
            _processCameraImage(image);
          }
        });
      }
      
      setState(() {
        _errorMessage = null;
      });
    } catch (e) {
      setState(() {
        _errorMessage = "Camera Error: ${e.toString()}";
      });
    }
  }

  void _initializeLabeler() {
    try {
      final options = ImageLabelerOptions(confidenceThreshold: 0.5); // Lower threshold for easier demo
      _imageLabeler = ImageLabeler(options: options);
    } catch (e) {
      debugPrint("ML Kit initialization failed: $e");
    }
  }

  Future<void> _processCameraImage(CameraImage image) async {
    if (_imageLabeler == null) return;
    
    _isProcessing = true;
    try {
      final inputImage = _inputImageFromCameraImage(image);
      if (inputImage == null) return;

      final labels = await _imageLabeler?.processImage(inputImage);
      bool foundTarget = false;

      if (labels != null) {
        for (final label in labels) {
          final text = label.label.toLowerCase();
          // Keywords that match the Starry Night painting
          if (text.contains('painting') || 
              text.contains('art') || 
              text.contains('starry night') ||
              text.contains('visual arts') ||
              text.contains('museum') ||
              text.contains('picture frame')) {
            foundTarget = true;
            break;
          }
        }
      }

      if (_imageDetected != foundTarget) {
        setState(() {
          _imageDetected = foundTarget;
        });
      }
    } catch (e) {
      debugPrint("Error processing image: $e");
    } finally {
      await Future.delayed(const Duration(milliseconds: 100));
      if (mounted) {
        _isProcessing = false;
      }
    }
  }

  InputImage? _inputImageFromCameraImage(CameraImage image) {
    if (_controller == null) return null;
    final camera = _controller!.description;
    final sensorOrientation = camera.sensorOrientation;
    
    InputImageRotation? rotation;
    if (Platform.isIOS) {
      rotation = InputImageRotationValue.fromRawValue(sensorOrientation);
    } else if (Platform.isAndroid) {
      var rotationCompensation = 0; 
      rotationCompensation = (sensorOrientation - rotationCompensation + 360) % 360;
      rotation = InputImageRotationValue.fromRawValue(rotationCompensation);
    }
    
    if (rotation == null) return null;

    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (format == null ||
        (Platform.isAndroid && format != InputImageFormat.nv21) ||
        (Platform.isIOS && format != InputImageFormat.bgra8888)) return null;

    if (image.planes.isEmpty) return null;

    return InputImage.fromBytes(
      bytes: Platform.isAndroid 
          ? _concatenatePlanes(image.planes) 
          : image.planes[0].bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: image.planes[0].bytesPerRow,
      ),
    );
  }

  Uint8List _concatenatePlanes(List<Plane> planes) {
    final WriteBuffer allBytes = WriteBuffer();
    for (Plane plane in planes) {
      allBytes.putUint8List(plane.bytes);
    }
    return allBytes.done().buffer.asUint8List();
  }

  Future<void> _takePhoto() async {
    if (_controller == null || !_controller!.value.isInitialized) return;

    try {
      final image = await _controller!.takePicture();
      setState(() {
        _lastCapturedImage = image;
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text("Photo Captured Successfully!"),
            backgroundColor: Colors.cyanAccent.withOpacity(0.8),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      debugPrint("Error taking photo: $e");
    }
  }

  @override
  void dispose() {
    _scanController.dispose();
    if (!kIsWeb) {
      _controller?.stopImageStream();
    }
    _controller?.dispose();
    _imageLabeler?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_errorMessage != null) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, color: Colors.redAccent, size: 64),
                const SizedBox(height: 16),
                Text(
                  _errorMessage!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 18),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _initializeCamera,
                  child: const Text("Retry"),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_controller == null || !_controller!.value.isInitialized) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Colors.cyanAccent),
              SizedBox(height: 16),
              Text("Initializing AR Engine...", style: TextStyle(color: Colors.white70)),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Camera Preview
          CameraPreview(_controller!),

          // 2. Scanning / AR Overlay
          if (!_imageDetected && !kIsWeb)
            AnimatedBuilder(
              animation: _scanController,
              builder: (context, child) {
                return Stack(
                  children: [
                    // Moving Scan Line
                    Positioned(
                      top: MediaQuery.of(context).size.height * 0.2 + 
                           (MediaQuery.of(context).size.height * 0.6 * _scanController.value),
                      left: 40,
                      right: 40,
                      child: Container(
                        height: 2,
                        decoration: BoxDecoration(
                          boxShadow: [
                            BoxShadow(
                              color: Colors.cyanAccent.withOpacity(0.5),
                              blurRadius: 10,
                              spreadRadius: 2,
                            ),
                          ],
                          gradient: const LinearGradient(
                            colors: [Colors.transparent, Colors.cyanAccent, Colors.transparent],
                          ),
                        ),
                      ),
                    ),
                    // Guide Corners
                    Center(
                      child: Container(
                        width: 280,
                        height: 350,
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.white10, width: 1),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),

          // 3. Detection Locked Overlay
          if (_imageDetected)
            Center(
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.8, end: 1.0),
                duration: const Duration(milliseconds: 500),
                curve: Curves.elasticOut,
                builder: (context, value, child) {
                  return Transform.scale(
                    scale: value,
                    child: Container(
                      width: 300,
                      height: 400,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.cyanAccent, width: 3),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.cyanAccent.withOpacity(0.4),
                            blurRadius: 30,
                            spreadRadius: 5,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),

          // 4. Status Bar
          Positioned(
            top: 50,
            left: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: _imageDetected ? Colors.cyanAccent : Colors.white24),
              ),
              child: Row(
                children: [
                  Icon(
                    _imageDetected ? Icons.lock : Icons.search,
                    color: _imageDetected ? Colors.cyanAccent : Colors.white70,
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    _imageDetected ? "TARGET LOCKED" : (kIsWeb ? "WEB MODE" : "SCANNING FOR AR..."),
                    style: TextStyle(
                      color: _imageDetected ? Colors.cyanAccent : Colors.white70,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 5. AR Text Overlay
          if (_imageDetected)
            Positioned(
              top: 120,
              left: 25,
              right: 25,
              child: _buildARContainer(
                child: Column(
                  children: [
                    const Icon(Icons.info_outline, color: Colors.cyanAccent, size: 36),
                    const SizedBox(height: 16),
                    Text(
                      _overlayText,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      "Detected: Starry Night",
                      style: TextStyle(color: Colors.cyanAccent, fontSize: 12, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
            ),

          // 6. Capture Control
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Gallery Thumbnail
                if (_lastCapturedImage != null)
                  GestureDetector(
                    onTap: () => _showImageDialog(_lastCapturedImage!.path),
                    child: Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white, width: 2),
                        image: DecorationImage(
                          image: kIsWeb 
                            ? NetworkImage(_lastCapturedImage!.path) 
                            : FileImage(File(_lastCapturedImage!.path)) as ImageProvider,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  )
                else
                  const SizedBox(width: 60),

                // Shutter
                GestureDetector(
                  onTap: _takePhoto,
                  child: Container(
                    width: 80,
                    height: 80,
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 3),
                    ),
                    child: Container(
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),

                const SizedBox(width: 60),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showImageDialog(String path) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(20)),
          child: kIsWeb ? Image.network(path) : Image.file(File(path)),
        ),
      ),
    );
  }

  Widget _buildARContainer({required Widget child}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.85),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.cyanAccent.withOpacity(0.5), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.cyanAccent.withOpacity(0.2),
            blurRadius: 20,
            spreadRadius: 2,
          ),
        ],
      ),
      child: child,
    );
  }
}
