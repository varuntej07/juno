import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/models/scan_result_model.dart';
import '../../viewmodels/dietary_profile_viewmodel.dart';
import '../../viewmodels/nutrition_scan_viewmodel.dart';

class NutritionScanScreen extends StatefulWidget {
  const NutritionScanScreen({super.key});

  @override
  State<NutritionScanScreen> createState() => _NutritionScanScreenState();
}

class _NutritionScanScreenState extends State<NutritionScanScreen> {
  final _picker = ImagePicker();
  File? _pickedImage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<NutritionScanViewModel>().reset();
    });
  }

  Future<void> _openCamera() async {
    final xfile = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 85,
      maxWidth: 1920,
    );
    if (xfile == null || !mounted) return;
    setState(() => _pickedImage = File(xfile.path));
  }

  Future<void> _pickGallery() async {
    final xfile = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1920,
    );
    if (xfile == null || !mounted) return;
    setState(() => _pickedImage = File(xfile.path));
  }

  Future<void> _scan() async {
    if (_pickedImage == null) return;
    await context.read<NutritionScanViewModel>().scan(_pickedImage!);
  }

  void _showProfileSheet() {
    final profile = context.read<DietaryProfileViewModel>().profile;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _ProfileSheet(profile: profile),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        title: const Text('Nutrition Scanner'),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline_rounded),
            tooltip: 'Your dietary profile',
            onPressed: _showProfileSheet,
          ),
        ],
      ),
      body: Consumer<NutritionScanViewModel>(
        builder: (context, vm, _) {
          return switch (vm.state) {
            NutritionScanState.idle => _IdleView(
                image: _pickedImage,
                onCamera: _openCamera,
                onGallery: _pickGallery,
                onScan: _pickedImage != null ? _scan : null,
              ),
            NutritionScanState.scanning => const _LoadingView(
                message: 'Analyzing image…',
              ),
            NutritionScanState.questioning => _QuestionView(
                vm: vm,
              ),
            NutritionScanState.analyzing => const _LoadingView(
                message: 'Calculating your verdict…',
              ),
            NutritionScanState.result => _ResultView(
                analysis: vm.analysis!,
                onReset: () {
                  vm.reset();
                  setState(() => _pickedImage = null);
                },
              ),
            NutritionScanState.error => _ErrorView(
                message: vm.error?.message ?? 'Something went wrong.',
                onRetry: () {
                  vm.reset();
                  setState(() => _pickedImage = null);
                },
              ),
          };
        },
      ),
    );
  }
}

// ─── Idle: image picker ───────────────────────────────────────────────────────

class _IdleView extends StatelessWidget {
  final File? image;
  final VoidCallback onCamera;
  final VoidCallback onGallery;
  final VoidCallback? onScan;

  const _IdleView({
    required this.image,
    required this.onCamera,
    required this.onGallery,
    required this.onScan,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Expanded(
            child: image != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Image.file(image!, fit: BoxFit.cover, width: double.infinity),
                  )
                : Container(
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.camera_alt_rounded,
                            color: AppColors.textTertiary,
                            size: 64,
                          ),
                          SizedBox(height: 16),
                          Text(
                            'Take a photo of a nutrition label\nor a restaurant dish',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 15,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onCamera,
                  icon: const Icon(Icons.camera_alt_rounded),
                  label: const Text('Camera'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textPrimary,
                    side: const BorderSide(color: AppColors.border),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onGallery,
                  icon: const Icon(Icons.photo_library_rounded),
                  label: const Text('Gallery'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textPrimary,
                    side: const BorderSide(color: AppColors.border),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: onScan,
              style: FilledButton.styleFrom(
                backgroundColor: onScan != null ? AppColors.accent : AppColors.surface,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text(
                'Scan',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Loading spinner ──────────────────────────────────────────────────────────

class _LoadingView extends StatelessWidget {
  final String message;

  const _LoadingView({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(color: AppColors.accent),
          const SizedBox(height: 20),
          Text(
            message,
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 15),
          ),
        ],
      ),
    );
  }
}

// ─── Q&A flow ─────────────────────────────────────────────────────────────────

class _QuestionView extends StatefulWidget {
  final NutritionScanViewModel vm;

  const _QuestionView({required this.vm});

  @override
  State<_QuestionView> createState() => _QuestionViewState();
}

class _QuestionViewState extends State<_QuestionView>
    with SingleTickerProviderStateMixin {
  late AnimationController _anim;
  late Animation<Offset> _slide;
  late Animation<double> _fade;
  final _textController = TextEditingController();
  final _numberController = TextEditingController();
  String? _selectedOption;
  bool? _boolAnswer;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 350));
    _slide = Tween<Offset>(begin: const Offset(0.3, 0), end: Offset.zero)
        .animate(CurvedAnimation(parent: _anim, curve: Curves.easeOut));
    _fade = CurvedAnimation(parent: _anim, curve: Curves.easeOut);
    _anim.forward();
  }

  @override
  void didUpdateWidget(_QuestionView old) {
    super.didUpdateWidget(old);
    if (widget.vm.currentQuestionIndex != old.vm.currentQuestionIndex) {
      _resetInputs();
      _anim.forward(from: 0);
    }
  }

  void _resetInputs() {
    _textController.clear();
    _numberController.clear();
    _selectedOption = null;
    _boolAnswer = null;
  }

  void _submit() {
    final q = widget.vm.currentQuestion;
    if (q == null) return;

    dynamic value;
    switch (q.inputType) {
      case 'select':
        if (_selectedOption == null) return;
        value = _selectedOption;
      case 'text':
        final t = _textController.text.trim();
        if (t.isEmpty) return;
        value = t;
      case 'number':
        final n = double.tryParse(_numberController.text.trim());
        if (n == null) return;
        value = n;
      case 'boolean':
        if (_boolAnswer == null) return;
        value = _boolAnswer;
      default:
        value = _textController.text.trim();
    }
    widget.vm.answerCurrent(value);
    setState(() => _resetInputs());
  }

  @override
  void dispose() {
    _anim.dispose();
    _textController.dispose();
    _numberController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = widget.vm;
    final q = vm.currentQuestion;
    if (q == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: vm.questionProgress,
              backgroundColor: AppColors.surface,
              color: AppColors.accent,
              minHeight: 4,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Question ${vm.currentQuestionIndex + 1} of ${vm.questions.length}',
            style: const TextStyle(color: AppColors.textTertiary, fontSize: 12),
          ),
          const SizedBox(height: 32),

          // Animated question card
          FadeTransition(
            opacity: _fade,
            child: SlideTransition(
              position: _slide,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    q.text,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 24),
                  _buildInput(q),
                ],
              ),
            ),
          ),

          const Spacer(),

          Row(
            children: [
              TextButton(
                onPressed: vm.skipCurrent,
                child: const Text(
                  'Skip',
                  style: TextStyle(color: AppColors.textTertiary),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(
                    vm.hasMoreQuestions ? 'Next' : 'Get Result',
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

  Widget _buildInput(ScanQuestion q) {
    return switch (q.inputType) {
      'select' => _SelectInput(
          options: q.options,
          selected: _selectedOption,
          onSelect: (v) => setState(() => _selectedOption = v),
        ),
      'number' => TextField(
          controller: _numberController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: const TextStyle(color: AppColors.textPrimary),
          decoration: InputDecoration(
            hintText: 'Enter a number',
            hintStyle: const TextStyle(color: AppColors.textTertiary),
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
      'boolean' => Row(
          children: [
            _BoolChip(
              label: 'Yes',
              selected: _boolAnswer == true,
              onTap: () => setState(() => _boolAnswer = true),
            ),
            const SizedBox(width: 12),
            _BoolChip(
              label: 'No',
              selected: _boolAnswer == false,
              onTap: () => setState(() => _boolAnswer = false),
            ),
          ],
        ),
      _ => TextField(
          controller: _textController,
          style: const TextStyle(color: AppColors.textPrimary),
          decoration: InputDecoration(
            hintText: 'Type your answer',
            hintStyle: const TextStyle(color: AppColors.textTertiary),
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
    };
  }
}

class _SelectInput extends StatelessWidget {
  final List<String> options;
  final String? selected;
  final void Function(String) onSelect;

  const _SelectInput({
    required this.options,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: options
          .map(
            (opt) => GestureDetector(
              onTap: () => onSelect(opt),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                decoration: BoxDecoration(
                  color: selected == opt ? AppColors.accent : AppColors.surface,
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(
                    color: selected == opt ? AppColors.accent : AppColors.border,
                  ),
                ),
                child: Text(
                  opt,
                  style: TextStyle(
                    color: selected == opt ? Colors.white : AppColors.textPrimary,
                    fontWeight: selected == opt ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ),
            ),
          )
          .toList(),
    );
  }
}

class _BoolChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _BoolChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
        decoration: BoxDecoration(
          color: selected ? AppColors.accent : AppColors.surface,
          borderRadius: BorderRadius.circular(30),
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

// ─── Result card ──────────────────────────────────────────────────────────────

class _ResultView extends StatelessWidget {
  final NutritionAnalysisModel analysis;
  final VoidCallback onReset;

  const _ResultView({required this.analysis, required this.onReset});

  Color get _verdictColor {
    return switch (analysis.recommendation) {
      'eat' => AppColors.success,
      'skip' => AppColors.error,
      _ => AppColors.warning,
    };
  }

  String get _verdictLabel {
    return switch (analysis.recommendation) {
      'eat' => 'EAT ✓',
      'skip' => 'SKIP ✗',
      _ => 'MODERATE ⚡',
    };
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Verdict badge
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 20),
            decoration: BoxDecoration(
              color: _verdictColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _verdictColor.withValues(alpha: 0.4)),
            ),
            child: Column(
              children: [
                Text(
                  _verdictLabel,
                  style: TextStyle(
                    color: _verdictColor,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  analysis.foodName,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Reason
          Text(
            analysis.verdictReason,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 15,
              height: 1.6,
            ),
          ),

          if (analysis.concerns.isNotEmpty) ...[
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: analysis.concerns
                  .map(
                    (c) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.warning.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
                      ),
                      child: Text(
                        c,
                        style: const TextStyle(color: AppColors.warning, fontSize: 13),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],

          const SizedBox(height: 24),

          // Macros table
          _MacroTable(macros: analysis.macros),

          const SizedBox(height: 32),

          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: onReset,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.textPrimary,
                side: const BorderSide(color: AppColors.border),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text('Scan Another'),
            ),
          ),
        ],
      ),
    );
  }
}

class _MacroTable extends StatelessWidget {
  final Map<String, double> macros;

  const _MacroTable({required this.macros});

  @override
  Widget build(BuildContext context) {
    final rows = [
      ('Calories', '${macros['calories']?.toStringAsFixed(0) ?? '—'} kcal'),
      ('Protein', '${macros['protein_g']?.toStringAsFixed(1) ?? '—'} g'),
      ('Carbs', '${macros['carbs_g']?.toStringAsFixed(1) ?? '—'} g'),
      ('Fat', '${macros['fat_g']?.toStringAsFixed(1) ?? '—'} g'),
      ('Sugar', '${macros['sugar_g']?.toStringAsFixed(1) ?? '—'} g'),
      ('Sodium', '${macros['sodium_mg']?.toStringAsFixed(0) ?? '—'} mg'),
      ('Fiber', '${macros['fiber_g']?.toStringAsFixed(1) ?? '—'} g'),
    ];

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: rows.asMap().entries.map((e) {
          final isLast = e.key == rows.length - 1;
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            decoration: BoxDecoration(
              border: isLast
                  ? null
                  : const Border(bottom: BorderSide(color: AppColors.divider)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(e.value.$1,
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 14)),
                Text(e.value.$2,
                    style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ─── Error view ───────────────────────────────────────────────────────────────

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 48),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 15),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: onRetry,
              style: FilledButton.styleFrom(backgroundColor: AppColors.accent),
              child: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Profile info sheet ───────────────────────────────────────────────────────

class _ProfileSheet extends StatelessWidget {
  final profile;

  const _ProfileSheet({required this.profile});

  @override
  Widget build(BuildContext context) {
    if (profile == null) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.person_outline_rounded, color: AppColors.textTertiary, size: 40),
            SizedBox(height: 12),
            Text(
              'No dietary profile set up yet.\nEnable Nutrition Agent in the Agents tab to get started.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
            ),
          ],
        ),
      );
    }

    final p = profile;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Your Dietary Profile',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 16),
          if (p.goal != null)
            _ProfileRow('Goal', p.goal!),
          if (p.activityLevel != null)
            _ProfileRow('Activity', p.activityLevel!),
          if (p.restrictions.isNotEmpty)
            _ProfileRow('Diet', p.restrictions.join(', ')),
          if (p.allergies.isNotEmpty)
            _ProfileRow('Allergies', p.allergies.join(', ')),
          if (p.weightKg != null)
            _ProfileRow('Weight', '${p.weightKg!.toStringAsFixed(1)} kg'),
        ],
      ),
    );
  }
}

class _ProfileRow extends StatelessWidget {
  final String label;
  final String value;

  const _ProfileRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(label,
                style: const TextStyle(color: AppColors.textTertiary, fontSize: 13)),
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
