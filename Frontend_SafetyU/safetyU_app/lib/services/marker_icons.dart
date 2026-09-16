import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// google_maps_flutter's BitmapDescriptor.defaultMarkerWithHue() is a
/// documented no-op on the web platform — every marker just falls back to
/// the same red pin there, regardless of hue (this doesn't affect Android
/// or iOS, where hues work fine). This loads real image-based markers
/// instead, which render correctly on every platform, and caches each one
/// so repeated calls (e.g. on every rebuild) don't reload the asset.
class MarkerIcons {
  MarkerIcons._();

  static Future<BitmapDescriptor>? _me;
  static Future<BitmapDescriptor>? _destination;
  static Future<BitmapDescriptor>? _contact;
  static Future<BitmapDescriptor>? _contactSelected;

  static Future<BitmapDescriptor> _load(BuildContext context, String asset) {
    final config = createLocalImageConfiguration(context, size: const Size(40, 55));
    return BitmapDescriptor.asset(config, asset);
  }

  /// Blue pin — the current user's own live position.
  static Future<BitmapDescriptor> me(BuildContext context) =>
      _me ??= _load(context, 'assets/images/marker_blue.png');

  /// Red pin — a destination or an active safety alert.
  static Future<BitmapDescriptor> destination(BuildContext context) =>
      _destination ??= _load(context, 'assets/images/marker_red.png');

  /// Orange pin — a trusted contact shown on the map, not currently selected.
  static Future<BitmapDescriptor> contact(BuildContext context) =>
      _contact ??= _load(context, 'assets/images/marker_orange.png');

  /// Violet pin — a trusted contact that's currently selected/highlighted.
  static Future<BitmapDescriptor> contactSelected(BuildContext context) =>
      _contactSelected ??= _load(context, 'assets/images/marker_violet.png');
}