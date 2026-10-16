import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../../core/constants/app_colors.dart';

// NOTE: This widget is superseded by PinDotRow (pin_dot_row.dart)
// Kept for backward compat — delegates to PinDotRow style
class PinInputWidget extends StatelessWidget {
  const PinInputWidget({
    super.key,
    required this.length,
    required this.filled,
    this.hasError = false,
  });

  final int length;
  final int filled;
  final bool hasError;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(length, (index) {
        final isFilled = index < filled;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: hasError
                  ? AppColors.destructiveRed
                  : isFilled
                      ? AppColors.accentEmerald
                      : Colors.transparent,
              border: Border.all(
                color: hasError
                    ? AppColors.destructiveRed
                    : isFilled
                        ? AppColors.accentEmerald
                        : AppColors.pinUnfilled,
                width: 2,
              ),
              boxShadow: isFilled && !hasError
                  ? [
                      BoxShadow(
                        color: AppColors.accentEmerald.withValues(alpha: 0.4),
                        blurRadius: 6,
                      )
                    ]
                  : null,
            ),
          )
              .animate(target: isFilled ? 1.0 : 0.0)
              .scale(
                begin: const Offset(0.5, 0.5),
                end: const Offset(1.0, 1.0),
                duration: 180.ms,
                curve: Curves.elasticOut,
              ),
        );
      }),
    );
  }
}
