import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/models/connector_models.dart';
import '../../viewmodels/connectors_viewmodel.dart';
import '../../viewmodels/dietary_profile_viewmodel.dart';
import '../../viewmodels/nutrition_scan_viewmodel.dart';
import '../../widgets/error_display.dart';
import '../../widgets/loading_indicator.dart';
import '../nutrition/dietary_onboarding_screen.dart';
import '../nutrition/nutrition_scan_screen.dart';

class AgentsScreen extends StatefulWidget {
  const AgentsScreen({super.key});

  @override
  State<AgentsScreen> createState() => _AgentsScreenState();
}

class _AgentsScreenState extends State<AgentsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ConnectorsViewModel>().load();
      context.read<DietaryProfileViewModel>().load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        title: const Text(
          'Agents',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
      ),
      body: Consumer2<ConnectorsViewModel, DietaryProfileViewModel>(
        builder: (context, connectorsVm, profileVm, _) {
          final loading = connectorsVm.state == ViewState.loading &&
              !connectorsVm.googleCalendar.enabled;

          if (loading) {
            return const FullScreenLoader(message: 'Loading agents…');
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (connectorsVm.error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: ErrorDisplay(
                    error: connectorsVm.error!,
                    onDismiss: connectorsVm.clearError,
                  ),
                ),
              if (profileVm.error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: ErrorDisplay(
                    error: profileVm.error!,
                    onDismiss: profileVm.clearError,
                  ),
                ),

              // ── Nutrition Agent ────────────────────────────────────────────
              _NutritionAgentCard(
                profileVm: profileVm,
                onScanTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const NutritionScanScreen(),
                  ),
                ),
                onEnableToggle: (enabled) async {
                  if (enabled) {
                    // Show onboarding to collect dietary profile
                    final ok = await DietaryOnboardingScreen.show(context);
                    if (!ok && mounted) {
                      profileVm.disableNutritionAgent();
                    }
                  } else {
                    profileVm.disableNutritionAgent();
                  }
                },
                onEditProfile: () async {
                  await DietaryOnboardingScreen.show(context);
                },
              ),

              const SizedBox(height: 16),

              // ── Google Calendar ────────────────────────────────────────────
              _GoogleCalendarCard(
                status: connectorsVm.googleCalendar,
                busy: connectorsVm.isMutating,
                onToggle: connectorsVm.toggleGoogleCalendar,
                onSync: connectorsVm.syncGoogleCalendar,
              ),

              const SizedBox(height: 32),

              // Coming soon placeholder
              Center(
                child: Text(
                  'More agents coming soon',
                  style: TextStyle(
                    color: AppColors.textTertiary,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ─── Nutrition Agent Card ─────────────────────────────────────────────────────

class _NutritionAgentCard extends StatelessWidget {
  final DietaryProfileViewModel profileVm;
  final VoidCallback onScanTap;
  final void Function(bool) onEnableToggle;
  final VoidCallback onEditProfile;

  const _NutritionAgentCard({
    required this.profileVm,
    required this.onScanTap,
    required this.onEnableToggle,
    required this.onEditProfile,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = profileVm.nutritionAgentEnabled;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: enabled
              ? AppColors.accent.withValues(alpha: 0.4)
              : AppColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Tappable avatar → scanner
              GestureDetector(
                onTap: enabled ? onScanTap : null,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: enabled
                        ? AppColors.accent.withValues(alpha: 0.15)
                        : AppColors.surfaceVariant,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: enabled
                          ? AppColors.accent.withValues(alpha: 0.5)
                          : AppColors.border,
                    ),
                  ),
                  child: Icon(
                    Icons.camera_alt_rounded,
                    color: enabled ? AppColors.accent : AppColors.textTertiary,
                    size: 26,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Nutrition Agent',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      enabled
                          ? 'Tap the camera to scan food'
                          : 'Enable to scan food & get diet advice',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: enabled,
                onChanged: profileVm.state == ViewState.loading ? null : onEnableToggle,
                activeThumbColor: AppColors.accent,
              ),
            ],
          ),
          if (enabled && profileVm.hasProfile) ...[
            const SizedBox(height: 16),
            const Divider(color: AppColors.divider, height: 1),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Dietary profile set up',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                ),
                GestureDetector(
                  onTap: onEditProfile,
                  child: const Text(
                    'Edit Profile',
                    style: TextStyle(
                      color: AppColors.accent,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Google Calendar Card (moved from ConnectorsScreen) ───────────────────────

class _GoogleCalendarCard extends StatelessWidget {
  final GoogleCalendarConnectorStatus status;
  final bool busy;
  final Future<void> Function(bool enabled) onToggle;
  final Future<void> Function() onSync;

  const _GoogleCalendarCard({
    required this.status,
    required this.busy,
    required this.onToggle,
    required this.onSync,
  });

  @override
  Widget build(BuildContext context) {
    final syncLabel = _formatDateTime(status.lastSyncedAt);
    final watchLabel = _formatDateTime(status.watchExpiresAt);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.calendar_month_rounded,
                  color: Color(0xFF1A73E8),
                ),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Google Calendar',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Sync meetings into Juno for chat answers.',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: status.enabled,
                onChanged: busy ? null : onToggle,
                activeThumbColor: AppColors.accent,
              ),
            ],
          ),
          const SizedBox(height: 16),
          _MetaRow(label: 'Calendar', value: status.calendarName),
          _MetaRow(label: 'Last Sync', value: syncLabel ?? 'Not synced yet'),
          _MetaRow(
            label: 'Auto Sync',
            value: status.watchActive
                ? 'Webhook active'
                : status.enabled
                    ? 'Connected, waiting for public HTTPS webhook'
                    : 'Disconnected',
          ),
          if (status.calendarTimeZone != null)
            _MetaRow(label: 'Timezone', value: status.calendarTimeZone!),
          if (watchLabel != null)
            _MetaRow(label: 'Watch Expires', value: watchLabel),
          if (status.pendingSync)
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: Text(
                'A calendar update is queued and will be processed shortly.',
                style: TextStyle(color: AppColors.warning, fontSize: 12),
              ),
            ),
          if (status.lastError != null && status.lastError!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                status.lastError!,
                style: const TextStyle(color: AppColors.warning, fontSize: 12),
              ),
            ),
          if (status.enabled) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: busy ? null : onSync,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textPrimary,
                  side: const BorderSide(color: AppColors.border),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Sync Now'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String? _formatDateTime(DateTime? value) {
    if (value == null) return null;
    return DateFormat('MMM d, h:mm a').format(value.toLocal());
  }
}

class _MetaRow extends StatelessWidget {
  final String label;
  final String value;

  const _MetaRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          SizedBox(
            width: 96,
            child: Text(label,
                style: const TextStyle(color: AppColors.textTertiary, fontSize: 12)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}
