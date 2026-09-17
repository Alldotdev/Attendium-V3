import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/constants/app_brand_assets.dart';
import '../../core/constants/app_colors.dart';

/// Clean, modern, non-editable customer support and technical assistance screen.
/// Vendor: Alldotdev
class SupportScreen extends StatelessWidget {
  const SupportScreen({super.key});

  static const String companyName = 'Alldotdev';
  static const String phoneNumber = '03420554448';
  static const String phoneFormatted = '+92 342 0554448';
  static const String supportEmail = 'alldotdev1@gmail.com';
  static const String officialWebsite = 'www.alldotdev.com';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Page Title & Description
            const Text(
              'Support & Assistance',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Official customer service, technical diagnostics, and system maintenance desk.',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 24),

            // 2. Company Hero Card
            _buildCompanyHeroCard(context),
            const SizedBox(height: 24),

            // 3. Grid of Contact & Technical Support Details
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Left Column: Contact Channels
                Expanded(
                  flex: 5,
                  child: Column(
                    children: [
                      _buildContactTile(
                        context: context,
                        icon: Icons.phone_in_talk_rounded,
                        accentColor: AppColors.primary,
                        title: 'Technical Support & Hotline',
                        primaryValue: phoneNumber,
                        subtitle: 'Direct Helpline / WhatsApp: $phoneFormatted',
                        badge: 'Priority Support',
                        copyValue: phoneNumber,
                      ),
                      const SizedBox(height: 16),
                      _buildContactTile(
                        context: context,
                        icon: Icons.alternate_email_rounded,
                        accentColor: AppColors.alldotdevMagenta,
                        title: 'Official Email Desk',
                        primaryValue: supportEmail,
                        subtitle: 'Send diagnostics, logs, or general inquiries.',
                        badge: '24h SLA',
                        copyValue: supportEmail,
                      ),
                      const SizedBox(height: 16),
                      _buildContactTile(
                        context: context,
                        icon: Icons.language_rounded,
                        accentColor: AppColors.excused,
                        title: 'Corporate Web Portal',
                        primaryValue: officialWebsite,
                        subtitle: 'Product releases, guides, and corporate resources.',
                        copyValue: officialWebsite,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 20),

                // Right Column: Operating Hours & System Verification
                Expanded(
                  flex: 4,
                  child: Column(
                    children: [
                      _buildHoursCard(),
                      const SizedBox(height: 16),
                      _buildSystemLicenseCard(),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompanyHeroCard(BuildContext context) {
    final Widget logoWidget = AppBrandAssets.getLogoWidget(height: 52);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderMedium),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surfaceSubtle,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.borderSubtle),
            ),
            child: logoWidget,
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      companyName,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.primaryLight,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        'Authorized Software Vendor',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  'Custom Enterprise Engineering, Academic Automation, and Intelligent Cloud Solutions.',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContactTile({
    required BuildContext context,
    required IconData icon,
    required Color accentColor,
    required String title,
    required String primaryValue,
    required String subtitle,
    String? badge,
    required String copyValue,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: accentColor, size: 22),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textMuted,
                      ),
                    ),
                    if (badge != null) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: AppColors.presentLight,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          badge,
                          style: const TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: AppColors.presentDark,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                SelectableText(
                  primaryValue,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.copy_rounded, size: 18, color: AppColors.textMuted),
            tooltip: 'Copy to clipboard',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: copyValue));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Copied "$copyValue" to clipboard'),
                  backgroundColor: AppColors.primary,
                  duration: const Duration(seconds: 2),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildHoursCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.schedule_rounded, size: 18, color: AppColors.primary),
              SizedBox(width: 8),
              Text(
                'Support Desk Hours',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _infoRow('Monday – Friday', '9:00 AM – 6:00 PM PKT'),
          const SizedBox(height: 6),
          _infoRow('Saturday', '10:00 AM – 3:00 PM PKT'),
          const SizedBox(height: 6),
          _infoRow('Sunday', 'Closed (Emergency On-Call)'),
          const Divider(height: 20),
          Row(
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
              const Text(
                'System Status: All Services Operational',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.presentDark,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSystemLicenseCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surfaceSubtle,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.verified_outlined, size: 18, color: AppColors.textSecondary),
              SizedBox(width: 8),
              Text(
                'License & Environment Information',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _infoRow('Application', 'Attendium Desktop'),
          const SizedBox(height: 4),
          _infoRow('Edition', 'Academic v1.0.0'),
          const SizedBox(height: 4),
          _infoRow('Database Engine', 'Local SQLite 3.45 (WAL Mode)'),
          const SizedBox(height: 4),
          _infoRow('Security', 'Encrypted Credentials Storage'),
          const SizedBox(height: 4),
          _infoRow('Vendor / Author', companyName),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
        Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
      ],
    );
  }
}
