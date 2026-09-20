import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'screens/pdf_viewer_screen.dart';
import 'screens/web_landing_screen.dart';
import 'widgets/apple_dialog.dart';
import 'screens/home_screen.dart';
import 'utils/app_localizations.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  PaintingBinding.instance.imageCache.maximumSize = 30;
  PaintingBinding.instance.imageCache.maximumSizeBytes = 30 * 1024 * 1024;
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));
  runApp(const DocScanSignApp());   // Changed
}

class DocScanSignApp extends StatefulWidget {   // Changed
  const DocScanSignApp({super.key});   // Changed
  @override
  State<DocScanSignApp> createState() => _DocScanSignAppState();   // Changed
}

class _DocScanSignAppState extends State<DocScanSignApp> {   // Changed
  final _nav = GlobalKey<NavigatorState>();
  static const _channel = MethodChannel('docsign/file_open');   // Kept as is
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

  Future<String?> _resolveContentUri(String path) async {
    if (!path.startsWith('content://')) return path;
    try {
      final resolvedPath = await _channel.invokeMethod<String>('resolveContentUri', {'uri': path});
      return resolvedPath;
    } catch (e) {
      debugPrint('Failed to resolve content URI: $e');
      return null;
    }
  }

  void _openFile(String path, Uint8List? bytes) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _nav.currentState?.push(
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => PdfViewerScreen(filePath: path, preloadedBytes: bytes),
          transitionsBuilder: (_, animation, __, child) => FadeTransition(opacity: animation, child: child),
          transitionDuration: const Duration(milliseconds: 300),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _nav,
      title: 'DocScanSign',   // Changed
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('en'), Locale('es'), Locale('hi'), Locale('te'), Locale('fr'),
      ],
      localeResolutionCallback: (deviceLocale, supported) {
        if (deviceLocale != null && supported.any((l) => l.languageCode == deviceLocale.languageCode)) {
          return deviceLocale;
        }
        return const Locale('en');
      },
      home: const AppRoot(),
    );
  }

  ThemeData _buildTheme() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF6366F1),
        brightness: Brightness.dark,
      ),
      scaffoldBackgroundColor: const Color(0xFF09090B),
      dialogTheme: DialogThemeData(
        backgroundColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
        ),
      ),
      dialogBackgroundColor: Colors.transparent,
      textTheme: GoogleFonts.interTextTheme().apply(
        bodyColor: Colors.white,
        displayColor: Colors.white,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.black.withOpacity(0.7),
        elevation: 0,
        centerTitle: true,
        titleTextStyle: GoogleFonts.inter(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: Colors.white,
          letterSpacing: -0.3,
        ),
        iconTheme: const IconThemeData(color: Color(0xFF6366F1)),
      ),
    );
  }
}

class AppRoot extends StatelessWidget {
  const AppRoot({super.key});
  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) return const HomeScreen();
    return const WebLandingScreen();
  }
}