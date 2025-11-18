import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A segmented input widget for DFS gate codes (format XXXX-XXXX).
class GateCodeInput extends StatefulWidget {
  const GateCodeInput({
    super.key,
    this.onCompleted,
    this.onChanged,
    this.fieldWidth = 48,
    this.fieldSpacing = 12,
    this.decoration,
    this.textStyle,
  });

  /// Triggered when all eight characters have been entered.
  final ValueChanged<String>? onCompleted;

  /// Called whenever the code changes. Emits `null` until all characters
  /// are filled.
  final ValueChanged<String?>? onChanged;

  /// Width of each individual input field.
  final double fieldWidth;

  /// Horizontal spacing between each field.
  final double fieldSpacing;

  /// Optional decoration applied to each field.
  final InputDecoration? decoration;

  /// Optional text style for every character.
  final TextStyle? textStyle;

  @override
  State<GateCodeInput> createState() => _GateCodeInputState();
}

class _GateCodeInputState extends State<GateCodeInput> {
  static const double _minFieldWidth = 32;
  static const double _minSpacing = 4;

  late final List<TextEditingController> _controllers;
  late final List<FocusNode> _focusNodes;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(8, (_) => TextEditingController());
    _focusNodes = List.generate(
      8,
      (index) => FocusNode(
        onKey: (node, event) => _handleKey(index, event),
      ),
    );
  }

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    for (final node in _focusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  void _handleChanged(int index, String value) {
    final previousValue = _controllers[index].text;
    final sanitized = value.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    if (sanitized.length > 1) {
      _fillFromIndex(index, sanitized);
      return;
    }

    if (_controllers[index].text != sanitized) {
      _controllers[index].value = TextEditingValue(
        text: sanitized,
        selection: TextSelection.collapsed(offset: sanitized.length),
      );
    }

    if (sanitized.isNotEmpty && index < _controllers.length - 1) {
      _focusNodes[index + 1].requestFocus();
      _controllers[index + 1].selection = TextSelection.collapsed(
        offset: _controllers[index + 1].text.length,
      );
    } else if (sanitized.isEmpty && previousValue.isNotEmpty && index > 0) {
      _focusNodes[index - 1].requestFocus();
      _controllers[index - 1].selection = TextSelection.collapsed(
        offset: _controllers[index - 1].text.length,
      );
    }

    _notifyProgress();
  }

  void _fillFromIndex(int startIndex, String value) {
    var currentIndex = startIndex;
    for (final char in value.split('')) {
      if (currentIndex >= _controllers.length) {
        break;
      }
      _controllers[currentIndex].value = TextEditingValue(
        text: char,
        selection: const TextSelection.collapsed(offset: 1),
      );
      currentIndex++;
    }

    if (currentIndex < _controllers.length) {
      _focusNodes[currentIndex].requestFocus();
    } else {
      _focusNodes.last.unfocus();
    }
    _notifyProgress();
  }

  void _notifyProgress() {
    final isComplete = _controllers.every((c) => c.text.length == 1);
    final code = _formattedCode();

    widget.onChanged?.call(isComplete ? code : null);

    if (isComplete) {
      widget.onCompleted?.call(code);
    }
  }

  String _formattedCode() {
    final buffer = StringBuffer();
    for (var i = 0; i < _controllers.length; i++) {
      if (i == 4) {
        buffer.write('-');
      }
      buffer.write(_controllers[i].text);
    }
    return buffer.toString();
  }

  KeyEventResult _handleKey(int index, RawKeyEvent event) {
    if (event is RawKeyDownEvent && event.logicalKey == LogicalKeyboardKey.backspace) {
      if (_controllers[index].text.isEmpty && index > 0) {
        _focusNodes[index - 1].requestFocus();
        _controllers[index - 1].selection = TextSelection.collapsed(
          offset: _controllers[index - 1].text.length,
        );
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  Widget _buildField(int index, double width) {
    return SizedBox(
      width: width,
      child: TextField(
        controller: _controllers[index],
        focusNode: _focusNodes[index],
        autofocus: index == 0,
        maxLength: 1,
        textAlign: TextAlign.center,
        textInputAction: index == _controllers.length - 1
            ? TextInputAction.done
            : TextInputAction.next,
        keyboardType: TextInputType.text,
        textCapitalization: TextCapitalization.characters,
        style: widget.textStyle ?? const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        decoration: widget.decoration ?? const InputDecoration(counterText: '', border: OutlineInputBorder()),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]'))],
        onChanged: (value) => _handleChanged(index, value),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dashStyle = widget.textStyle ?? Theme.of(context).textTheme.headlineSmall;
    return LayoutBuilder(
      builder: (context, constraints) {
        final dashPainter = TextPainter(
          text: TextSpan(text: '-', style: dashStyle),
          textDirection: Directionality.of(context),
        )..layout();
        final dashWidth = dashPainter.width;

        const fieldCount = 8;
        const spacingCount = 8; // 3 + 3 + 2 (around the dash)

        var fieldWidth = widget.fieldWidth;
        var spacing = widget.fieldSpacing;
        final maxWidth = constraints.maxWidth.isFinite ? constraints.maxWidth : null;

        double totalWidth() =>
            (fieldCount * fieldWidth) + (spacingCount * spacing) + dashWidth;

        if (maxWidth != null && totalWidth() > maxWidth) {
          final maxSpacing =
              (maxWidth - (fieldCount * _minFieldWidth) - dashWidth) / spacingCount;
          if (maxSpacing.isFinite && maxSpacing >= _minSpacing) {
            spacing = spacing.clamp(_minSpacing, maxSpacing);
          } else {
            spacing = _minSpacing;
          }

          final availableForFields = maxWidth - (spacingCount * spacing) - dashWidth;
          final maxFieldWidth = availableForFields / fieldCount;
          if (maxFieldWidth.isFinite && maxFieldWidth >= _minFieldWidth) {
            fieldWidth = fieldWidth.clamp(_minFieldWidth, maxFieldWidth);
          } else {
            fieldWidth = _minFieldWidth;
          }
        }

        final inputs = <Widget>[];
        for (var i = 0; i < 4; i++) {
          inputs.add(_buildField(i, fieldWidth));
          if (i != 3) {
            inputs.add(SizedBox(width: spacing));
          }
        }

        final tailInputs = <Widget>[];
        for (var i = 4; i < 8; i++) {
          tailInputs.add(_buildField(i, fieldWidth));
          if (i != 7) {
            tailInputs.add(SizedBox(width: spacing));
          }
        }

        final row = Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ...inputs,
            Padding(
              padding: EdgeInsets.symmetric(horizontal: spacing),
              child: Text('-', style: dashStyle),
            ),
            ...tailInputs,
          ],
        );

        if (maxWidth != null && totalWidth() > maxWidth) {
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: row,
          );
        }
        return row;
      },
    );
  }
}
