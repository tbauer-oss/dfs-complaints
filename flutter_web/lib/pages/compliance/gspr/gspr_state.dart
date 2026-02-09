import 'package:flutter/foundation.dart';

import '../../../models/gspr.dart';

class GsprTdState {
  static final ValueNotifier<GsprTdOption?> selectedTd = ValueNotifier<GsprTdOption?>(null);
}

class GsprAccess {
  final bool canEdit;
  final bool isPrrc;
  final bool isQm;
  final bool isAdmin;

  const GsprAccess({
    required this.canEdit,
    required this.isPrrc,
    required this.isQm,
    required this.isAdmin,
  });

  static bool _isTruthy(dynamic flag) {
    if (flag == null) return false;
    if (flag is bool) return flag;
    final s = flag.toString().trim().toLowerCase();
    return s == 'true' || s == '1' || s == 'yes';
  }

  static String? _normalizeTilePermission(Object? raw) {
    final value = (raw ?? '').toString().trim().toLowerCase();
    if (value == 'write') return 'write';
    if (value == 'read') return 'read';
    if (value == 'none' || value == 'hidden' || value == 'hide') return 'none';
    return null;
  }

  static bool _canWriteTile(Map<String, dynamic> profile, String tileId) {
    final role = (profile['role'] ?? '').toString().trim().toLowerCase();
    final permissions = profile['tilePermissions'];
    if (permissions is Map) {
      final override = _normalizeTilePermission(permissions[tileId]);
      if (override != null) return override == 'write';
    }
    return role != 'readonly';
  }

  static GsprAccess fromProfile(Map<String, dynamic>? profile) {
    final data = profile ?? const <String, dynamic>{};
    final role = (data['role'] ?? '').toString().trim().toLowerCase();
    return GsprAccess(
      canEdit: _canWriteTile(data, 'gspr'),
      isPrrc: _isTruthy(data['isPRRC'] ?? data['isPrrc'] ?? data['prrc']),
      isQm: _isTruthy(data['isQM'] ?? data['isQm'] ?? data['qm']),
      isAdmin: role == 'admin' || role == 'superuser',
    );
  }
}
