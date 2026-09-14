import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// A flat, hand-drawn-from-shapes cityscape + simplified person illustration,
/// in the spirit of the reference design (skyline silhouette, person with a
/// backpack looking at their phone, floating location pin). Built entirely
/// from basic shapes rather than a real illustration asset — deliberately
/// simple/geometric rather than attempting photorealistic line art, which
/// would need an actual designed asset to look right.
class SafetyIllustration extends StatelessWidget {
  final double height;
  const SafetyIllustration({super.key, this.height = 150});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Container(color: const Color(0xFFEAF0FE)),
            // Skyline — simple rectangles of varying height, back-to-front
            // so nearer buildings are drawn last (on top).
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: height * 0.62,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _building(width: 30, heightFactor: 0.55, color: 0xFFC7D7F8),
                  _building(width: 22, heightFactor: 0.8, color: 0xFFB7CBF6),
                  _building(width: 34, heightFactor: 0.4, color: 0xFFD3E0FA),
                  _building(width: 26, heightFactor: 0.95, color: 0xFFA9C0F4),
                  const Spacer(),
                  _building(width: 28, heightFactor: 0.6, color: 0xFFC7D7F8),
                  _building(width: 20, heightFactor: 0.85, color: 0xFFB7CBF6),
                  _building(width: 30, heightFactor: 0.45, color: 0xFFD3E0FA),
                ],
              ),
            ),
            // Floating location pin, upper right.
            Positioned(
              top: height * 0.12,
              right: 22,
              child: Icon(Icons.location_on,
                  color: const Color(0xFF3E6DF6), size: 26),
            ),
            // Simplified person: head + hoodie body + backpack, made from
            // plain shapes rather than a traced illustration.
            Positioned(
              bottom: 0,
              right: 46,
              child: _personFigure(height: height * 0.78),
            ),
          ],
        ),
      ),
    );
  }

  Widget _building(
      {required double width,
      required double heightFactor,
      required int color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 1.5),
      child: FractionallySizedBox(
        heightFactor: heightFactor,
        alignment: Alignment.bottomCenter,
        child: Container(width: width, color: Color(color)),
      ),
    );
  }

  Widget _personFigure({required double height}) {
    final backpackColor = const Color(0xFF2B3A67);
    final hoodieColor = const Color(0xFF3E6DF6);
    final skinColor = const Color(0xFFF2C6A0);
    return SizedBox(
      height: height,
      width: 70,
      child: Stack(
        alignment: Alignment.bottomCenter,
        clipBehavior: Clip.none,
        children: [
          // Backpack, peeking out behind the body.
          Positioned(
            bottom: height * 0.28,
            left: 4,
            child: Container(
              width: 26,
              height: height * 0.34,
              decoration: BoxDecoration(
                color: backpackColor,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          // Body (hoodie), a simple rounded trapezoid stand-in.
          Positioned(
            bottom: 0,
            child: Container(
              width: 46,
              height: height * 0.52,
              decoration: BoxDecoration(
                color: hoodieColor,
                borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(22), bottom: Radius.circular(10)),
              ),
            ),
          ),
          // Arm holding a phone.
          Positioned(
            bottom: height * 0.32,
            right: 2,
            child: Container(
              width: 10,
              height: height * 0.22,
              decoration: BoxDecoration(
                color: hoodieColor,
                borderRadius: BorderRadius.circular(6),
              ),
            ),
          ),
          Positioned(
            bottom: height * 0.5,
            right: -2,
            child: Container(
              width: 14,
              height: 20,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(3),
                border: Border.all(color: const Color(0xFF1B1D29), width: 1.5),
              ),
            ),
          ),
          // Head.
          Positioned(
            bottom: height * 0.56,
            child: Container(
              width: 26,
              height: 26,
              decoration:
                  BoxDecoration(color: skinColor, shape: BoxShape.circle),
            ),
          ),
          // Hair, a simple arc-like shape over part of the head.
          Positioned(
            bottom: height * 0.68,
            left: 18,
            child: Container(
              width: 26,
              height: 16,
              decoration: const BoxDecoration(
                color: Color(0xFF2B2340),
                borderRadius: BorderRadius.vertical(top: Radius.circular(13)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Wraps a bottom action area (button, optional link below it) with the
/// skyline background behind it — same treatment as Add Contact and Login,
/// reused here so it isn't duplicated across every form screen.
class SkylineBottomBar extends StatelessWidget {
  final Widget child;
  final double height;
  const SkylineBottomBar({super.key, required this.child, this.height = 150});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          Positioned.fill(
            child: Image.asset(
              'assets/images/add_contact_background.png',
              fit: BoxFit.cover,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: child,
          ),
        ],
      ),
    );
  }
}

/// Small decorative corner accent — a soft blob plus a heart — used in the
/// app bar area of several screens in the reference designs. Purely
/// decorative, no functionality.
class HeaderAccent extends StatelessWidget {
  final double size;
  const HeaderAccent({super.key, this.size = 46});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            top: 0,
            child: Container(
              width: size * 0.7,
              height: size * 0.7,
              decoration: BoxDecoration(
                color: const Color(0xFF4A90E2).withValues(alpha: 0.18),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Positioned(
            right: -2,
            bottom: -2,
            child:
                Icon(Icons.favorite, size: size * 0.4, color: AppColors.danger),
          ),
        ],
      ),
    );
  }
}

/// Simple wavy background with a cloud and a couple of droplet/leaf
/// accents — used behind a bottom button area on a few screens, distinct
/// from the fuller SafetyIllustration/SkylineBottomBar art.
class WaveDecorBottom extends StatelessWidget {
  final double height;
  const WaveDecorBottom({super.key, this.height = 120});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ClipPath(
            clipper: BottomWaveClipper(),
            child: Container(
              color: const Color(0xFF4A90E2).withValues(alpha: 0.1),
            ),
          ),
          Positioned(
            top: height * 0.1,
            right: 40,
            child: Icon(Icons.cloud,
                size: 26,
                color: const Color(0xFF4A90E2).withValues(alpha: 0.35)),
          ),
          Positioned(
            left: 40,
            bottom: 10,
            child: Icon(Icons.water_drop,
                size: 20,
                color: const Color(0xFF4A90E2).withValues(alpha: 0.4)),
          ),
          Positioned(
            right: 60,
            bottom: 4,
            child: Icon(Icons.water_drop,
                size: 18, color: AppColors.danger.withValues(alpha: 0.35)),
          ),
        ],
      ),
    );
  }
}

/// Decorative wave shape for the bottom of a screen, matching the reference
/// design's soft rounded wave under the role tiles.
class BottomWaveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.lineTo(0, size.height * 0.5);
    path.quadraticBezierTo(size.width * 0.25, size.height * 0.2,
        size.width * 0.5, size.height * 0.45);
    path.quadraticBezierTo(
        size.width * 0.75, size.height * 0.7, size.width, size.height * 0.35);
    path.lineTo(size.width, size.height);
    path.lineTo(0, size.height);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}

/// Thin decorative wave band — use at the very bottom of a screen, behind
/// the primary button, for the soft rounded-wave accent from the reference.
class BottomWaveBand extends StatelessWidget {
  final double height;
  const BottomWaveBand({super.key, this.height = 60});

  @override
  Widget build(BuildContext context) {
    return ClipPath(
      clipper: BottomWaveClipper(),
      child: Container(height: height, color: const Color(0xFFEAF0FE)),
    );
  }
}
