import 'package:flutter_test/flutter_test.dart';
import 'package:Kelivo/features/workspace/runtime/virtualization_capability_report.dart';

void main() {
  test('PRoot explicitly shares kernel and network', () {
    final p = VirtualizationCapabilityReport.proot();
    expect(p.claimsFullVm, isFalse);
    expect(p.independentKernel, isFalse);
    expect(p.virtualDevices, isFalse);
    expect(p.isolatedNetwork, isFalse);
  });
  test('PRoot cannot be upgraded to VM by self-report', () {
    expect(
      () => VirtualizationCapabilityReport(
        kind: EnvironmentExecutionKind.proot,
        vmAvailability: VirtualMachineAvailability.available,
        independentKernel: true,
        virtualDevices: true,
        isolatedNetwork: true,
        evidenceSource: 'mock',
      ),
      throwsArgumentError,
    );
  });
  test('VM availability needs kernel and virtual device evidence', () {
    expect(
      () => VirtualizationCapabilityReport(
        kind: EnvironmentExecutionKind.fullVm,
        vmAvailability: VirtualMachineAvailability.available,
        independentKernel: true,
        virtualDevices: false,
        isolatedNetwork: false,
        evidenceSource: 'mock',
      ),
      throwsArgumentError,
    );
    final report = VirtualizationCapabilityReport(
      kind: EnvironmentExecutionKind.fullVm,
      vmAvailability: VirtualMachineAvailability.available,
      independentKernel: true,
      virtualDevices: true,
      isolatedNetwork: false,
      evidenceSource: 'mock:not-live',
    );
    expect(report.claimsFullVm, isTrue);
    expect(report.isolatedNetwork, isFalse);
  });
  test('unsupported and unknown remain distinct without platform probe', () {
    final report = VirtualizationCapabilityReport(
      kind: EnvironmentExecutionKind.nativeShell,
      vmAvailability: VirtualMachineAvailability.unknown,
      independentKernel: false,
      virtualDevices: false,
      isolatedNetwork: false,
      evidenceSource: 'mock:no-probe',
    );
    expect(report.claimsFullVm, isFalse);
    expect(report.vmAvailability, VirtualMachineAvailability.unknown);
  });
}
