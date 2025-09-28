import 'package:flutter/material.dart';

class NumericKeypad extends StatelessWidget {
  final Function(String) onNumberTap;
  final VoidCallback onBackspace;
  final bool showBackspace;
  final double? buttonSize;
  final double? fontSize;

  const NumericKeypad({
    super.key,
    required this.onNumberTap,
    required this.onBackspace,
    this.showBackspace = true,
    this.buttonSize,
    this.fontSize,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = buttonSize ?? 72.0;
    final textSize = fontSize ?? 24.0;

    Widget buildNumberButton(String number) {
      return SizedBox(
        width: size,
        height: size,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(size / 2),
            onTap: () => onNumberTap(number),
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: theme.colorScheme.outline.withOpacity(0.3),
                  width: 1,
                ),
              ),
              child: Center(
                child: Text(
                  number,
                  style: TextStyle(
                    fontSize: textSize,
                    fontWeight: FontWeight.w500,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    Widget buildBackspaceButton() {
      return SizedBox(
        width: size,
        height: size,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(size / 2),
            onTap: onBackspace,
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: theme.colorScheme.outline.withOpacity(0.3),
                  width: 1,
                ),
              ),
              child: Center(
                child: Icon(
                  Icons.backspace_outlined,
                  size: textSize,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
          ),
        ),
      );
    }

    Widget buildEmptySpace() {
      return SizedBox(width: size, height: size);
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Row 1: 1, 2, 3
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            buildNumberButton('1'),
            buildNumberButton('2'),
            buildNumberButton('3'),
          ],
        ),
        const SizedBox(height: 16),
        // Row 2: 4, 5, 6
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            buildNumberButton('4'),
            buildNumberButton('5'),
            buildNumberButton('6'),
          ],
        ),
        const SizedBox(height: 16),
        // Row 3: 7, 8, 9
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            buildNumberButton('7'),
            buildNumberButton('8'),
            buildNumberButton('9'),
          ],
        ),
        const SizedBox(height: 16),
        // Row 4: empty, 0, backspace
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            buildEmptySpace(),
            buildNumberButton('0'),
            if (showBackspace) buildBackspaceButton() else buildEmptySpace(),
          ],
        ),
      ],
    );
  }
}