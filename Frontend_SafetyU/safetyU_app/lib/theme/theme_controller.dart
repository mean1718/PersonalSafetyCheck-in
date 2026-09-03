import 'package:flutter/foundation.dart';

/// The single source of truth for light/dark mode.
///
/// AppColors reads `ThemeController.instance.isDark` on every color lookup,
/// so flipping this and calling notifyListeners() is enough to re-color the
/// whole app on the next rebuild — no per-screen wiring needed.
class ThemeController extends ChangeNotifier {
  ThemeController._internal();
  static final ThemeController instance = ThemeController._internal();

  bool isDark = false;

  void setDark(bool value) {
    if (isDark == value) return;
    isDark = value;
    notifyListeners();
  }

  void toggle() => setDark(!isDark);
}
