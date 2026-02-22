import 'package:flutter/material.dart';

/// Compact stat display for queue counts (pending, active, completed, failed).
/// When [valueLabel] is non-null, it is shown instead of [value] (e.g. for duration "2m 30s").
class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    required this.label,
    required this.value,
    required this.color,
    this.valueLabel,
  });

  final String label;
  final int value;
  final Color color;
  final String? valueLabel;

  @override
  Widget build(BuildContext context) {
    final displayValue = valueLabel ?? value.toString();
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(
              label,
              style: TextStyle(color: color, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              displayValue,
              style: TextStyle(
                color: color,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
