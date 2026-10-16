import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../../core/constants/app_colors.dart';

/// Custom numeric keypad per design.md — supports dark mode (lock screen)
/// and light mode (PIN setup screen).
/// Dark mode: #384D70 button background on #2B3C5A canvas
/// Light mode: white card buttons on surface neutral
class VaultNumpad extends StatelessWidget {
  const VaultNumpad({
    super.key,
    required this.onKey,
    required this.onBackspace,
    this.isDarkMode = true,
    this.onBiometric,
    this.showBiometric = false,
  });

  final void Function(String key) onKey;
  final VoidCallback onBackspace;
  final bool isDarkMode;
  final VoidCallback? onBiometric;
  final bool showBiometric;

  static const _rows = [
    ['1', '2', '3'],
    ['4', '5', '6'],
    ['7', '8', '9'],
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        children: [
          // Digit rows 1-9
          ..._rows.asMap().entries.map((entry) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: entry.value
                    .map((k) => _KeyButton(
                          label: k,
                          onTap: () => onKey(k),
                          isDarkMode: isDarkMode,
                        ))
                    .toList(),
              ),
            );
          }),
          // Bottom row: biometric | 0 | backspace
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              showBiometric && onBiometric != null
                  ? _IconButton(
                      icon: Icons.fingerprint_rounded,
                      onTap: onBiometric!,
                      isDarkMode: isDarkMode,
                    )
                  : SizedBox(
                      width: _keyWidth,
                      height: _keyWidth,
                    ),
              _KeyButton(label: '0', onTap: () => onKey('0'), isDarkMode: isDarkMode),
              _IconButton(
                icon: Icons.backspace_rounded,
                onTap: onBackspace,
                isDarkMode: isDarkMode,
              ),
            ],
          ),
        ],
      ).animate().fadeIn(delay: 200.ms, duration: 400.ms).slideY(
            begin: 0.15,
            end: 0,
            delay: 200.ms,
            duration: 400.ms,
            curve: Curves.easeOut,
          ),
    );
  }
}

const double _keyWidth = 76;
const double _keyHeight = 64;

class _KeyButton extends StatefulWidget {
  const _KeyButton({
    required this.label,
    required this.onTap,
    required this.isDarkMode,
  });

  final String label;
  final VoidCallback onTap;
  final bool isDarkMode;

  @override
  State<_KeyButton> createState() => _KeyButtonState();
}

class _KeyButtonState extends State<_KeyButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final bgColor = widget.isDarkMode
        ? (_pressed ? AppColors.lockKeypadButtonPressed : AppColors.lockKeypadButton)
        : (_pressed ? AppColors.accentEmeraldLight : AppColors.cardCanvas);

    final textColor = widget.isDarkMode
        ? Colors.white
        : AppColors.textPrimary;

    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 80),
        width: _keyWidth,
        height: _keyHeight,
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(14),
          border: widget.isDarkMode
              ? null
              : Border.all(color: AppColors.borderLight),
          boxShadow: widget.isDarkMode
              ? null
              : AppColors.cardShadow,
        ),
        child: Center(
          child: Text(
            widget.label,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w400,
              color: textColor,
            ),
          ),
        ),
      ),
    );
  }
}

class _IconButton extends StatefulWidget {
  const _IconButton({
    required this.icon,
    required this.onTap,
    required this.isDarkMode,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool isDarkMode;

  @override
  State<_IconButton> createState() => _IconButtonState();
}

class _IconButtonState extends State<_IconButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 80),
        width: _keyWidth,
        height: _keyHeight,
        decoration: BoxDecoration(
          color: _pressed
              ? (widget.isDarkMode
                  ? AppColors.lockKeypadButtonPressed
                  : AppColors.accentEmeraldLight)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(
          widget.icon,
          color: widget.isDarkMode
              ? AppColors.textOnDarkMuted
              : AppColors.textMuted,
          size: 26,
        ),
      ),
    );
  }
}
