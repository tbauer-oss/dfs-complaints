import 'package:flutter/material.dart';

/// A [DropdownMenu] that always occupies the requested field width.
///
/// Flutter's web implementation may otherwise size the menu from its label or
/// selected value, even when an ancestor provides a wider constraint.
class WidthBoundDropdownMenu extends StatelessWidget {
  const WidthBoundDropdownMenu({
    super.key,
    required this.width,
    required this.controller,
    required this.label,
    required this.options,
    this.enableFilter = true,
    this.enableSearch = true,
    this.requestFocusOnTap = true,
    this.menuHeight,
    this.textStyle,
    this.labelStyle,
    this.leadingIcon,
    this.inputDecorationTheme,
  });

  final double width;
  final TextEditingController controller;
  final String label;
  final Iterable<String> options;
  final bool enableFilter;
  final bool enableSearch;
  final bool requestFocusOnTap;
  final double? menuHeight;
  final TextStyle? textStyle;
  final TextStyle? labelStyle;
  final Widget? leadingIcon;
  final InputDecorationTheme? inputDecorationTheme;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: DropdownMenu<String>(
        width: width,
        controller: controller,
        label: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: labelStyle,
        ),
        dropdownMenuEntries: options
            .map(
              (value) => DropdownMenuEntry<String>(
                value: value,
                label: value,
              ),
            )
            .toList(),
        enableFilter: enableFilter,
        enableSearch: enableSearch,
        requestFocusOnTap: requestFocusOnTap,
        menuHeight: menuHeight,
        textStyle: textStyle,
        leadingIcon: leadingIcon,
        inputDecorationTheme: inputDecorationTheme,
      ),
    );
  }
}
