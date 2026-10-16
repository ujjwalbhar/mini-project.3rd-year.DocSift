// This file is superseded by vault_numpad.dart
// Kept to avoid import errors from any remaining references
import 'package:flutter/material.dart';

class NumpadWidget extends StatelessWidget {
  const NumpadWidget({
    super.key,
    required this.onKeyTap,
    required this.onBackspace,
    this.onBiometric,
    this.showBiometric = false,
  });

  final void Function(String key) onKeyTap;
  final VoidCallback onBackspace;
  final VoidCallback? onBiometric;
  final bool showBiometric;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
