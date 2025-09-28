import 'package:flutter/material.dart';

/// A widget that displays PIN input as dots/circles
/// similar to Android lockscreen PIN display
class PinDisplay extends StatelessWidget {
  final String pin;
  final int maxLength;
  final double? dotSize;
  final Color? filledColor;
  final Color? emptyColor;
  final double spacing;

  const PinDisplay({
    super.key,
    required this.pin,
    this.maxLength = 6,
    this.dotSize,
    this.filledColor,
    this.emptyColor,
    this.spacing = 16.0,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = dotSize ?? 16.0;
    final filled = filledColor ?? theme.colorScheme.primary;
    final empty = emptyColor ?? theme.colorScheme.outline.withOpacity(0.3);

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(maxLength, (index) {
        final isFilled = index < pin.length;
        return Container(
          margin: EdgeInsets.symmetric(horizontal: spacing / 2),
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isFilled ? filled : Colors.transparent,
            border: Border.all(color: isFilled ? filled : empty, width: 2),
          ),
        );
      }),
    );
  }
}