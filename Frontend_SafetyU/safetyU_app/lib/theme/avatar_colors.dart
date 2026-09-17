import 'package:flutter/material.dart';

/// One palette, shared by every screen that shows a contact avatar
/// (Friends, Select Contacts, Home's trust-request banner, etc.) so the
/// same person always lands on the same color everywhere instead of each
/// screen picking its own flat tint.
const List<Color> avatarBgPalette = [
  Color(0xFFE3F0FF),
  Color(0xFFEEE8FF),
  Color(0xFFFFE9DE),
  Color(0xFFE1F7EA),
  Color(0xFFFFF3D6),
  Color(0xFFFFE0EC),
];

const List<Color> avatarFgPalette = [
  Color(0xFF2F6FED),
  Color(0xFF7C5CFC),
  Color(0xFFFF7A45),
  Color(0xFF23A26D),
  Color(0xFFE0A500),
  Color(0xFFF0508C),
];

/// Keyed off a stable identifier (contact id, or phone/name as a fallback)
/// so the color never shuffles between rebuilds or screens.
int avatarColorIndex(String key) => key.hashCode.abs() % avatarBgPalette.length;

Color avatarBackgroundFor(String key) => avatarBgPalette[avatarColorIndex(key)];
Color avatarForegroundFor(String key) => avatarFgPalette[avatarColorIndex(key)];

/// Main/Other tier colors, used anywhere the tier itself needs a color
/// (chips, selection ticks, banners) — Main is blue, Other is orange.
const Color mainTierColor = Color(0xFF2F6FED);
const Color otherTierColor = Color(0xFFF5A622);
