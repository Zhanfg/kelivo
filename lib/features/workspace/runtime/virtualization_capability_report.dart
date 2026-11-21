/// #55 machine capability classification, not a hypervisor probe or launcher.
/// PRoot shares the host kernel and is never classified as a full VM.
enum EnvironmentExecutionKind { proot, nativeShell, container, fullVm }

enum VirtualMachineAvailability {
  available,
  unsupported,
  permissionRequired,
  unknown,
}

final class VirtualizationCapabilityReport {
  VirtualizationCapabilityReport({
    required this.kind,
    required this.vmAvailability,
    required this.independentKernel,
    required this.virtualDevices,
    required this.isolatedNetwork,
    required this.evidenceSource,
  }) {
    if (evidenceSource.trim().isEmpty || evidenceSource.length > 96) {
      throw ArgumentError('Evidence source is required');
    }
    if (kind == EnvironmentExecutionKind.proot &&
        (independentKernel ||
            virtualDevices ||
            isolatedNetwork ||
            vmAvailability == VirtualMachineAvailability.available)) {
      throw ArgumentError('PRoot cannot claim VM or host network isolation');
    }
    if (kind == EnvironmentExecutionKind.fullVm &&
        vmAvailability == VirtualMachineAvailability.available &&
        (!independentKernel || !virtualDevices)) {
      throw ArgumentError('Full VM requires verified kernel and devices');
    }
  }

  final EnvironmentExecutionKind kind;
  final VirtualMachineAvailability vmAvailability;
  final bool independentKernel;
  final bool virtualDevices;
  final bool isolatedNetwork;
  final String evidenceSource;
  bool get claimsFullVm =>
      kind == EnvironmentExecutionKind.fullVm &&
      vmAvailability == VirtualMachineAvailability.available;

  factory VirtualizationCapabilityReport.proot() =>
      VirtualizationCapabilityReport(
        kind: EnvironmentExecutionKind.proot,
        vmAvailability: VirtualMachineAvailability.unsupported,
        independentKernel: false,
        virtualDevices: false,
        isolatedNetwork: false,
        evidenceSource: 'contract:shared-host',
      );
}
