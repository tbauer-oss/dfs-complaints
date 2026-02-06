import 'dart:async';

import 'package:flutter/foundation.dart';

import '../api/client.dart';

class AppErrorMessage {
  final String title;
  final String message;

  const AppErrorMessage({required this.title, required this.message});

  const AppErrorMessage.custom(this.title) : message = '';
}

class AppErrorMapper {
  static AppErrorMessage map(Object error) {
    if (error is AppErrorMessage) {
      return error;
    }

    _logError(error);

    if (error is ApiError) {
      return _mapStatus(error.status, error.message);
    }

    if (error is TimeoutException || _contains(error, 'TimeoutException')) {
      return const AppErrorMessage(
        title: 'Die Anfrage dauert länger als erwartet.',
        message: 'Bitte erneut versuchen.',
      );
    }

    if (_contains(error, 'SocketException') ||
        _contains(error, 'NetworkError') ||
        _contains(error, 'Failed to fetch') ||
        _contains(error, 'CORS')) {
      return const AppErrorMessage(
        title: 'Keine Internetverbindung.',
        message: 'Bitte Verbindung prüfen und erneut versuchen.',
      );
    }

    return const AppErrorMessage(
      title: 'Etwas ist schiefgelaufen.',
      message: 'Bitte erneut versuchen.',
    );
  }

  static AppErrorMessage _mapStatus(int status, String? message) {
    if (status == 401 || status == 403) {
      return const AppErrorMessage(
        title: 'Zugriff nicht möglich.',
        message: 'Bitte melden Sie sich erneut an oder prüfen Sie Ihre Berechtigung.',
      );
    }

    if (status == 404) {
      return const AppErrorMessage(
        title: 'Inhalt nicht gefunden.',
        message: 'Möglicherweise wurde er verschoben oder gelöscht.',
      );
    }

    if (status == 400) {
      return const AppErrorMessage(
        title: 'Eingabe prüfen.',
        message: 'Einige Angaben sind unvollständig oder ungültig.',
      );
    }

    if (status >= 500 && status <= 504) {
      return const AppErrorMessage(
        title: 'Server gerade nicht erreichbar.',
        message: 'Bitte später erneut versuchen.',
      );
    }

    if (status == 0) {
      return const AppErrorMessage(
        title: 'Keine Internetverbindung.',
        message: 'Bitte Verbindung prüfen und erneut versuchen.',
      );
    }

    if (message != null && message.isNotEmpty) {
      return const AppErrorMessage(
        title: 'Etwas ist schiefgelaufen.',
        message: 'Bitte erneut versuchen.',
      );
    }

    return const AppErrorMessage(
      title: 'Etwas ist schiefgelaufen.',
      message: 'Bitte erneut versuchen.',
    );
  }

  static bool _contains(Object error, String needle) => error.toString().contains(needle);

  static void _logError(Object error) {
    if (kDebugMode) {
      if (error is ApiError) {
        debugPrint('AppErrorMapper: ApiError(status: ${error.status}, message: ${error.message}, details: ${error.details})');
      } else {
        debugPrint('AppErrorMapper: $error');
      }
    }
  }
}
