// onboarding_screen.dart — Polished first-run experience.
// 5 pages: Welcome → Privacy Promise → Your Name → Location → Ready.
// Shown once; splash_screen routes here only when onboarding_complete=false.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_ce/hive.dart';

import '../constants.dart';
import '../theme/bravo_theme.dart';
import '../widgets/avatar/avatar_painter.dart';
import '../models/archetype_model.dart';
import 'map_screen.dart';
import 'splash_screen.dart' show settingsKeyOnboardingComplete;

// ---------------------------------------------------------------------------
// Local constants
// ---------------------------------------------------------------------------

const Duration _pageAnimDuration = Duration(milliseconds: 380);
const Curve _pageAnimCurve = Curves.easeInOutCubic;
const Color _darkBg = Color(0xFF0D0D1A);

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});
  static const String routeName = '/onboarding';

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  final TextEditingController _nameController = TextEditingController();
  int _currentPage = 0;
  static const int _pageCount = 5;

  @override
  void dispose() {
    _pageController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  void _next() {
    if (_currentPage < _pageCount - 1) {
      _pageController.nextPage(
          duration: _pageAnimDuration, curve: _pageAnimCurve);
    } else {
      _finish();
    }
  }

  void _skip() => _finish();

  void _finish() {
    // Save display name if provided.
    final String name = _nam