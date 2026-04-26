import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_image_labeling/google_mlkit_image_labeling.dart';

late List<CameraDescription> _cameras;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _cameras = await availableCameras();
  
  // Keep orientation portrait for simplicity
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  
  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'AR Demo',
      home: ImageRecognitionDemo(),
    );
  }
}

class ImageRecognitionDemo extends StatefulWidget {
  const ImageRecognitionDemo({super.key});

  @override
  State<ImageRecognitionDemo> createState() => _ImageRecognitionDemoState();
}

class _ImageRecognitionDemoState extends State<ImageRecognitionDemo> {
  CameraController? _controller;
  ImageLabeler? _imageLabeler;
  bool _isProcessing = false;
  bool _imageDetected = false;

  // The text to display when the image is detected
  final String _overlayText = "this is demo for musis of skikm gantegok karma bhai";

  @override
  void initState() {
    super.initState();
    _initializeCamera();
    _initializeLabeler();
  }

  void _initializeCamera() async {
    if (_cameras.isEmpty) return;
    
    // Choose the first back camera
    final camera = _cameras.firstWhere(
      (cam) => cam.lensDirection == CameraLensDirection.back,
      orElse: () => _cameras.first,
    );

    _controller = CameraController(
      camera,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: Platform.isAndroid 
          ? ImageFormatGroup.nv21 
          : ImageFormatGroup.bgra8888,
    );

    await _controller?.initialize();
    if (!mounted) return;

    _controller?.startImageStream((CameraImage image) {
      if (!_isProcessing) {
        _processCameraImage(image);
      }
    });
    setState(() {});
  }

  void _initializeLabeler() {
    // For a production app with a SPECIFIC image, you would use a Custom Image Labeler
    // powered by a trained .tflite model containing only your reference painting.
    // final modelPath = 'assets/my_custom_model.tflite';
    // final options = CustomLabelerOptions(modelPath: modelPath, confidenceThreshold: 0.7);
    // _imageLabeler = ImageLabeler(options: options);

    // For this DEMO, we use the base ML Kit model and trigger the overlay 
    // whenever it detects a "Painting", "Art", or "Picture frame".
    final options = ImageLabelerOptions(confidenceThreshold: 0.65);
    _imageLabeler = ImageLabeler(options: options);
  }

  Future<void> _processCameraImage(CameraImage image) async {
    _isProcessing = true;
    try {
      final inputImage = _inputImageFromCameraImage(image);
      if (inputImage == null) return;

      final labels = await _imageLabeler?.processImage(inputImage);
      bool foundPainting = false;

      if (labels != null) {
        for (final label in labels) {
          final text = label.label.toLowerCase();
          // Demo logic: If it sees a "painting" or "art", consider it a match
          if (text.contains('painting') || text.contains('art') || text.contains('picture frame')) {
            foundPainting = true;
            break;
          }
        }
      }

      if (_imageDetected != foundPainting) {
        setState(() {
          _imageDetected = foundPainting;
        });
      }
    } catch (e) {
      debugPrint("Error processing image: $e");
    } finally {
      // Small delay to prevent running recognition too frequently (saves battery)
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
    
    // Calculate rotation
    InputImageRotation? rotation;
    if (Platform.isIOS) {
      rotation = InputImageRotationValue.fromRawValue(sensorOrientation);
    } else if (Platform.isAndroid) {
      var rotationCompensation = 0; // for simplicity assuming portrait
      if (camera.lensDirection == CameraLensDirection.front) {
        rotationCompensation = (sensorOrientation + rotationCompensation) % 360;
      } else {
        rotationCompensation = (sensorOrientation - rotationCompensation + 360) % 360;
      }
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

  @override
  void dispose() {
    _controller?.stopImageStream();
    _controller?.dispose();
    _imageLabeler?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_controller == null || !_controller!.value.isInitialized) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Camera Preview
          CameraPreview(_controller!),

          // 2. Overlay (Bounding Box / Highlight visual feedback)
          if (_imageDetected)
            Center(
              child: Container(
                width: 300,
                height: 400,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.greenAccent, width: 4),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.greenAccent.withOpacity(0.3),
                      blurRadius: 20,
                      spreadRadius: 5,
                    ),
                  ],
                ),
              ),
            ),

          // 3. Text Overlay
          if (_imageDetected)
            Positioned(
              top: 80,
              left: 20,
              right: 20,
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.0, end: 1.0),
                duration: const Duration(milliseconds: 300),
                builder: (context, value, child) {
                  return Opacity(
                    opacity: value,
                    child: Transform.translate(
                      offset: Offset(0, 20 * (1 - value)),
                      child: child,
                    ),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
                  decoration: BoxDecoration(
                    color: Colors.black87,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.greenAccent.withOpacity(0.5), width: 1),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.5),
                        blurRadius: 10,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.check_circle_outline, color: Colors.greenAccent, size: 32),
                      const SizedBox(height: 12),
                      Text(
                        _overlayText,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
