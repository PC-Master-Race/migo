// onboarding_screen.dart — Polished first-run experience.
// 5 pages: Welcome → Privacy Promise → Your Name → Avatar Teaser → Ready.
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

const Duration _pageAnimDuration = Duration(milliseconds: 380);
const Curve _pageAnimCurve = Curves.easeInOutCubic;
const Color _darkBg = Color(0xFF0D0D1A);

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
      _pageController.nextPage(duration: _pageAnimDuration, curve: _pageAnimCurve);
    } else {
      _finish();
    }
  }

  void _skip() => _finish();

  void _finish() {
    final String name = _nameController.text.trim();
    if (name.isNotEmpty) {
      Hive.box<dynamic>(hiveBoxSettings).put('display_name', name);
    }
    Hive.box<dynamic>(hiveBoxSettings).put(settingsKeyOnboardingComplete, true);
    Navigator.of(context).pushReplacementNamed(MapScreen.routeName);
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);
    return Scaffold(
      backgroundColor: _darkBg,
      body: Stack(
        children: <Widget>[
          PageView(
            controller: _pageController,
            physics: const NeverScrollableScrollPhysics(),
            onPageChanged: (int i) => setState(() => _currentPage = i),
            children: <Widget>[
              // _ScrollSafe lets a page scroll (instead of overflowing) on
              // short screens / large system fonts. The Name and Avatar pages
              // already wrap themselves, so they're not double-wrapped here.
              _ScrollSafe(child: _WelcomePage(onNext: _next)),
              _ScrollSafe(child: _PrivacyPage(onNext: _next)),
              _NamePage(controller: _nameController, onNext: _next),
              _AvatarTeaserPage(onNext: _next),
              _ScrollSafe(child: _ReadyPage(onFinish: _finish)),
            ],
          ),
          if (_currentPage < _pageCount - 1)
            Positioned(
              top: MediaQuery.of(context).padding.top + 12,
              right: 20,
              child: TextButton(
                onPressed: _skip,
                child: const Text('Skip',
                    style: TextStyle(color: Colors.white54, fontSize: 14, fontWeight: FontWeight.w600)),
              ),
            ),
          Positioned(
            bottom: MediaQuery.of(context).padding.bottom + 100,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List<Widget>.generate(_pageCount, (int i) {
                final bool active = i == _currentPage;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: active ? 20 : 7,
                  height: 7,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    color: active ? migoCoral : Colors.white.withValues(alpha: 0.25),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}

/// Wraps a page so it scrolls when it's taller than the viewport (short
/// screens, large system fonts, on-screen keyboard) yet stays vertically
/// centred when it fits. Apply once per page — never double-wrap.
class _ScrollSafe extends StatelessWidget {
  const _ScrollSafe({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: IntrinsicHeight(child: child),
          ),
        );
      },
    );
  }
}

// Page 1 — Welcome
class _WelcomePage extends StatelessWidget {
  const _WelcomePage({required this.onNext});
  final VoidCallback onNext;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          const AvatarWidget(archetype: DrivingArchetype.rocket, size: 120),
          const SizedBox(height: 32),
          Text('Bravo Maps',
              style: Theme.of(context).textTheme.displaySmall?.copyWith(
                    color: Colors.white, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
          const SizedBox(height: 12),
          Text('Navigate with personality.\nStay completely private.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 17, height: 1.5)),
          const SizedBox(height: 48),
          _PrimaryButton(label: 'Get started', onPressed: onNext),
        ],
      ),
    );
  }
}

// Page 2 — Privacy Promise
class _PrivacyPage extends StatelessWidget {
  const _PrivacyPage({required this.onNext});
  final VoidCallback onNext;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const _PageHeader(
            emoji: "\u{1F512}",
            title: 'Your data,\nyour rules.',
            subtitle: 'We built Bravo Maps around one simple promise:',
          ),
          const SizedBox(height: 32),
          const _PrivacyItem(icon: Icons.block_rounded, color: migoCoral,
              title: 'No ad networks. Ever.',
              body: 'Zero SDKs from Google, Meta, or any ad platform. No tracking pixels.'),
          const SizedBox(height: 20),
          const _PrivacyItem(icon: Icons.sell_outlined, color: migoAmber,
              title: 'Your data is not for sale.',
              body: "We don't sell or share your data with third parties. Your routes stay with us."),
          const SizedBox(height: 20),
          const _PrivacyItem(icon: Icons.shield_rounded, color: migoTeal,
              title: 'Insurance? Never.',
              body: 'Driving data is never shared with insurance companies or law enforcement.'),
          const SizedBox(height: 48),
          Center(child: _PrimaryButton(label: 'I love this', onPressed: onNext)),
        ],
      ),
    );
  }
}

class _PrivacyItem extends StatelessWidget {
  const _PrivacyItem({required this.icon, required this.color, required this.title, required this.body});
  final IconData icon;
  final Color color;
  final String title;
  final String body;
  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          width: 40, height: 40,
          decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
          const SizedBox(height: 3),
          Text(body, style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 12.5, height: 1.45)),
        ])),
      ],
    );
  }
}

// Page 3 — Your Name
class _NamePage extends StatelessWidget {
  const _NamePage({required this.controller, required this.onNext});
  final TextEditingController controller;
  final VoidCallback onNext;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          // Scrollable so the keyboard opening can't overflow the page, while
          // staying vertically centred when the keyboard is closed.
          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: IntrinsicHeight(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    const _PageHeader(
                      emoji: "\u{1F44B}",
                      title: "What should we\ncall you?",
                      subtitle: 'Shown only to your family group. Change it anytime in Settings.',
                    ),
                    const SizedBox(height: 36),
                    TextField(
            controller: controller,
            textCapitalization: TextCapitalization.words,
            maxLength: 24,
            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
            decoration: InputDecoration(
              hintText: 'Nickname or first name',
              hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.35)),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.08),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              counterStyle: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
            ),
          ),
                    const SizedBox(height: 32),
                    _PrimaryButton(label: 'Continue', onPressed: onNext),
                    const SizedBox(height: 12),
                    TextButton(onPressed: onNext,
                        child: Text('Skip for now',
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 14))),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// Page 4 — Avatar Teaser
class _AvatarTeaserPage extends StatelessWidget {
  const _AvatarTeaserPage({required this.onNext});
  final VoidCallback onNext;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          // Scrollable so it never overflows on shorter screens, yet stays
          // vertically centred when there's enough room.
          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: IntrinsicHeight(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    const _PageHeader(
                      emoji: "\u{1F3CE}",
                      title: 'Drive to discover\nyour avatar.',
                      subtitle: 'Bravo Maps figures out your style and assigns your chibi character. Which will you be?',
                    ),
                    const SizedBox(height: 28),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 16, runSpacing: 16,
                      children: DrivingArchetype.values.map((DrivingArchetype a) => Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          AvatarWidget(archetype: a, size: 56),
                          const SizedBox(height: 4),
                          Text(_shortName(a),
                              style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 10, fontWeight: FontWeight.w600)),
                        ],
                      )).toList(),
                    ),
                    const SizedBox(height: 40),
                    _PrimaryButton(label: "I'm ready to find out", onPressed: onNext),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
  String _shortName(DrivingArchetype a) => switch (a) {
    DrivingArchetype.grandpa => 'Grandpa', DrivingArchetype.rocket => 'Rocket',
    DrivingArchetype.ghost => 'Ghost', DrivingArchetype.scout => 'Scout',
    DrivingArchetype.phantom => 'Phantom', DrivingArchetype.zenMaster => 'Zen',
    DrivingArchetype.chaosAgent => 'Chaos', DrivingArchetype.nightOwl => 'Night Owl',
    DrivingArchetype.streetRat => 'Street Rat',
  };
}

// Page 5 — Ready
class _ReadyPage extends StatelessWidget {
  const _ReadyPage({required this.onFinish});
  final VoidCallback onFinish;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              AvatarWidget(archetype: DrivingArchetype.zenMaster, size: 60),
              SizedBox(width: 8),
              AvatarWidget(archetype: DrivingArchetype.rocket, size: 80),
              SizedBox(width: 8),
              AvatarWidget(archetype: DrivingArchetype.scout, size: 60),
            ],
          ),
          const SizedBox(height: 32),
          Text("You're all set!", style: Theme.of(context).textTheme.displaySmall?.copyWith(
              color: Colors.white, fontWeight: FontWeight.w900)),
          const SizedBox(height: 12),
          Text("Report hazards. Earn Bravos. Keep your location to yourself.\n\nLet's go.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 16, height: 1.6)),
          const SizedBox(height: 48),
          _PrimaryButton(label: "Let's drive! \u{1F697}", onPressed: onFinish),
        ],
      ),
    );
  }
}

// Shared widgets
class _PageHeader extends StatelessWidget {
  const _PageHeader({required this.emoji, required this.title, required this.subtitle});
  final String emoji; final String title; final String subtitle;
  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
      Text(emoji, style: const TextStyle(fontSize: 44)),
      const SizedBox(height: 14),
      Text(title, style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w800, height: 1.15)),
      const SizedBox(height: 12),
      Text(subtitle, style: TextStyle(color: Colors.white.withValues(alpha: 0.65), fontSize: 15, height: 1.55)),
    ]);
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({required this.label, required this.onPressed});
  final String label; final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity, height: 54,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: migoCoral, foregroundColor: Colors.white, elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
        ),
        onPressed: onPressed,
        child: Text(label),
      ),
    );
  }
}
