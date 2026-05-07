import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/models/scan_result_model.dart';
import '../../../data/models/dietary_profile_model.dart';
import '../../viewmodels/dietary_profile_viewmodel.dart';
import '../../viewmodels/nutrition_scan_viewmodel.dart';

class NutritionScanScreen extends StatefulWidget {
  const NutritionScanScreen({super.key});

  @override
  State<NutritionScanScreen> createState() => _NutritionScanScreenState();
}

class _NutritionScanScreenState extends State<NutritionScanScreen>
    with WidgetsBindingObserver {
  final _picker = ImagePicker();
  File? _pickedImage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<NutritionScanViewModel>().reset();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    context.read<NutritionScanViewModel>().onAppLifecycleChanged(state);
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
            NutritionScanState.scanning => _LoadingView(phrase: vm.currentLoadingPhrase),
            NutritionScanState.questioning => _QuestionView(vm: vm),
            NutritionScanState.analyzing => _LoadingView(phrase: vm.currentLoadingPhrase),
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
                          Icon(Icons.camera_alt_rounded, color: AppColors.textTertiary, size: 64),
                          SizedBox(height: 16),
                          Text(
                            'Take a photo of a nutrition label\nor a restaurant dish',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: AppColors.textSecondary, fontSize: 15),
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
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: const Text('Scan', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Loading: animated rotating phrases ──────────────────────────────────────

class _LoadingView extends StatelessWidget {
  final String phrase;

  const _LoadingView({required this.phrase});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 44,
            height: 44,
            child: CircularProgressIndicator(color: AppColors.accent, strokeWidth: 2.5),
          ),
          const SizedBox(height: 36),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 48),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 400),
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.08),
                    end: Offset.zero,
                  ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOut)),
                  child: child,
                ),
              ),
              child: Text(
                phrase,
                key: ValueKey(phrase),
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 15, height: 1.5),
              ),
            ),
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

  void _autoAdvance(dynamic value) {
    setState(() {
      if (value is bool) {
        _boolAnswer = value;
      } else {
        _selectedOption = value as String;
      }
    });
    Future.delayed(const Duration(milliseconds: 280), () {
      if (mounted) {
        widget.vm.answerCurrent(value);
        setState(() => _resetInputs());
      }
    });
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

    final isAutoAdvanceType = q.inputType == 'select' || q.inputType == 'boolean';

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
                child: const Text('Skip', style: TextStyle(color: AppColors.textTertiary)),
              ),
              if (!isAutoAdvanceType) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _submit,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: Text(
                      vm.hasMoreQuestions ? 'Next' : 'Get Result',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
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
          onSelect: _autoAdvance,
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
            _BoolChip(label: 'Yes', selected: _boolAnswer == true, onTap: () => _autoAdvance(true)),
            const SizedBox(width: 12),
            _BoolChip(label: 'No', selected: _boolAnswer == false, onTap: () => _autoAdvance(false)),
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

  const _SelectInput({required this.options, required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: options.map((opt) => GestureDetector(
        onTap: () => onSelect(opt),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          decoration: BoxDecoration(
            color: selected == opt ? AppColors.accent : AppColors.surface,
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: selected == opt ? AppColors.accent : AppColors.border),
          ),
          child: Text(
            opt,
            style: TextStyle(
              color: selected == opt ? Colors.white : AppColors.textPrimary,
              fontWeight: selected == opt ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ),
      )).toList(),
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

// ─── Result: staggered animated redesign ─────────────────────────────────────

class _ResultView extends StatefulWidget {
  final NutritionAnalysisModel analysis;
  final VoidCallback onReset;

  const _ResultView({required this.analysis, required this.onReset});

  @override
  State<_ResultView> createState() => _ResultViewState();
}

class _ResultViewState extends State<_ResultView> with TickerProviderStateMixin {
  late AnimationController _controller;

  // Each section gets its own interval on the shared controller.
  late Animation<double> _headerFade;
  late Animation<Offset> _headerSlide;
  late Animation<double> _verdictScale;
  late Animation<double> _buddyFade;
  late Animation<Offset> _buddySlide;
  late Animation<double> _nutrientsFade;
  late Animation<Offset> _nutrientsSlide;
  late Animation<double> _prosFade;
  late Animation<Offset> _prosSlide;
  late Animation<double> _consFade;
  late Animation<Offset> _consSlide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );

    _headerFade = _buildFade(0.0, 0.22);
    _headerSlide = _buildSlide(0.0, 0.22);
    _verdictScale = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.15, 0.38, curve: Curves.elasticOut),
    );
    _buddyFade = _buildFade(0.28, 0.50);
    _buddySlide = _buildSlide(0.28, 0.50);
    _nutrientsFade = _buildFade(0.44, 0.65);
    _nutrientsSlide = _buildSlide(0.44, 0.65);
    _prosFade = _buildFade(0.60, 0.80);
    _prosSlide = _buildSlide(0.60, 0.80, direction: const Offset(-0.15, 0));
    _consFade = _buildFade(0.68, 0.88);
    _consSlide = _buildSlide(0.68, 0.88, direction: const Offset(0.15, 0));

    _controller.forward();
  }

  Animation<double> _buildFade(double start, double end) => CurvedAnimation(
        parent: _controller,
        curve: Interval(start, end, curve: Curves.easeOut),
      );

  Animation<Offset> _buildSlide(
    double start,
    double end, {
    Offset direction = const Offset(0, 0.12),
  }) =>
      Tween<Offset>(begin: direction, end: Offset.zero).animate(
        CurvedAnimation(
          parent: _controller,
          curve: Interval(start, end, curve: Curves.easeOut),
        ),
      );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Color get _verdictColor => switch (widget.analysis.recommendation) {
        'eat' => AppColors.success,
        'skip' => AppColors.error,
        _ => AppColors.warning,
      };

  String get _verdictLabel => switch (widget.analysis.recommendation) {
        'eat' => 'EAT',
        'skip' => 'SKIP',
        _ => 'MODERATE',
      };

  @override
  Widget build(BuildContext context) {
    final a = widget.analysis;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header: food name + headline + verdict pill ──────────────────
          FadeTransition(
            opacity: _headerFade,
            child: SlideTransition(
              position: _headerSlide,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          a.foodName,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            height: 1.2,
                          ),
                        ),
                        if (a.headline.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            '"${a.headline}"',
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 14,
                              fontStyle: FontStyle.italic,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Verdict pill with scale bounce
                  ScaleTransition(
                    scale: _verdictScale,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                      decoration: BoxDecoration(
                        color: _verdictColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: _verdictColor.withValues(alpha: 0.5)),
                      ),
                      child: Text(
                        _verdictLabel,
                        style: TextStyle(
                          color: _verdictColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          // ── Buddy's take ──────────────────────────────────────────────────
          FadeTransition(
            opacity: _buddyFade,
            child: SlideTransition(
              position: _buddySlide,
              child: _BuddyTakeCard(
                verdictReason: a.verdictReason,
                accentColor: _verdictColor,
              ),
            ),
          ),

          const SizedBox(height: 20),

          // ── Key nutrients ──────────────────────────────────────────────────
          if (a.keyNutrients.isNotEmpty)
            FadeTransition(
              opacity: _nutrientsFade,
              child: SlideTransition(
                position: _nutrientsSlide,
                child: _KeyNutrientsRow(nutrients: a.keyNutrients),
              ),
            ),

          if (a.keyNutrients.isNotEmpty) const SizedBox(height: 20),

          // ── Pros ──────────────────────────────────────────────────────────
          if (a.pros.isNotEmpty)
            FadeTransition(
              opacity: _prosFade,
              child: SlideTransition(
                position: _prosSlide,
                child: _ProsConsSection(
                  label: 'What works for you',
                  items: a.pros,
                  accentColor: AppColors.success,
                  bulletChar: '↑',
                ),
              ),
            ),

          if (a.pros.isNotEmpty) const SizedBox(height: 12),

          // ── Cons ──────────────────────────────────────────────────────────
          if (a.cons.isNotEmpty)
            FadeTransition(
              opacity: _consFade,
              child: SlideTransition(
                position: _consSlide,
                child: _ProsConsSection(
                  label: 'Keep in mind',
                  items: a.cons,
                  accentColor: AppColors.warning,
                  bulletChar: '↓',
                ),
              ),
            ),

          if (a.cons.isNotEmpty) const SizedBox(height: 20),

          // ── All the numbers (collapsible) ─────────────────────────────────
          _FullMacrosCollapsible(macros: a.macros),

          const SizedBox(height: 28),

          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: widget.onReset,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.textPrimary,
                side: const BorderSide(color: AppColors.border),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: const Text('Scan Another'),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Buddy's take card ────────────────────────────────────────────────────────

class _BuddyTakeCard extends StatelessWidget {
  final String verdictReason;
  final Color accentColor;

  const _BuddyTakeCard({required this.verdictReason, required this.accentColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border(left: BorderSide(color: accentColor, width: 3)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Buddy\'s take',
            style: TextStyle(
              color: accentColor,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            verdictReason,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 14,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Key nutrients row ────────────────────────────────────────────────────────

class _KeyNutrientsRow extends StatelessWidget {
  final List<KeyNutrient> nutrients;

  const _KeyNutrientsRow({required this.nutrients});

  Color _sentimentColor(String sentiment) => switch (sentiment) {
        'good' => AppColors.success,
        'watch' => AppColors.warning,
        _ => AppColors.textTertiary,
      };

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 100,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: nutrients.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, i) => _NutrientCard(
          nutrient: nutrients[i],
          accentColor: _sentimentColor(nutrients[i].sentiment),
        ),
      ),
    );
  }
}

class _NutrientCard extends StatelessWidget {
  final KeyNutrient nutrient;
  final Color accentColor;

  const _NutrientCard({required this.nutrient, required this.accentColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 120,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accentColor.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            nutrient.name.toUpperCase(),
            style: TextStyle(
              color: accentColor,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
          Text(
            nutrient.value,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            nutrient.context,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11,
              height: 1.3,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// ─── Pros / Cons section ──────────────────────────────────────────────────────

class _ProsConsSection extends StatelessWidget {
  final String label;
  final List<String> items;
  final Color accentColor;
  final String bulletChar;

  const _ProsConsSection({
    required this.label,
    required this.items,
    required this.accentColor,
    required this.bulletChar,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accentColor.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: accentColor,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 10),
          ...items.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Text(
                      bulletChar,
                      style: TextStyle(
                        color: accentColor,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      item,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                        height: 1.45,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── All the numbers (collapsible macro table) ────────────────────────────────

class _FullMacrosCollapsible extends StatefulWidget {
  final Map<String, double> macros;

  const _FullMacrosCollapsible({required this.macros});

  @override
  State<_FullMacrosCollapsible> createState() => _FullMacrosCollapsibleState();
}

class _FullMacrosCollapsibleState extends State<_FullMacrosCollapsible> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () => setState(() => _expanded = !_expanded),
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Text(
                  'All the numbers',
                  style: const TextStyle(
                    color: AppColors.textTertiary,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 6),
                AnimatedRotation(
                  turns: _expanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 250),
                  child: const Icon(Icons.keyboard_arrow_down_rounded,
                      color: AppColors.textTertiary, size: 18),
                ),
              ],
            ),
          ),
        ),
        AnimatedCrossFade(
          firstChild: const SizedBox.shrink(),
          secondChild: Padding(
            padding: const EdgeInsets.only(top: 10),
            child: _MacroTable(macros: widget.macros),
          ),
          crossFadeState: _expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 250),
        ),
      ],
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
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: rows.asMap().entries.map((e) {
          final isLast = e.key == rows.length - 1;
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              border: isLast ? null : const Border(bottom: BorderSide(color: AppColors.divider)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(e.value.$1,
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                Text(e.value.$2,
                    style: const TextStyle(
                        color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
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
  final DietaryProfileModel? profile;

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

    final p = profile!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Your Dietary Profile',
            style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 16),
          if (p.goal != null) _ProfileRow('Goal', p.goal!),
          if (p.activityLevel != null) _ProfileRow('Activity', p.activityLevel!),
          if (p.restrictions.isNotEmpty) _ProfileRow('Diet', p.restrictions.join(', ')),
          if (p.allergies.isNotEmpty) _ProfileRow('Allergies', p.allergies.join(', ')),
          if (p.weightKg != null) _ProfileRow('Weight', '${p.weightKg!.toStringAsFixed(1)} kg'),
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
            child: Text(label, style: const TextStyle(color: AppColors.textTertiary, fontSize: 13)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(color: AppColors.textPrimary, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}
