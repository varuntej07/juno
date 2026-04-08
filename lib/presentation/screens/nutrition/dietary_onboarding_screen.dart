import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/models/dietary_profile_model.dart';
import '../../viewmodels/dietary_profile_viewmodel.dart';

class DietaryOnboardingScreen extends StatefulWidget {
  const DietaryOnboardingScreen({super.key});

  /// Push and return true if profile was saved successfully.
  static Future<bool> show(BuildContext context) async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const DietaryOnboardingScreen(),
      ),
    );
    return result ?? false;
  }

  @override
  State<DietaryOnboardingScreen> createState() => _DietaryOnboardingScreenState();
}

class _DietaryOnboardingScreenState extends State<DietaryOnboardingScreen> {
  int _step = 0;
  bool _saving = false;

  // Accumulated answers
  int? _age;
  String? _gender;
  double _heightCm = 170;
  double _weightKg = 70;
  String? _goal;
  String? _activityLevel;
  String? _workoutDuration;
  final Set<String> _restrictions = {};
  final Set<String> _allergies = {};
  double? _fatPct;
  bool _useMetric = true;

  static const _totalSteps = 8;

  void _next() {
    if (_step < _totalSteps - 1) {
      setState(() => _step++);
    } else {
      _save();
    }
  }

  void _prev() {
    if (_step > 0) setState(() => _step--);
  }

  Future<void> _save() async {
    final workoutMin = switch (_workoutDuration) {
      '<30 min' => 20,
      '30-60 min' => 45,
      '60-90 min' => 75,
      '90 min+' => 100,
      _ => null,
    };

    final profile = DietaryProfileModel(
      age: _age,
      gender: _gender,
      heightCm: _heightCm,
      weightKg: _weightKg,
      goal: _goal,
      activityLevel: _activityLevel,
      workoutMinPerDay: workoutMin,
      restrictions: _restrictions.toList(),
      allergies: _allergies.toList(),
      fatPct: _fatPct,
    );

    if (!mounted) return;
    setState(() => _saving = true);
    final vm = context.read<DietaryProfileViewModel>();
    final ok = await vm.saveProfile(profile);
    if (mounted) Navigator.of(context).pop(ok);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        leading: _step > 0
            ? IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: _prev,
              )
            : null,
        title: Text(
          'Step ${_step + 1} of $_totalSteps',
          style: const TextStyle(color: AppColors.textTertiary, fontSize: 14),
        ),
      ),
      body: Column(
        children: [
          // Progress bar
          LinearProgressIndicator(
            value: (_step + 1) / _totalSteps,
            backgroundColor: AppColors.surface,
            color: AppColors.accent,
            minHeight: 3,
          ),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: KeyedSubtree(
                key: ValueKey(_step),
                child: _buildStep(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStep() {
    return switch (_step) {
      0 => _AgeStep(
          value: _age,
          onChange: (v) => setState(() => _age = v),
          onNext: _next,
        ),
      1 => _SelectStep(
          title: 'Biological sex?',
          options: const ['Male', 'Female', 'Prefer not to say'],
          selected: _gender,
          onSelect: (v) => setState(() => _gender = v),
          onNext: _next,
        ),
      2 => _HeightWeightStep(
          heightCm: _heightCm,
          weightKg: _weightKg,
          useMetric: _useMetric,
          onHeightChanged: (v) => setState(() => _heightCm = v),
          onWeightChanged: (v) => setState(() => _weightKg = v),
          onUnitToggle: (v) => setState(() => _useMetric = v),
          onNext: _next,
        ),
      3 => _SelectStep(
          title: "What's your goal?",
          options: const ['Lose weight', 'Maintain', 'Build muscle', 'Eat healthier'],
          selected: _goal,
          onSelect: (v) => setState(() => _goal = v),
          onNext: _next,
        ),
      4 => _SelectStep(
          title: 'Activity level?',
          options: const [
            'Sedentary (desk job)',
            'Light (1-3x/week)',
            'Moderate (3-5x/week)',
            'Very active (6-7x/week)',
          ],
          selected: _activityLevel,
          onSelect: (v) => setState(() => _activityLevel = v),
          onNext: _next,
        ),
      5 => _SelectStep(
          title: 'Workout duration per session?',
          options: const ['<30 min', '30-60 min', '60-90 min', '90 min+', 'I don\'t workout'],
          selected: _workoutDuration,
          onSelect: (v) => setState(() => _workoutDuration = v),
          onNext: _next,
        ),
      6 => _MultiSelectStep(
          title: 'Dietary restrictions?',
          subtitle: 'Select all that apply',
          options: const ['Vegan', 'Vegetarian', 'Keto', 'Paleo', 'Gluten-free', 'Dairy-free', 'None'],
          selected: _restrictions,
          onToggle: (v) {
            setState(() {
              if (v == 'None') {
                _restrictions
                  ..clear()
                  ..add('None');
              } else {
                _restrictions.remove('None');
                if (_restrictions.contains(v)) {
                  _restrictions.remove(v);
                } else {
                  _restrictions.add(v);
                }
              }
            });
          },
          onNext: _next,
        ),
      7 => _AllergiesStep(
          allergies: _allergies,
          fatPct: _fatPct,
          saving: _saving,
          onAllergyToggle: (v) {
            setState(() {
              if (_allergies.contains(v)) {
                _allergies.remove(v);
              } else {
                _allergies.add(v);
              }
            });
          },
          onFatPctChanged: (v) => setState(() => _fatPct = v),
          onSave: _save,
        ),
      _ => const SizedBox.shrink(),
    };
  }
}

// ─── Step widgets ─────────────────────────────────────────────────────────────

class _StepShell extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;
  final VoidCallback? onNext;
  final String nextLabel;
  final bool canSkip;
  final VoidCallback? onSkip;
  final bool isSaving;

  const _StepShell({
    required this.title,
    this.subtitle,
    required this.child,
    this.onNext,
    this.nextLabel = 'Next',
    this.canSkip = false,
    this.onSkip,
    this.isSaving = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 24,
              fontWeight: FontWeight.w700,
              height: 1.3,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 8),
            Text(subtitle!,
                style: const TextStyle(color: AppColors.textTertiary, fontSize: 14)),
          ],
          const SizedBox(height: 32),
          Expanded(child: child),
          Row(
            children: [
              if (canSkip)
                TextButton(
                  onPressed: onSkip,
                  child: const Text('Skip',
                      style: TextStyle(color: AppColors.textTertiary)),
                ),
              if (canSkip) const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: onNext,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: isSaving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          nextLabel,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// Age
class _AgeStep extends StatefulWidget {
  final int? value;
  final void Function(int) onChange;
  final VoidCallback onNext;

  const _AgeStep({required this.value, required this.onChange, required this.onNext});

  @override
  State<_AgeStep> createState() => _AgeStepState();
}

class _AgeStepState extends State<_AgeStep> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.value?.toString() ?? '');
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _StepShell(
      title: 'How old are you?',
      onNext: () {
        final v = int.tryParse(_ctrl.text.trim());
        if (v != null && v > 0 && v < 120) {
          widget.onChange(v);
          widget.onNext();
        }
      },
      canSkip: true,
      onSkip: widget.onNext,
      child: TextField(
        controller: _ctrl,
        keyboardType: TextInputType.number,
        autofocus: true,
        style: const TextStyle(color: AppColors.textPrimary, fontSize: 32, fontWeight: FontWeight.w700),
        decoration: const InputDecoration(
          hintText: '25',
          hintStyle: TextStyle(color: AppColors.textTertiary, fontSize: 32),
          border: InputBorder.none,
          suffix: Text('years', style: TextStyle(color: AppColors.textTertiary, fontSize: 18)),
        ),
      ),
    );
  }
}

// Single select
class _SelectStep extends StatelessWidget {
  final String title;
  final List<String> options;
  final String? selected;
  final void Function(String) onSelect;
  final VoidCallback onNext;

  const _SelectStep({
    required this.title,
    required this.options,
    required this.selected,
    required this.onSelect,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return _StepShell(
      title: title,
      onNext: selected != null ? onNext : null,
      canSkip: true,
      onSkip: onNext,
      child: ListView(
        children: options
            .map(
              (opt) => GestureDetector(
                onTap: () => onSelect(opt),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: selected == opt
                        ? AppColors.accent.withValues(alpha: 0.15)
                        : AppColors.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: selected == opt ? AppColors.accent : AppColors.border,
                      width: selected == opt ? 2 : 1,
                    ),
                  ),
                  child: Text(
                    opt,
                    style: TextStyle(
                      color: selected == opt ? AppColors.accent : AppColors.textPrimary,
                      fontSize: 16,
                      fontWeight: selected == opt ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

// Height + Weight
class _HeightWeightStep extends StatelessWidget {
  final double heightCm;
  final double weightKg;
  final bool useMetric;
  final void Function(double) onHeightChanged;
  final void Function(double) onWeightChanged;
  final void Function(bool) onUnitToggle;
  final VoidCallback onNext;

  const _HeightWeightStep({
    required this.heightCm,
    required this.weightKg,
    required this.useMetric,
    required this.onHeightChanged,
    required this.onWeightChanged,
    required this.onUnitToggle,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final heightDisplay = useMetric
        ? '${heightCm.round()} cm'
        : '${(heightCm / 30.48).toStringAsFixed(1)} ft';
    final weightDisplay = useMetric
        ? '${weightKg.round()} kg'
        : '${(weightKg * 2.20462).round()} lbs';

    return _StepShell(
      title: 'Height & Weight',
      onNext: onNext,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Unit toggle
          Row(
            children: [
              _UnitToggleBtn(label: 'Metric', selected: useMetric, onTap: () => onUnitToggle(true)),
              const SizedBox(width: 10),
              _UnitToggleBtn(label: 'Imperial', selected: !useMetric, onTap: () => onUnitToggle(false)),
            ],
          ),
          const SizedBox(height: 32),
          Text('Height: $heightDisplay',
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Slider(
            value: heightCm.clamp(100, 250),
            min: 100,
            max: 250,
            divisions: 150,
            activeColor: AppColors.accent,
            inactiveColor: AppColors.surface,
            onChanged: onHeightChanged,
          ),
          const SizedBox(height: 24),
          Text('Weight: $weightDisplay',
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Slider(
            value: weightKg.clamp(30, 200),
            min: 30,
            max: 200,
            divisions: 170,
            activeColor: AppColors.accent,
            inactiveColor: AppColors.surface,
            onChanged: onWeightChanged,
          ),
        ],
      ),
    );
  }
}

class _UnitToggleBtn extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _UnitToggleBtn({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppColors.accent : AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? AppColors.accent : AppColors.border),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : AppColors.textPrimary,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

// Multi select
class _MultiSelectStep extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<String> options;
  final Set<String> selected;
  final void Function(String) onToggle;
  final VoidCallback onNext;

  const _MultiSelectStep({
    required this.title,
    this.subtitle,
    required this.options,
    required this.selected,
    required this.onToggle,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return _StepShell(
      title: title,
      subtitle: subtitle,
      onNext: onNext,
      canSkip: true,
      onSkip: onNext,
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: options.map((opt) {
          final isSelected = selected.contains(opt);
          return GestureDetector(
            onTap: () => onToggle(opt),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              decoration: BoxDecoration(
                color: isSelected ? AppColors.accent : AppColors.surface,
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: isSelected ? AppColors.accent : AppColors.border),
              ),
              child: Text(
                opt,
                style: TextStyle(
                  color: isSelected ? Colors.white : AppColors.textPrimary,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// Allergies + optional fat %
class _AllergiesStep extends StatefulWidget {
  final Set<String> allergies;
  final double? fatPct;
  final bool saving;
  final void Function(String) onAllergyToggle;
  final void Function(double?) onFatPctChanged;
  final VoidCallback onSave;

  const _AllergiesStep({
    required this.allergies,
    required this.fatPct,
    required this.saving,
    required this.onAllergyToggle,
    required this.onFatPctChanged,
    required this.onSave,
  });

  @override
  State<_AllergiesStep> createState() => _AllergiesStepState();
}

class _AllergiesStepState extends State<_AllergiesStep> {
  final _fatCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.fatPct != null) _fatCtrl.text = widget.fatPct!.toString();
  }

  @override
  void dispose() {
    _fatCtrl.dispose();
    super.dispose();
  }

  static const _allergyOptions = ['Nuts', 'Dairy', 'Gluten', 'Shellfish', 'Soy', 'Eggs', 'None'];

  @override
  Widget build(BuildContext context) {
    return _StepShell(
      title: 'Allergies & body fat',
      onNext: widget.saving ? null : () {
        final fat = double.tryParse(_fatCtrl.text.trim());
        widget.onFatPctChanged(fat);
        widget.onSave();
      },
      nextLabel: widget.saving ? 'Saving…' : 'Save Profile',
      isSaving: widget.saving,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Allergies (optional)',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 14)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: _allergyOptions.map((opt) {
                final isSelected = widget.allergies.contains(opt);
                return GestureDetector(
                  onTap: () => widget.onAllergyToggle(opt),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    decoration: BoxDecoration(
                      color: isSelected ? AppColors.accent : AppColors.surface,
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(color: isSelected ? AppColors.accent : AppColors.border),
                    ),
                    child: Text(opt,
                        style: TextStyle(
                          color: isSelected ? Colors.white : AppColors.textPrimary,
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                        )),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 32),
            const Text('Body fat % (optional)',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 14)),
            const SizedBox(height: 12),
            TextField(
              controller: _fatCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: InputDecoration(
                hintText: 'e.g. 18.5',
                hintStyle: const TextStyle(color: AppColors.textTertiary),
                suffixText: '%',
                suffixStyle: const TextStyle(color: AppColors.textTertiary),
                filled: true,
                fillColor: AppColors.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
