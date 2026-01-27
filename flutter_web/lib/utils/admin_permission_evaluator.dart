enum AdminAccessDecision {
  allow,
  deny,
  loading,
  unauthenticated,
}

AdminAccessDecision evaluateAdminAccess({
  required bool hasAuthToken,
  required bool hasProfile,
  required bool isAllowed,
}) {
  if (!hasAuthToken) return AdminAccessDecision.unauthenticated;
  if (!hasProfile) return AdminAccessDecision.loading;
  return isAllowed ? AdminAccessDecision.allow : AdminAccessDecision.deny;
}
