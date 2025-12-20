import 'package:flutter/material.dart';

import '../utils/app_error_mapper.dart';

class AppErrorSnackBar {
  static void show(BuildContext context, Object error) {
    final message = AppErrorMapper.map(error);
    final text = message.message.isEmpty ? message.title : '${message.title}\n${message.message}';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text)),
    );
  }
}
