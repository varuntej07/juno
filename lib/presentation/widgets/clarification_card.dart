import 'package:flutter/material.dart';

import '../../data/models/clarification_payload.dart';

/// Renders a clarification question with tappable option chips.
///
/// Single-select: tap a chip → immediately calls [onSubmit].
/// Multi-select: tap chips to toggle selection → tap "Done" to submit.
/// Once [payload.isAnswered], renders in read-only mode showing selected options.
class ClarificationCard extends StatefulWidget {
  final ClarificationPayload payload;
  final void Function(List<String> selected) onSubmit;

  const ClarificationCard({
    super.key,
    required this.payload,
    required this.onSubmit,
  });

  @override
  State<ClarificationCard> createState() => _ClarificationCardState();
}

class _ClarificationCardState extends State<ClarificationCard> {
  late final Set<String> _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.payload.selectedOptions?.toSet() ?? {};
  }

  void _toggle(String option) {
    if (widget.payload.isAnswered) return;
    setState(() {
      if (widget.payload.multiSelect) {
        if (_selected.contains(option)) {
          _selected.remove(option);
        } else {
          _selected.add(option);
        }
      } else {
        _selected
          ..clear()
          ..add(option);
        widget.onSubmit([option]);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isReadOnly = widget.payload.isAnswered;

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.88,
        ),
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(4),
            topRight: Radius.circular(16),
            bottomLeft: Radius.circular(16),
            bottomRight: Radius.circular(16),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Question text
            Text(
              widget.payload.question,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 10),
            // Option chips
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: widget.payload.options.map((option) {
                final isSelected = _selected.contains(option);
                return _OptionChip(
                  label: option,
                  isSelected: isSelected,
                  isReadOnly: isReadOnly,
                  onTap: () => _toggle(option),
                );
              }).toList(),
            ),
            // Multi-select "Done" button
            if (widget.payload.multiSelect &&
                !isReadOnly &&
                _selected.isNotEmpty) ...[
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: () => widget.onSubmit(_selected.toList()),
                  style: FilledButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    textStyle: theme.textTheme.labelMedium,
                  ),
                  child: const Text('Done'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _OptionChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final bool isReadOnly;
  final VoidCallback onTap;

  const _OptionChip({
    required this.label,
    required this.isSelected,
    required this.isReadOnly,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final selectedColor = cs.primaryContainer;
    final unselectedColor = cs.surfaceContainerHigh;
    final selectedTextColor = cs.onPrimaryContainer;
    final unselectedTextColor =
        isReadOnly ? cs.onSurface.withValues(alpha: 0.38) : cs.onSurface;

    return GestureDetector(
      onTap: isReadOnly ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? selectedColor : unselectedColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? cs.primary
                : cs.outline.withValues(alpha: isReadOnly ? 0.3 : 0.6),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: isSelected ? selectedTextColor : unselectedTextColor,
                fontWeight:
                    isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
        ),
      ),
    );
  }
}
