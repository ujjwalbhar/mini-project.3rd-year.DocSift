import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../constants/app_colors.dart';

/// Copies sensitive vault values to the system clipboard and automatically
/// scrubs them after [clearAfter] if the clipboard has not been overwritten.
class SecureClipboard {
  SecureClipboard._();

  static Timer? _clearTimer;
  static String? _lastCopiedSecret;

  static Future<void> copy(
    BuildContext context, {
    required String label,
    required String value,
    bool sensitive = true,
    Duration clearAfter = const Duration(seconds: 30),
  }) async {
    if (value.isEmpty) return;

    await Clipboard.setData(ClipboardData(text: value));
    _clearTimer?.cancel();

    if (sensitive) {
      _lastCopiedSecret = value;
      _clearTimer = Timer(clearAfter, () async {
        try {
          final current = await Clipboard.getData(Clipboard.kTextPlain);
          if (current?.text == _lastCopiedSecret) {
            await Clipboard.setData(const ClipboardData(text: ''));
          }
        } catch (_) {
          // Ignore platform clipboard restrictions while backgrounded
        } finally {
          _lastCopiedSecret = null;
        }
      });
    } else {
      _lastCopiedSecret = null;
    }

    if (context.mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              sensitive
                  ? '$label copied · auto-clears in ${clearAfter.inSeconds}s'
                  : '$label copied to clipboard',
            ),
            backgroundColor: AppColors.primaryNavy,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
    }
  }
}

