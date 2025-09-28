import 'package:flutter/material.dart';
import 'package:intelliboro/widgets/numeric_keypad.dart';
import 'package:intelliboro/widgets/pin_display.dart';

/// A compact PIN input dialog with custom numeric keypad
class PinInputDialog extends StatefulWidget {
  final String title;
  final String? subtitle;
  final int maxLength;
  final Function(String pin) onPinComplete;

  const PinInputDialog({
    super.key,
    required this.title,
    this.subtitle,
    this.maxLength = 6,
    required this.onPinComplete,
  });

  @override
  State<PinInputDialog> createState() => _PinInputDialogState();
}

class _PinInputDialogState extends State<PinInputDialog> {
  String _enteredPin = '';

  void _onNumberTap(String number) {
    if (_enteredPin.length < widget.maxLength) {
      setState(() {
        _enteredPin += number;
      });

      // Auto-complete when PIN is full
      if (_enteredPin.length == widget.maxLength) {
        Future.delayed(const Duration(milliseconds: 200), () {
          if (mounted) {
            widget.onPinComplete(_enteredPin);
          }
        });
      }
    }
  }

  void _onBackspace() {
    if (_enteredPin.isNotEmpty) {
      setState(() {
        _enteredPin = _enteredPin.substring(0, _enteredPin.length - 1);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 300,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.subtitle != null) ...[
              Text(
                widget.subtitle!,
                style: theme.textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
            ],

            // PIN Display
            PinDisplay(
              pin: _enteredPin,
              maxLength: widget.maxLength,
              dotSize: 12,
              spacing: 12,
            ),

            const SizedBox(height: 24),

            // Compact Numeric Keypad
            NumericKeypad(
              onNumberTap: _onNumberTap,
              onBackspace: _onBackspace,
              showBackspace: true,
              buttonSize: 56,
              fontSize: 18,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        if (_enteredPin.length == widget.maxLength)
          FilledButton(
            onPressed: () => widget.onPinComplete(_enteredPin),
            child: const Text('Confirm'),
          ),
      ],
    );
  }
}