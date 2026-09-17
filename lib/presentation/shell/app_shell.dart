import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_constants.dart';
import '../providers/classroom_providers.dart';
import '../screens/attendance_grid_screen.dart';
import '../screens/audit_log_screen.dart';
import '../screens/classrooms_screen.dart';
import '../screens/dashboard_screen.dart';
import '../screens/import_review_screen.dart';
import '../screens/reports_screen.dart';
import '../screens/support_screen.dart';

final selectedNavigationIndexProvider = StateProvider<int>((ref) => 0);

class AppShell extends ConsumerWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedNav = ref.watch(selectedNavigationIndexProvider);
    final classroomsAsync = ref.watch(classroomsProvider);
    final selectedClassroomId = ref.watch(selectedClassroomIdProvider);

    return Scaffold(
      body: Row(
        children: [
          // -----------------------------------------------------------
          // Desktop Left Sidebar (White-Dominant Minimalist)
          // -----------------------------------------------------------
          Container(
            width: 280,
            decoration: const BoxDecoration(
              color: AppColors.surface,
              border: Border(right: BorderSide(color: AppColors.borderSubtle)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. App Brand Header
                Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: AppColors.primaryLight,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
                        ),
                        child: const Icon(
                          Icons.fact_check_rounded,
                          color: AppColors.primary,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    AppConstants.appName,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.textPrimary,
                                      letterSpacing: -0.3,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppColors.surfaceMuted,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text(
                                    'v1.0',
                                    style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.textMuted,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const Text(
                              'Academic Edition',
                              style: TextStyle(
                                fontSize: 11,
                                color: AppColors.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const Divider(height: 1),

                // 2. Classroom Quick Switcher
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'ACTIVE CLASSROOM',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textMuted,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 6),
                      classroomsAsync.when(
                        data: (classrooms) {
                          if (classrooms.isEmpty) {
                            return const Text(
                              'No classes yet',
                              style: TextStyle(fontSize: 12, color: AppColors.textDisabled),
                            );
                          }
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceSubtle,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: AppColors.borderSubtle),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                isExpanded: true,
                                  value: (selectedClassroomId != null && classrooms.any((c) => c.id == selectedClassroomId))
                                      ? selectedClassroomId
                                      : (classrooms.isNotEmpty ? classrooms.first.id : null),
                                items: classrooms.map((c) {
                                  return DropdownMenuItem(
                                    value: c.id,
                                    child: Text(
                                      '${c.courseCode} (${c.section})',
                                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  );
                                }).toList(),
                                onChanged: (val) {
                                  if (val != null) {
                                    ref.read(selectedClassroomIdProvider.notifier).state = val;
                                  }
                                },
                              ),
                            ),
                          );
                        },
                        loading: () => const LinearProgressIndicator(minHeight: 2),
                        error: (_, _) => const Text('Error loading classes', style: TextStyle(fontSize: 11)),
                      ),
                    ],
                  ),
                ),

                const Divider(height: 1),

                // 3. Navigation Links
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                    children: [
                      _navItem(
                        context: context,
                        ref: ref,
                        index: 0,
                        currentIndex: selectedNav,
                        icon: Icons.space_dashboard_outlined,
                        activeIcon: Icons.space_dashboard,
                        label: 'Dashboard',
                      ),
                      _navItem(
                        context: context,
                        ref: ref,
                        index: 1,
                        currentIndex: selectedNav,
                        icon: Icons.school_outlined,
                        activeIcon: Icons.school,
                        label: 'Classrooms & Rosters',
                      ),
                      _navItem(
                        context: context,
                        ref: ref,
                        index: 2,
                        currentIndex: selectedNav,
                        icon: Icons.grid_on_outlined,
                        activeIcon: Icons.grid_on,
                        label: 'Take Attendance',
                        badge: 'Keyboard',
                      ),
                      _navItem(
                        context: context,
                        ref: ref,
                        index: 3,
                        currentIndex: selectedNav,
                        icon: Icons.document_scanner_outlined,
                        activeIcon: Icons.document_scanner,
                        label: 'Import & Verification',
                        badge: 'AI',
                      ),
                      _navItem(
                        context: context,
                        ref: ref,
                        index: 4,
                        currentIndex: selectedNav,
                        icon: Icons.bar_chart_outlined,
                        activeIcon: Icons.bar_chart,
                        label: 'Reports & Exports',
                      ),
                      _navItem(
                        context: context,
                        ref: ref,
                        index: 5,
                        currentIndex: selectedNav,
                        icon: Icons.history_edu_outlined,
                        activeIcon: Icons.history_edu,
                        label: 'Audit Trail',
                      ),
                      _navItem(
                        context: context,
                        ref: ref,
                        index: 6,
                        currentIndex: selectedNav,
                        icon: Icons.settings_outlined,
                        activeIcon: Icons.settings,
                        label: 'Settings & Cloud Backup',
                        onTapOverride: () {
                          showDialog(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              title: const Row(
                                children: [
                                  Icon(Icons.hourglass_top_rounded, color: AppColors.primary),
                                  SizedBox(width: 8),
                                  Text('Module Coming Soon', style: TextStyle(fontWeight: FontWeight.w700)),
                                ],
                              ),
                              content: const Text(
                                'This module will come soon.\nSettings & Cloud Backup is currently under development and will be available in an upcoming release.',
                                style: TextStyle(fontSize: 13, height: 1.5, color: AppColors.textPrimary),
                              ),
                              actions: [
                                ElevatedButton(
                                  onPressed: () => Navigator.pop(ctx),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.primary,
                                    foregroundColor: Colors.white,
                                  ),
                                  child: const Text('OK'),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                      _navItem(
                        context: context,
                        ref: ref,
                        index: 7,
                        currentIndex: selectedNav,
                        icon: Icons.headset_mic_outlined,
                        activeIcon: Icons.headset_mic_rounded,
                        label: 'Support & Help',
                      ),
                    ],
                  ),
                ),

                // 4. System Status & Offline Authoritative Indicator
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: const BoxDecoration(
                    color: AppColors.surfaceSubtle,
                    border: Border(top: BorderSide(color: AppColors.borderSubtle)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: AppColors.present,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'SQLite WAL Active',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            Text(
                              'Local Authoritative Engine',
                              style: TextStyle(
                                fontSize: 10,
                                color: AppColors.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.shield_outlined, size: 16, color: AppColors.present),
                    ],
                  ),
                ),

                // 5. Vendor Attribution
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  child: Row(
                    children: [
                      const Text(
                        'Powered by ',
                        style: TextStyle(fontSize: 10, color: AppColors.textMuted),
                      ),
                      const Text(
                        'Alldotdev',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                        ),
                      ),
                      const Spacer(),
                      InkWell(
                        onTap: () => ref.read(selectedNavigationIndexProvider.notifier).state = 7,
                        child: const Text(
                          'Help Desk',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // -----------------------------------------------------------
          // Main Screen Content Area
          // -----------------------------------------------------------
          Expanded(
            child: _buildCurrentScreen(selectedNav),
          ),
        ],
      ),
    );
  }

  Widget _navItem({
    required BuildContext context,
    required WidgetRef ref,
    required int index,
    required int currentIndex,
    required IconData icon,
    required IconData activeIcon,
    required String label,
    String? badge,
    VoidCallback? onTapOverride,
  }) {
    final isSelected = index == currentIndex;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Material(
        color: isSelected ? AppColors.primaryLight : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: onTapOverride ?? () => ref.read(selectedNavigationIndexProvider.notifier).state = index,
          hoverColor: AppColors.surfaceHover,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            child: Row(
              children: [
                Icon(
                  isSelected ? activeIcon : icon,
                  size: 18,
                  color: isSelected ? AppColors.primary : AppColors.textSecondary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                      color: isSelected ? AppColors.primary : AppColors.textPrimary,
                    ),
                  ),
                ),
                if (badge != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: isSelected ? AppColors.primary : AppColors.surfaceMuted,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      badge,
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                        color: isSelected ? AppColors.textOnAccent : AppColors.textMuted,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCurrentScreen(int index) {
    switch (index) {
      case 0:
        return const DashboardScreen();
      case 1:
        return const ClassroomsScreen();
      case 2:
        return const AttendanceGridScreen();
      case 3:
        return const ImportReviewScreen();
      case 4:
        return const ReportsScreen();
      case 5:
        return const AuditLogScreen();
      case 6:
        return const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.hourglass_top_rounded, size: 48, color: AppColors.primary),
              SizedBox(height: 12),
              Text(
                'This module will come soon.',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        );
      case 7:
        return const SupportScreen();
      default:
        return const DashboardScreen();
    }
  }
}
