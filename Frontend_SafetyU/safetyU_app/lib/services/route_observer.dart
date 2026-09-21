import 'package:flutter/material.dart';

/// Shared app-wide [RouteObserver], registered on the [MaterialApp] in
/// main.dart. Lets a screen (e.g. Home) know when another screen gets
/// pushed on top of it or popped back off, so it can pause/resume things
/// like the plan-promo popup timer instead of firing while it's covered.
final RouteObserver<PageRoute> appRouteObserver = RouteObserver<PageRoute>();

/// Lets code outside the widget tree (push notification taps) navigate.
/// Registered as `navigatorKey` on the MaterialApp in main.dart.
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();
