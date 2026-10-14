import 'package:flutter/material.dart';
import 'router_finder_screen.dart';

void main() {
  runApp(const RouteFinderApp());
}

class RouteFinderApp extends StatelessWidget {
  const RouteFinderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Route Finder',
      home: RouteFinderScreen(),
    );
  }
}