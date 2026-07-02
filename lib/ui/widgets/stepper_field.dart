import 'package:flutter/material.dart';

import '../app_theme.dart';

/// A labeled "− value +" row, styled like the mockup's dimension controls.
/// Tapping the value opens a text field for precise entry, so the compact
/// stepper never trades away exact numeric input.
class StepperField extends StatelessWidget {
  const StepperField({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    required this.onChanged,
    this.suffix = '',
    this.decimals = 1,
    this.trailing,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final double step;
  final String suffix;
  final int decimals;
  final ValueChanged<double> onChanged;

  /// Extra widget shown after the label (e.g. a derived readout).
  final Widget? trailing;

  String get _shown => value.toStringAsFixed(decimals);

  void _step(double delta) {
    final v = double.parse((value + delta).toStringAsFixed(decimals));
    if (v >= min && v <= max) onChanged(v);
  }

  Future<void> _editPrecise(BuildContext context) async {
    final controller = TextEditingController(text: _shown);
    final result = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceAlt,
        title: Text(label),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(suffixText: suffix),
          onSubmitted: (text) {
            final v = double.tryParse(text);
            if (v != null) Navigator.of(context).pop(v);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final v = double.tryParse(controller.text);
              Navigator.of(context).pop(v);
            },
            child: const Text('Set'),
          ),
        ],
      ),
    );
    if (result != null && result >= min && result <= max) {
      onChanged(double.parse(result.toStringAsFixed(decimals)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                Text(label,
                    style: const TextStyle(
                        fontSize: 13, color: AppColors.textSecondary)),
                if (trailing != null) ...[
                  const SizedBox(width: 8),
                  trailing!,
                ],
              ],
            ),
          ),
          _StepButton(icon: Icons.remove, onTap: () => _step(-step)),
          SizedBox(
            width: 74,
            child: InkWell(
              onTap: () => _editPrecise(context),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  '$_shown $suffix',
                  textAlign: TextAlign.center,
                  style: monoStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ),
          _StepButton(icon: Icons.add, onTap: () => _step(step)),
        ],
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(9),
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: AppColors.control,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Icon(icon, size: 18, color: AppColors.textPrimary),
      ),
    );
  }
}
