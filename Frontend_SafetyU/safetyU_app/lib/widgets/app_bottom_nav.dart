import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/app_session.dart';

class _NavItem {
  final IconData icon;
  final String label;
  const _NavItem(this.icon, this.label);
}

/// Shared bottom nav bar: Home / Contacts / History / Profile.
/// Pass [currentIndex] to highlight the active tab and [onTap]
/// to handle navigation from the parent screen.
class AppBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int>? onTap;

  const AppBottomNav({super.key, required this.currentIndex, this.onTap});

  static const List<_NavItem> _items = [
    _NavItem(Icons.home, 'Home'),
    _NavItem(Icons.people_alt, 'Friends'),
    _NavItem(Icons.history, 'History'),
    _NavItem(Icons.person, 'Profile'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        // On top of whatever inset the phone itself reports for its
        // system nav bar/gesture pill, guarantee a real visual gap here
        // too — some Android devices (esp. 3-button nav) report little or
        // no bottom inset, which leaves this bar sitting flush against the
        // system buttons and makes them easy to mis-tap for each other.
        minimum: const EdgeInsets.only(bottom: 12),
        child: SizedBox(
          height: 64,
          child: Row(
            children: List.generate(_items.length, (i) {
              final item = _items[i];
              final active = i == currentIndex;
              // Each tab gets an equal, full-height slice of the bar as its
              // tap target (not just the tight box around the icon/label),
              // so adjacent tabs — and anything floating above the bar,
              // like the Add Friend button — can't be mis-tapped for each
              // other.
              return Expanded(
                child: InkWell(
                  onTap: () => onTap?.call(i),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      i == 1
                          ? AnimatedBuilder(
                              animation: AppSession.instance,
                              builder: (context, _) {
                                final count = AppSession
                                    .instance.pendingTrustRequestCount;
                                return Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    Icon(
                                      item.icon,
                                      size: 24,
                                      color: active
                                          ? AppColors.navy
                                          : AppColors.textMuted,
                                    ),
                                    if (count > 0)
                                      Positioned(
                                        top: -4,
                                        right: -6,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 5, vertical: 1),
                                          constraints: const BoxConstraints(
                                              minWidth: 16, minHeight: 16),
                                          decoration: BoxDecoration(
                                            color: AppColors.danger,
                                            borderRadius:
                                                BorderRadius.circular(10),
                                            border: Border.all(
                                                color: AppColors.card,
                                                width: 2),
                                          ),
                                          child: Text(
                                            count > 9 ? '9+' : '$count',
                                            textAlign: TextAlign.center,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 9,
                                              fontWeight: FontWeight.w800,
                                              height: 1.2,
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                );
                              },
                            )
                          : Icon(
                              item.icon,
                              size: 24,
                              color:
                                  active ? AppColors.navy : AppColors.textMuted,
                            ),
                      const SizedBox(height: 4),
                      Text(
                        item.label,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight:
                              active ? FontWeight.w700 : FontWeight.w500,
                          color: active ? AppColors.navy : AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}
