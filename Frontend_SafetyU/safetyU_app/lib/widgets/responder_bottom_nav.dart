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
  final int caseCount;

  const ResponderBottomNav({super.key, required this.currentIndex, this.onTap, this.caseCount = 0,});

  static const List<_NavItem> _items = [
    _NavItem(Icons.home, 'Home'),
    _NavItem(Icons.folder_open, 'Cases'),
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
                      Stack(
                        clipBehavior: Clip.none,
    children: [
      Icon(
        item.icon,
        size: 24,
        color: active ? AppColors.navy : AppColors.textMuted,
      ),

      if (i == 1 && caseCount > 0)
        Positioned(
          right: -10,
          top: -8,
          child: Container(
            constraints: const BoxConstraints(
              minWidth: 17,
              minHeight: 17,
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: 4,
              vertical: 1,
            ),
            decoration: BoxDecoration(
              color: const Color(0xFFFF6554),
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Text(
              caseCount > 99 ? '99+' : '$caseCount',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 9,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
    ],
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
