import 'package:flutter/material.dart';

class DateField extends StatelessWidget {
  final String label;
  final DateTime? value;
  final void Function(DateTime?) onChanged;
  final bool requiredField;

  const DateField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.requiredField = false,
  });

  @override
  Widget build(BuildContext context) {
    final controller = TextEditingController(
      text: value != null ? _formatDate(value!) : '',
    );
    controller.selection = TextSelection.fromPosition(
      TextPosition(offset: controller.text.length),
    );
    return TextFormField(
      controller: controller,
      readOnly: true,
      decoration: InputDecoration(
        labelText: requiredField ? '$label *' : label,
        suffixIcon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (value != null)
              IconButton(
                icon: const Icon(Icons.clear),
                tooltip: 'Datum löschen',
                onPressed: () => onChanged(null),
              ),
            IconButton(
              icon: const Icon(Icons.calendar_today_outlined),
              tooltip: 'Datum auswählen',
              onPressed: () async {
                final now = DateTime.now();
                final picked = await showDatePicker(
                  context: context,
                  initialDate: value ?? now,
                  firstDate: DateTime(2000),
                  lastDate: DateTime(now.year + 10),
                );
                if (picked != null) {
                  onChanged(picked);
                }
              },
            ),
          ],
        ),
        border: const OutlineInputBorder(),
        isDense: true,
      ),
    );
  }

  String _formatDate(DateTime date) => '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}
