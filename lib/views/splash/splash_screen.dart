import 'dart:async';
import 'package:flutter/material.dart';

const _brandGreen = Color(0xFF176455);
const _muted = Color(0xFF6E7D83);

/// Shows the startup logo for [duration], then swaps to [child].
class SplashGate extends StatefulWidget {
  const SplashGate({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 1800),
  });
  final Widget child;
  final Duration duration;

  @override
  State<SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<SplashGate> {
  bool _finished = false;

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: const Duration(milliseconds: 350),
    switchInCurve: Curves.easeOut,
    switchOutCurve: Curves.easeIn,
    child: _finished
        ? KeyedSubtree(key: const ValueKey('app-content'), child: widget.child)
        : SplashScreen(
            key: const ValueKey('splash-screen'),
            duration: widget.duration,
            onFinished: () {
              if (mounted) setState(() => _finished = true);
            },
          ),
  );
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({
    super.key,
    required this.onFinished,
    this.duration = const Duration(milliseconds: 1800),
  });
  final VoidCallback onFinished;
  final Duration duration;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _controller, _drive;
  late final Animation<double> _fade, _scale, _driveProgress;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    final curve = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
    _fade = curve;
    _scale = Tween<double>(begin: 0.94, end: 1).animate(curve);
    _drive = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _driveProgress = CurvedAnimation(
      parent: _drive,
      curve: Curves.easeInOutCubic,
    );
    _controller.forward();
    _drive.forward();
    _timer = Timer(widget.duration, widget.onFinished);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    _drive.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.white, Color(0xFFF5F7F8)],
        ),
      ),
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          child: FadeTransition(
            opacity: _fade,
            child: ScaleTransition(
              scale: _scale,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Semantics(
                    label: 'Xe Máy Toàn Hợp',
                    image: true,
                    child: ConstrainedBox(
                      key: const ValueKey('splash-logo-box'),
                      constraints: const BoxConstraints(maxWidth: 260),
                      child: Image.asset(
                        'assets/images/SplashLogo.png',
                        key: const ValueKey('splash-logo'),
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.high,
                        errorBuilder: (_, _, _) => const Icon(
                          Icons.storefront,
                          size: 56,
                          color: _brandGreen,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Xe Máy Toàn Hợp',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _brandGreen,
                      fontSize: 34,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 340),
                    child: SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: Stack(
                        children: [
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 9,
                            child: Container(
                              height: 2,
                              color: const Color(0xFFE0E7E9),
                            ),
                          ),
                          Positioned.fill(
                            child: AnimatedBuilder(
                              animation: _driveProgress,
                              builder: (context, child) => Align(
                                alignment: Alignment(
                                  -1 + 2 * _driveProgress.value,
                                  0,
                                ),
                                child: child,
                              ),
                              child: const Icon(
                                Icons.two_wheeler,
                                key: ValueKey('splash-motorcycle'),
                                color: _brandGreen,
                                size: 40,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Đang khởi động…',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: _muted, fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
