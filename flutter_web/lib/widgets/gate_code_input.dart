import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A segmented input widget for DFS gate codes (format XXXX-XXXX).
class GateCodeInput extends StatefulWidget {
  const GateCodeInput({
    super.key,
    this.onCompleted,
    this.fieldWidth = 48,
    this.fieldSpacing = 12,
    this.decoration,
    this.textStyle,
  });

  /// Triggered when all eight characters have been entered.
  final ValueChanged<String>? onCompleted;

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
  late final List<TextEditingController> _controllers;
  late final List<FocusNode> _focusNodes;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(8, (_) => TextEditingController());
    _focusNodes = List.generate(8, (_) => FocusNode());
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
    }

    _notifyIfComplete();
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
    _notifyIfComplete();
  }

  void _notifyIfComplete() {
    if (_controllers.every((c) => c.text.length == 1)) {
      final buffer = StringBuffer();
      for (var i = 0; i < _controllers.length; i++) {
        if (i == 4) {
          buffer.write('-');
        }
        buffer.write(_controllers[i].text);
      }
      widget.onCompleted?.call(buffer.toString());
    }
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

  Widget _buildField(int index) {
    return SizedBox(
      width: widget.fieldWidth,
      child: Focus(
        focusNode: _focusNodes[index],
        onKey: (_, event) => _handleKey(index, event),
        child: TextField(
          controller: _controllers[index],
          autofocus: index == 0,
          maxLength: 1,
          textAlign: TextAlign.center,
          textInputAction:
              index == _controllers.length - 1 ? TextInputAction.done : TextInputAction.next,
          keyboardType: TextInputType.text,
          textCapitalization: TextCapitalization.characters,
          style: widget.textStyle ?? const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          decoration: widget.decoration ?? const InputDecoration(counterText: '', border: OutlineInputBorder()),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]'))],
          onChanged: (value) => _handleChanged(index, value),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final head = <Widget>[];
    for (var i = 0; i < 4; i++) {
      head.add(_buildField(i));
      if (i != 3) {
        head.add(SizedBox(width: widget.fieldSpacing));
      }
    }

    final tail = <Widget>[];
    for (var i = 4; i < 8; i++) {
      tail.add(_buildField(i));
      if (i != 7) {
        tail.add(SizedBox(width: widget.fieldSpacing));
      }
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        ...head,
        Padding(
          padding: EdgeInsets.symmetric(horizontal: widget.fieldSpacing),
          child: Text('-', style: widget.textStyle ?? Theme.of(context).textTheme.headlineSmall),
        ),
        ...tail,
      ],
    );
  }
}
