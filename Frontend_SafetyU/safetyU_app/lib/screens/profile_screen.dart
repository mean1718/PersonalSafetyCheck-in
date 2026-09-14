import 'dart:io';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';
import '../widgets/app_bottom_nav.dart';
import '../widgets/responder_bottom_nav.dart';
import '../models/user_role.dart';
import '../services/app_session.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  // Index 3 in both nav bars is "Profile" — User (Home/Friends/History/
  // Profile) and Responder (Home/Case/Report/Profile) happen to share that
  // position, but everything they route to below is role-specific.
  final int _navIndex = 3;

  bool get _isResponder =>
      AppSession.instance.role == UserRole.emergencyResponder;

  void _onNavTap(int index) {
    if (index == _navIndex) return;
    if (_isResponder) {
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

  Future<void> _pickProfilePhoto() async {
    final hasPhoto = AppSession.instance.profilePhotoPath != null;
    final choice = await showModalBottomSheet<String>(
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
                child: Text('Update Profile Photo',
                    style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        color: AppColors.textPrimary)),
              ),
              ListTile(
                leading:
                    Icon(Icons.photo_camera_outlined, color: AppColors.navy),
                title: const Text('Take Photo'),
                onTap: () => Navigator.pop(context, 'camera'),
              ),
              ListTile(
                leading:
                    Icon(Icons.photo_library_outlined, color: AppColors.navy),
                title: const Text('Choose from Gallery'),
                onTap: () => Navigator.pop(context, 'gallery'),
              ),
              if (hasPhoto)
                ListTile(
                  leading: Icon(Icons.delete_outline, color: AppColors.danger),
                  title: Text('Remove Photo',
                      style: TextStyle(color: AppColors.danger)),
                  onTap: () => Navigator.pop(context, 'remove'),
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );

    if (choice == null) return;

    if (choice == 'remove') {
      setState(() => AppSession.instance.updateProfilePhoto(null));
      return;
    }

    final source =
        choice == 'camera' ? ImageSource.camera : ImageSource.gallery;
    try {
      final picked = await ImagePicker().pickImage(
        source: source,
        maxWidth: 800,
        imageQuality: 85,
      );
      if (picked == null || !mounted) return;
      // Evict any previously-cached image at this same path first — some
      // Android/iOS pickers reuse temp file paths, which would otherwise
      // make Flutter think "same image" and skip redrawing it.
      FileImage(File(picked.path)).evict();
      setState(() => AppSession.instance.updateProfilePhoto(picked.path));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                'Could not open ${choice == 'camera' ? 'camera' : 'gallery'}: $e')),
      );
    }
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
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.navy.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.settings, size: 18, color: AppColors.navy),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          children: [
            Row(
              children: [
                GestureDetector(
                  onTap: _pickProfilePhoto,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const LinearGradient(
                            colors: [Color(0xFF6C8DF7), Color(0xFFF7A8C4)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                        child: CircleAvatar(
                          radius: 28,
                          backgroundColor: AppColors.navy,
                          backgroundImage: session.profilePhotoPath != null
                              ? FileImage(File(session.profilePhotoPath!))
                              : null,
                          child: session.profilePhotoPath == null
                              ? Text(session.initials,
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700))
                              : null,
                        ),
                      ),
                      // Small camera badge — signals the avatar is tappable
                      // and lets you change the photo.
                      Positioned(
                        right: -2,
                        bottom: -2,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: AppColors.navy,
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: AppColors.background, width: 2),
                          ),
                          child: const Icon(Icons.camera_alt,
                              size: 12, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
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
                      if (_isResponder) ...[
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.navy.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            'Emergency Responder',
                            style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                color: AppColors.navy),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 28),
            _SectionLabel('General',
                icon: Icons.person, color: const Color(0xFF7B6EF6)),
            const SizedBox(height: 10),
            _SettingsCard(children: [
              _SwitchRow(
                label: 'Notifications and Sounds',
                subtitle: 'Manage alerts and notification sounds',
                icon: Icons.notifications,
                color: const Color(0xFFFF6B6B),
                value: session.notificationsEnabled,
                onChanged: (v) =>
                    setState(() => session.notificationsEnabled = v),
              ),
              _ValueRow(
                label: 'Language',
                subtitle: 'Choose your preferred language',
                icon: Icons.language,
                color: const Color(0xFF4A90E2),
                value: session.language,
                onTap: () => _pickOption(
                    'Language',
                    const ['English'],
                    session.language,
                    (v) => setState(() => session.language = v)),
              ),
              _ValueRow(
                label: 'Theme',
                subtitle: 'Choose your app theme',
                icon: Icons.water_drop,
                color: const Color(0xFF9B7FE8),
                value: session.themeName,
                onTap: () => _pickOption(
                    'Theme', const ['Light', 'Dark'], session.themeName, (v) {
                  setState(() => session.themeName = v);
                  ThemeController.instance.setDark(v == 'Dark');
                }),
              ),
            ]),
            const SizedBox(height: 20),
            _SectionLabel('Account',
                icon: Icons.shield, color: AppColors.success),
            const SizedBox(height: 10),
            _SettingsCard(children: [
              _NavRow(
                label: 'Personal Info',
                subtitle: 'View and edit your personal information',
                icon: Icons.person_outline,
                color: const Color(0xFF4A90E2),
                onTap: () => Navigator.pushNamed(context, '/personal-info'),
              ),
              _NavRow(
                label: 'Change Password',
                subtitle: 'Update your password',
                icon: Icons.lock_outline,
                color: const Color(0xFFD86EDB),
                onTap: () => Navigator.pushNamed(context, '/change-password'),
              ),
              _SwitchRow(
                label: 'Location',
                subtitle: 'Allow location access for better safety',
                icon: Icons.location_on,
                color: const Color(0xFFF5A623),
                value: session.locationSharingEnabled,
                onChanged: _toggleLocation,
              ),
            ]),
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
      bottomNavigationBar: _isResponder
          ? ResponderBottomNav(currentIndex: _navIndex, onTap: _onNavTap)
          : AppBottomNav(currentIndex: _navIndex, onTap: _onNavTap),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  final IconData icon;
  final Color color;
  const _SectionLabel(this.text, {required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 2),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: Icon(icon, size: 14, color: Colors.white),
          ),
          const SizedBox(width: 10),
          Text(
            text,
            style: TextStyle(
                fontSize: 15, fontWeight: FontWeight.w800, color: color),
          ),
        ],
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  final List<Widget> children;
  const _SettingsCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.6)),
      ),
      child: Column(
        children: [
          for (int i = 0; i < children.length; i++) ...[
            if (i > 0) Divider(height: 1, indent: 60, color: AppColors.border),
            children[i],
          ],
        ],
      ),
    );
  }
}

class _IconBadge extends StatelessWidget {
  final IconData icon;
  final Color color;
  const _IconBadge({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, size: 19, color: color),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  final String label;
  final String subtitle;
  final IconData icon;
  final Color color;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SwitchRow({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      child: Row(
        children: [
          _IconBadge(icon: icon, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        fontSize: 14,
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: TextStyle(
                        fontSize: 11.5, color: AppColors.textSecondary)),
              ],
            ),
          ),
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
  final String subtitle;
  final IconData icon;
  final Color color;
  final String value;
  final VoidCallback onTap;

  const _ValueRow({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        child: Row(
          children: [
            _IconBadge(icon: icon, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                          fontSize: 14,
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: TextStyle(
                          fontSize: 11.5, color: AppColors.textSecondary)),
                ],
              ),
            ),
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
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _NavRow({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        child: Row(
          children: [
            _IconBadge(icon: icon, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                          fontSize: 14,
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: TextStyle(
                          fontSize: 11.5, color: AppColors.textSecondary)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 18, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}
