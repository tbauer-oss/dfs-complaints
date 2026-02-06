import 'package:flutter_test/flutter_test.dart';
import 'package:dfs_customer_complaint/utils/admin_permission_evaluator.dart';

void main() {
  group('evaluateAdminAccess', () {
    test('returns unauthenticated when no token is present', () {
      final decision = evaluateAdminAccess(
        hasAuthToken: false,
        hasProfile: false,
        isAllowed: false,
      );

      expect(decision, AdminAccessDecision.unauthenticated);
    });

    test('returns loading when token exists but profile is missing', () {
      final decision = evaluateAdminAccess(
        hasAuthToken: true,
        hasProfile: false,
        isAllowed: false,
      );

      expect(decision, AdminAccessDecision.loading);
    });

    test('returns allow for authorized views with profile', () {
      final decision = evaluateAdminAccess(
        hasAuthToken: true,
        hasProfile: true,
        isAllowed: true,
      );

      expect(decision, AdminAccessDecision.allow);
    });

    test('returns deny for unauthorized views with profile', () {
      final decision = evaluateAdminAccess(
        hasAuthToken: true,
        hasProfile: true,
        isAllowed: false,
      );

      expect(decision, AdminAccessDecision.deny);
    });
  });
}
