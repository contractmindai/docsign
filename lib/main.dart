import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'screens/pdf_viewer_screen.dart';
import 'screens/web_landing_screen.dart';
import 'screens/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  PaintingBinding.instance.imageCache.maximumSize = 30;
  PaintingBinding.instance.imageCache.maximumSizeBytes = 30 * 1024 * 1024;
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent, statusBarIconBrightness: Brightness.light,
  ));
  runApp(const DocSignApp());
}

class DocSignApp extends StatefulWidget {
  const DocSignApp({super.key});
  @override
  State<DocSignApp> createState() => _DocSignAppState();
}

class _DocSignAppState extends State<DocSignApp> {
  final _nav = GlobalKey<NavigatorState>();
  static const _channel = MethodChannel('docsign/file_open');
  final _pendingFiles = <String>[];

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) _setupFileOpenChannel();
  }

  void _setupFileOpenChannel() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'openFile') {
        final path = call.arguments as String?;
        if (path != null && path.isNotEmpty) {
          // ✅ Handle content:// URIs
          final resolvedPath = await _resolveContentUri(path);
          if (resolvedPath != null) {
            _openFile(resolvedPath, null);
          }
        }
      }
    });
    _getInitialFile();
  }

  Future<void> _getInitialFile() async {
    try {
      final path = await _channel.invokeMethod<String>('getInitialFile');
      if (path != null && path.isNotEmpty) {
        final resolvedPath = await _resolveContentUri(path);
        if (resolvedPath != null) {
          _openFile(resolvedPath, null);
        }
      }
    } catch (_) {}
  }

  // ✅ Resolve content:// URIs to local files
  Future<String?> _resolveContentUri(String path) async {
    // If it's already a file path, return it
    if (!path.startsWith('content://')) {
      return path;
    }

    try {
      // Use MethodChannel to call native Android code
      final resolvedPath = await _channel.invokeMethod<String>('resolveContentUri', {'uri': path});
      return resolvedPath;
    } catch (e) {
      print('Failed to resolve content URI: $e');
      return null;
    }
  }

  void _openFile(String path, Uint8List? bytes) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _nav.currentState?.push(MaterialPageRoute(
        builder: (_) => PdfViewerScreen(filePath: path, preloadedBytes: bytes)));
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _nav,
      title: 'DocSign',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6366F1), brightness: Brightness.dark),
        scaffoldBackgroundColor: const Color(0xFF09090B),
        useMaterial3: true,
      ),
      home: const AppRoot(),
    );
  }
}

class AppRoot extends StatelessWidget {
  const AppRoot({super.key});
  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) return HomeScreen();
    return const WebLandingScreen();
  }
}