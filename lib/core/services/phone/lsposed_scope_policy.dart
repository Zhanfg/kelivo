/// LSPosed scope policy model. No module is installed or Hook invoked.
enum LsposedScopeDecision { allow, deny }

final class LsposedTarget {
  LsposedTarget({
    required this.packageName,
    required this.processName,
    required this.moduleVersion,
  }) {
    if (!RegExp(
          r'^[a-zA-Z][a-zA-Z0-9_]*(\.[a-zA-Z][a-zA-Z0-9_]*){1,}$',
        ).hasMatch(packageName) ||
        processName != packageName &&
            !processName.startsWith('$packageName:') ||
        !RegExp(r'^\d+\.\d+\.\d+$').hasMatch(moduleVersion)) {
      throw ArgumentError('Invalid LSPosed target or version');
    }
  }
  final String packageName;
  final String processName;
  final String moduleVersion;
}

final class LsposedScopePolicy {
  LsposedScopePolicy({
    required this.allowedPackage,
    required this.requiredVersion,
  });
  final String allowedPackage;
  final String requiredVersion;
  bool _enabled = true;
  bool get enabled => _enabled;
  void disable() {
    _enabled = false;
  }

  LsposedScopeDecision evaluate(
    LsposedTarget target, {
    required bool userApproved,
    required bool moduleHealthy,
  }) {
    if (!_enabled ||
        !userApproved ||
        !moduleHealthy ||
        target.packageName != allowedPackage ||
        target.moduleVersion != requiredVersion) {
      return LsposedScopeDecision.deny;
    }
    return LsposedScopeDecision.allow;
  }
}
