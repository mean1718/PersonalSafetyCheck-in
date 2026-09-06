import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class _NavItem {
  final IconData icon;
  final String label;
  const _NavItem(this.icon, this.label);
}

/// Bottom nav for the Emergency Responder role: Home / Cases / Report /
/// Profile — distinct from the regular User's Home / Contacts / History /
/// Profile nav, matching the officer app's own navigation model.
class ResponderBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int>? onTap;

  const ResponderBottomNav({super.key, required this.currentIndex, this.onTap});

  static const List<_NavItem> _items = [
    _NavItem(Icons.home, 'Home'),
    _NavItem(Icons.folder_open, 'Case'),
    _NavItem(Icons.description_outlined, 'Report'),
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
        minimum: const EdgeInsets.only(bottom: 12),
        child: SizedBox(
          height: 64,
          child: Row(
            children: List.generate(_items.length, (i) {
              final item = _items[i];
              final active = i == currentIndex;
              return Expanded(
                child: InkWell(
                  onTap: () => onTap?.call(i),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(item.icon,
                          size: 24,
                          color: active ? AppColors.navy : AppColors.textMuted),
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
