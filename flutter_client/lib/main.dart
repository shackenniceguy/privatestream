import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:privatestream/core/theme.dart';
import 'package:privatestream/core/responsive_shell.dart';
import 'package:privatestream/screens/home_screen.dart';
import 'package:privatestream/screens/downloads_screen.dart';
import 'package:privatestream/screens/settings_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize hardware-accelerated MediaKit video engine
  MediaKit.ensureInitialized();

  // Initialize SQLite FFI database engine for Linux, macOS, and Windows desktop
  if (!kIsWeb && (Platform.isLinux || Platform.isMacOS || Platform.isWindows)) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  runApp(
    const ProviderScope(
      child: PrivateStreamApp(),
    ),
  );
}

class PrivateStreamApp extends StatelessWidget {
  const PrivateStreamApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PrivateStream',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const MainNavigationRoot(),
    );
  }
}

class MainNavigationRoot extends StatefulWidget {
  const MainNavigationRoot({super.key});

  @override
  State<MainNavigationRoot> createState() => _MainNavigationRootState();
}

class _MainNavigationRootState extends State<MainNavigationRoot> {
  int _currentIndex = 0;

  final List<Widget> _pages = const [
    HomeScreen(),
    DownloadsScreen(initialTabIndex: 0), // On-Device Offline Downloads
    DownloadsScreen(initialTabIndex: 1), // Cloud Torrents Ingestion Queue
    SettingsScreen(),                   // Server Endpoint & Offline Storage Management
  ];

  @override
  Widget build(BuildContext context) {
    return ResponsiveShell(
      currentIndex: _currentIndex,
      onNavigationChanged: (index) {
        setState(() => _currentIndex = index);
      },
      pages: _pages,
    );
  }
}
