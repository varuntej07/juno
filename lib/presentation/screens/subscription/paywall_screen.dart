import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/glass_card.dart';
import '../../../data/models/subscription_plan.dart';
import '../../viewmodels/subscription_viewmodel.dart';

enum _PlanToggle { free, premium }

enum _BillingPeriod { monthly, annual }

class PaywallScreen extends StatefulWidget {
  const PaywallScreen({super.key});

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  _PlanToggle _activePlan = _PlanToggle.premium;
  _BillingPeriod _billingPeriod = _BillingPeriod.annual;
  final PageController _togglePageController = PageController(initialPage: 1);

  @override
  void dispose() {
    _togglePageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pricing = _resolveLocalePricing(context);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AmbientBackground(
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: GlassIconButton(
                    icon: Icons.close_rounded,
                    onTap: () => Navigator.pop(context),
                    iconSize: 18,
                  ),
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 4, 24, 32),
                  child: Consumer<SubscriptionViewModel>(
                    builder: (context, vm, _) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            'Unlock Aura',
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 30,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -1,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            '14-day free trial. Cancel anytime.',
                            style: TextStyle(
                              color: AppColors.textTertiary,
                              fontSize: 14,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 24),

                          // Free / Premium toggle
                          _PlanToggleSwitch(
                            selected: _activePlan,
                            pageController: _togglePageController,
                            onChanged: (p) {
                              setState(() => _activePlan = p);
                              _togglePageController.animateToPage(
                                p == _PlanToggle.free ? 0 : 1,
                                duration: const Duration(milliseconds: 300),
                                curve: Curves.easeInOut,
                              );
                            },
                          ),
                          const SizedBox(height: 24),

                          // Feature list driven by the same PageController so
                          // swiping the content area updates the toggle pill too
                          SizedBox(
                            height: 350,
                            child: PageView(
                              controller: _togglePageController,
                              onPageChanged: (index) {
                                setState(() {
                                  _activePlan = index == 0
                                      ? _PlanToggle.free
                                      : _PlanToggle.premium;
                                });
                              },
                              children: const [
                                _FeatureList(plan: _PlanToggle.free),
                                _FeatureList(plan: _PlanToggle.premium),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),

                          // Side-by-side billing cards
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: _BillingCard(
                                  period: _BillingPeriod.monthly,
                                  selected: _billingPeriod == _BillingPeriod.monthly,
                                  enabled: _activePlan == _PlanToggle.premium,
                                  pricing: pricing,
                                  storePrice: vm.products
                                      .where((p) => p.id == SubscriptionProductIds.starterMonthly)
                                      .firstOrNull
                                      ?.price,
                                  onTap: _activePlan == _PlanToggle.premium
                                      ? () => setState(() => _billingPeriod = _BillingPeriod.monthly)
                                      : null,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _BillingCard(
                                  period: _BillingPeriod.annual,
                                  selected: _billingPeriod == _BillingPeriod.annual,
                                  enabled: _activePlan == _PlanToggle.premium,
                                  pricing: pricing,
                                  storePrice: vm.products
                                      .where((p) => p.id == SubscriptionProductIds.starterAnnual)
                                      .firstOrNull
                                      ?.price,
                                  onTap: _activePlan == _PlanToggle.premium
                                      ? () => setState(() => _billingPeriod = _BillingPeriod.annual)
                                      : null,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 28),

                          // CTA
                          if (_activePlan == _PlanToggle.premium) ...[
                            _CtaButton(
                              label: vm.isTrialActive
                                  ? 'Continue with ${_billingPeriod == _BillingPeriod.annual ? 'Yearly' : 'Monthly'}'
                                  : 'Start 14-day free trial',
                              isLoading: vm.isLoading,
                              onTap: () => _purchase(context, vm),
                            ),
                          ] else ...[
                            _GhostButton(
                              label: 'Continue with Free',
                              onTap: () => Navigator.pop(context),
                            ),
                          ],

                          if (vm.errorMessage != null) ...[
                            const SizedBox(height: 12),
                            Text(
                              vm.errorMessage!,
                              style: const TextStyle(
                                color: AppColors.error,
                                fontSize: 13,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],

                        ],
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _purchase(BuildContext context, SubscriptionViewModel vm) {
    vm.purchaseStarter(annual: _billingPeriod == _BillingPeriod.annual);
  }
}

// Locale-based fallback pricing

class _LocalePricing {
  final String symbol;
  final String monthly;
  final String annual;
  final String monthlyEquivalent;

  const _LocalePricing({
    required this.symbol,
    required this.monthly,
    required this.annual,
    required this.monthlyEquivalent,
  });
}

_LocalePricing _resolveLocalePricing(BuildContext context) {
  final locale = Localizations.maybeLocaleOf(context);
  final countryCode = locale?.countryCode ?? '';

  const euroCountries = {
    'DE', 'FR', 'IT', 'ES', 'NL', 'PT', 'BE', 'AT',
    'FI', 'IE', 'GR', 'SK', 'SI', 'LU', 'CY', 'EE', 'LV', 'LT', 'MT',
  };

  if (countryCode == 'IN') {
    return const _LocalePricing(
      symbol: '₹',
      monthly: '499',
      annual: '3,999',
      monthlyEquivalent: '333',
    );
  }
  if (euroCountries.contains(countryCode)) {
    return const _LocalePricing(
      symbol: '€',
      monthly: '4.99',
      annual: '39.99',
      monthlyEquivalent: '3.33',
    );
  }
  return const _LocalePricing(
    symbol: '\$',
    monthly: '4.99',
    annual: '39.99',
    monthlyEquivalent: '3.33',
  );
}

// Free / Premium toggle

class _PlanToggleSwitch extends StatelessWidget {
  final _PlanToggle selected;
  final PageController pageController;
  final ValueChanged<_PlanToggle> onChanged;

  const _PlanToggleSwitch({
    required this.selected,
    required this.pageController,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: AppColors.glassWhiteFill,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: AppColors.glassBorderDim),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          _ToggleSegment(
            label: 'Free',
            isSelected: selected == _PlanToggle.free,
            onTap: () => onChanged(_PlanToggle.free),
          ),
          _ToggleSegment(
            label: 'Premium',
            isSelected: selected == _PlanToggle.premium,
            onTap: () => onChanged(_PlanToggle.premium),
          ),
        ],
      ),
    );
  }
}

class _ToggleSegment extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _ToggleSegment({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: isSelected ? AppColors.accent : Colors.transparent,
            borderRadius: BorderRadius.circular(22),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? Colors.white : AppColors.textTertiary,
              fontSize: 15,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}

// Feature list

class _FeatureItem {
  final IconData icon;
  final String text;
  final bool included;

  const _FeatureItem({
    required this.icon,
    required this.text,
    required this.included,
  });
}

const _freeFeatureItems = [
  _FeatureItem(
    icon: Icons.chat_bubble_outline_rounded,
    text: '20 messages per day with Buddy',
    included: true,
  ),
  _FeatureItem(
    icon: Icons.notifications_outlined,
    text: 'Basic reminders',
    included: true,
  ),
  _FeatureItem(
    icon: Icons.history_rounded,
    text: '7-day chat history',
    included: true,
  ),
  _FeatureItem(
    icon: Icons.record_voice_over_outlined,
    text: 'Voice conversations with Buddy',
    included: false,
  ),
  _FeatureItem(
    icon: Icons.extension_outlined,
    text: 'Calendar, nutrition and more agents',
    included: false,
  ),
  _FeatureItem(
    icon: Icons.memory_rounded,
    text: 'Aura memory profile',
    included: false,
  ),
];

const _premiumFeatureItems = [
  _FeatureItem(
    icon: Icons.all_inclusive_rounded,
    text: 'Unlimited chat with Buddy',
    included: true,
  ),
  _FeatureItem(
    icon: Icons.extension_outlined,
    text: 'All agents unlocked',
    included: true,
  ),
  _FeatureItem(
    icon: Icons.record_voice_over_outlined,
    text: 'Natural voice conversations',
    included: true,
  ),
  _FeatureItem(
    icon: Icons.memory_rounded,
    text: 'Full Aura memory profile',
    included: true,
  ),
  _FeatureItem(
    icon: Icons.notifications_active_outlined,
    text: 'Proactive briefings and nudges',
    included: true,
  ),
  _FeatureItem(
    icon: Icons.history_rounded,
    text: 'Unlimited chat history',
    included: true,
  ),
];

class _FeatureList extends StatelessWidget {
  final _PlanToggle plan;

  const _FeatureList({required this.plan});

  @override
  Widget build(BuildContext context) {
    final items = plan == _PlanToggle.free ? _freeFeatureItems : _premiumFeatureItems;

    return FauxGlassCard(
      borderRadius: 18,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      child: Column(
        children: [
          for (int i = 0; i < items.length; i++) ...[
            if (i > 0)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Divider(
                  height: 1,
                  color: AppColors.glassBorderDim,
                ),
              ),
            _FeatureRow(item: items[i]),
          ],
        ],
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  final _FeatureItem item;

  const _FeatureRow({required this.item});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: item.included
                ? AppColors.accent.withValues(alpha: 0.12)
                : AppColors.glassWhiteFill,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(
            item.icon,
            color: item.included ? AppColors.accent : AppColors.textDisabled,
            size: 16,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            item.text,
            style: TextStyle(
              color: item.included ? AppColors.textSecondary : AppColors.textDisabled,
              fontSize: 14,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Icon(
          item.included ? Icons.check_rounded : Icons.lock_outline_rounded,
          color: item.included ? AppColors.accent : AppColors.textDisabled,
          size: 15,
        ),
      ],
    );
  }
}

// Billing cards

class _BillingCard extends StatelessWidget {
  final _BillingPeriod period;
  final bool selected;
  final bool enabled;
  final _LocalePricing pricing;
  final String? storePrice;
  final VoidCallback? onTap;

  const _BillingCard({
    required this.period,
    required this.selected,
    required this.enabled,
    required this.pricing,
    required this.onTap,
    this.storePrice,
  });

  @override
  Widget build(BuildContext context) {
    final isAnnual = period == _BillingPeriod.annual;
    final isActive = selected && enabled;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: enabled ? 1.0 : 0.38,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isActive
                  ? [
                      AppColors.accent.withValues(alpha: 0.20),
                      AppColors.accent.withValues(alpha: 0.08),
                    ]
                  : [
                      const Color(0x14FFFFFF),
                      const Color(0x08FFFFFF),
                    ],
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isActive
                  ? AppColors.accent.withValues(alpha: 0.6)
                  : AppColors.glassBorderDim,
              width: isActive ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    isAnnual ? 'Yearly' : 'Monthly',
                    style: TextStyle(
                      color: isActive ? AppColors.accent : AppColors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (isAnnual) ...[
                    const SizedBox(width: 5),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.accent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: const Text(
                        'Save 33%',
                        style: TextStyle(
                          color: AppColors.accent,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 10),
              if (isAnnual) ...[
                Text(
                  '${pricing.symbol}${pricing.monthly}/mo',
                  style: const TextStyle(
                    color: AppColors.textDisabled,
                    fontSize: 12,
                    decoration: TextDecoration.lineThrough,
                    decorationColor: AppColors.textDisabled,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${pricing.symbol}${pricing.monthlyEquivalent}/mo',
                  style: TextStyle(
                    color: isActive ? AppColors.accent : AppColors.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  storePrice != null
                      ? 'Billed $storePrice per year'
                      : 'Billed ${pricing.symbol}${pricing.annual} per year',
                  style: const TextStyle(
                    color: AppColors.textTertiary,
                    fontSize: 11,
                  ),
                ),
              ] else ...[
                Text(
                  storePrice != null
                      ? '$storePrice/mo'
                      : '${pricing.symbol}${pricing.monthly}/mo',
                  style: TextStyle(
                    color: isActive ? AppColors.accent : AppColors.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'billed monthly',
                  style: TextStyle(
                    color: AppColors.textTertiary,
                    fontSize: 11,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// CTA button

class _CtaButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool isLoading;

  const _CtaButton({
    required this.label,
    required this.onTap,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isLoading ? null : onTap,
      child: AnimatedOpacity(
        opacity: isLoading ? 0.6 : 1.0,
        duration: const Duration(milliseconds: 150),
        child: Container(
          height: 54,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [AppColors.accent, AppColors.accentDark],
            ),
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: AppColors.accent.withValues(alpha: 0.38),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Center(
            child: isLoading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                  )
                : Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

// Ghost button for Free plan

class _GhostButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _GhostButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 54,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: AppColors.glassBorderLight),
        ),
        child: Center(
          child: Text(
            label,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}
