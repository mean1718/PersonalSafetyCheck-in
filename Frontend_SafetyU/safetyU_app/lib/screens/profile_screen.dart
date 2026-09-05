import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';
import '../widgets/app_bottom_nav.dart';
import '../widgets/responder_bottom_nav.dart';
import '../services/app_session.dart';
import '../models/user_role.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final int _navIndex = 3;

  void _onNavTap(int index) {
    if (index == _navIndex) return;
    final isResponder = AppSession.instance.role == UserRole.emergencyResponder;
    if (isResponder) {
      switch (index) {
        case 0:
          Navigator.pushReplacementNamed(context, '/emergency-home');
          break;
        case 1:
          Navigator.pushReplacementNamed(context, '/cases');
          break;
        case 2:
          Navigator.pushReplacementNamed(context, '/reports');
          break;
      }
      return;
    }
    switch (index) {
      case 0:
        Navigator.pushReplacementNamed(context, '/home');
        break;
      case 1:
        Navigator.pushReplacementNamed(context, '/contacts');
        break;
      case 2:
        Navigator.pushReplacementNamed(context, '/history');
        break;
    }
  }

  Future<void> _toggleLocation(bool value) async {
    if (value) {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        final requested = await Geolocator.requestPermission();
        if (requested == LocationPermission.denied ||
            requested == LocationPermission.deniedForever) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Location permission was not granted.')),
          );
          setState(() {});
          return;
        }
      }
    }
    setState(() => AppSession.instance.locationSharingEnabled = value);
  }

  Future<void> _pickOption(String title, List<String> options, String current,
      ValueChanged<String> onSelected) async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 15)),
              ),
              ...options.map(
                (o) => ListTile(
                  title: Text(o),
                  trailing: o == current
                      ? Icon(Icons.check, color: AppColors.navy)
                      : null,
                  onTap: () => Navigator.pop(context, o),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
    if (selected != null) onSelected(selected);
  }

  void _logout() {
    AppSession.instance.signOut();
    Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    final session = AppSession.instance;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
        automaticallyImplyLeading: false,
        title: const Text('Setting',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: AppColors.navy,
                  child: Text(session.initials,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w700)),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        session.fullName.isEmpty ? 'Member' : session.fullName,
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary),
                      ),
                      Text(session.email,
                          style: TextStyle(
                              fontSize: 12.5, color: AppColors.textSecondary)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 28),
            const _SectionLabel('General'),
            _SwitchRow(
              label: 'Notifications and Sounds',
              value: session.notificationsEnabled,
              onChanged: (v) =>
                  setState(() => session.notificationsEnabled = v),
            ),
            _ValueRow(
              label: 'Language',
              value: session.language,
              onTap: () => _pickOption(
                  'Language',
                  const ['English', 'Khmer'],
                  session.language,
                  (v) => setState(() => session.language = v)),
            ),
            _ValueRow(
              label: 'Theme',
              value: session.themeName,
              onTap: () => _pickOption(
                  'Theme', const ['Light', 'Dark'], session.themeName, (v) {
                setState(() => session.themeName = v);
                ThemeController.instance.setDark(v == 'Dark');
              }),
            ),
            const SizedBox(height: 20),
            const _SectionLabel('Account'),
            _NavRow(
                label: 'Personal Info',
                onTap: () => Navigator.pushNamed(context, '/personal-info')),
            _NavRow(
                label: 'Change Password',
                onTap: () => Navigator.pushNamed(context, '/change-password')),
            _SwitchRow(
              label: 'Location',
              value: session.locationSharingEnabled,
              onChanged: _toggleLocation,
            ),
            const SizedBox(height: 20),
            if (session.role == UserRole.emergencyResponder) ...[
              const _SectionLabel('Officer Info'),
              _ValueRow(
                  label: 'Badge / Officer ID',
                  value: session.badgeId.isEmpty ? '—' : session.badgeId,
                  onTap: () {}),
              _ValueRow(
                  label: 'Verification',
                  value: session.responderStatus.name == 'verified'
                      ? 'Verified'
                      : 'Pending',
                  onTap: () {}),
            ] else ...[
              const _SectionLabel('Trust Mode'),
              _SwitchRow(
                label: 'Your availability to help',
                value: session.availableToHelp,
                onChanged: (v) => setState(() => session.availableToHelp = v),
              ),
            ],
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _logout,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF6554),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(26)),
                ),
                child: const Text('Log Out',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: session.role == UserRole.emergencyResponder
          ? ResponderBottomNav(currentIndex: _navIndex, onTap: _onNavTap)
          : AppBottomNav(currentIndex: _navIndex, onTap: _onNavTap),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: AppColors.textMuted,
            letterSpacing: 0.6),
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SwitchRow(
      {required this.label, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Expanded(
              child: Text(label,
                  style: TextStyle(
                      fontSize: 14,
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600))),
          Switch(
              value: value,
              onChanged: onChanged,
              activeColor: AppColors.success),
        ],
      ),
    );
  }
}

class _ValueRow extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onTap;

  const _ValueRow(
      {required this.label, required this.value, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Expanded(
                child: Text(label,
                    style: TextStyle(
                        fontSize: 14,
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600))),
            Text(value,
                style:
                    TextStyle(fontSize: 13.5, color: AppColors.textSecondary)),
            const SizedBox(width: 6),
            Icon(Icons.chevron_right, size: 18, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}

class _NavRow extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _NavRow({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Expanded(
                child: Text(label,
                    style: TextStyle(
                        fontSize: 14,
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600))),
            Icon(Icons.chevron_right, size: 18, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}
