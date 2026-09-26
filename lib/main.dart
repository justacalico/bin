import 'package:flutter/material.dart';

import 'bootstrap_stub.dart'
    if (dart.library.io) 'bootstrap_io.dart';
import 'ui/home_page.dart';

void main() {
  configureProxy();
  runApp(const BinApp());
}

class BinApp extends StatelessWidget {
  const BinApp({super.key});

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF74BFFF);
    return MaterialApp(
      title: 'bin',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0A0A12),
        colorScheme: const ColorScheme.dark(
          primary: accent,
          surface: Color(0xFF14141F),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF14141F),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
          hintStyle: const TextStyle(color: Color(0xFF55556A)),
        ),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}
