import 'dart:async';

import 'package:flutter/material.dart';

import 'core/theme.dart';
import 'screens/home_screen.dart';
import 'services/download_manager.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  unawaited(DownloadManager.instance.load());
  runApp(const TubeGrabApp());
}

class TubeGrabApp extends StatelessWidget {
  const TubeGrabApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TubeGrab',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: const HomeScreen(),
    );
  }
}
