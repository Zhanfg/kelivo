import 'package:flutter_test/flutter_test.dart';
import 'package:Kelivo/core/services/jobs/job_dag_admission_policy.dart';

void main() {
  JobDagAdmissionPolicy pipeline() => JobDagAdmissionPolicy([
    DagJobNode(id: 'download'),
    DagJobNode(id: 'verify', dependsOn: ['download']),
    DagJobNode(id: 'unpack', dependsOn: ['verify']),
  ]);

  test(
    'ordered download, verify and unpack require successful predecessors',
    () {
      final dag = pipeline();
      expect(dag.admission('download', {}), DagNodeAdmission.ready);
      expect(
        dag.admission('verify', {'download': DagDependencyResult.pending}),
        DagNodeAdmission.blocked,
      );
      expect(
        dag.admission('verify', {'download': DagDependencyResult.success}),
        DagNodeAdmission.ready,
      );
      expect(
        dag.admission('unpack', {'verify': DagDependencyResult.success}),
        DagNodeAdmission.ready,
      );
    },
  );

  test('failed and unknown upstream jobs fail closed', () {
    final dag = pipeline();
    expect(
      dag.admission('verify', {'download': DagDependencyResult.failed}),
      DagNodeAdmission.failed,
    );
    expect(dag.admission('unpack', {}), DagNodeAdmission.reviewRequired);
  });

  test(
    'missing nodes, cycles, duplicates and self dependencies are rejected',
    () {
      expect(
        () => JobDagAdmissionPolicy([
          DagJobNode(id: 'a', dependsOn: ['nonexistent']),
        ]),
        throwsArgumentError,
      );
      expect(
        () => JobDagAdmissionPolicy([
          DagJobNode(id: 'a', dependsOn: ['b']),
          DagJobNode(id: 'b', dependsOn: ['a']),
        ]),
        throwsArgumentError,
      );
      expect(
        () => JobDagAdmissionPolicy([DagJobNode(id: 'a'), DagJobNode(id: 'a')]),
        throwsArgumentError,
      );
      expect(() => DagJobNode(id: 'a', dependsOn: ['a']), throwsArgumentError);
    },
  );

  test('immutable structure and no source mutation', () {
    final dependencies = <String>['a'];
    final source = DagJobNode(id: 'b', dependsOn: dependencies);
    dependencies.clear();
    expect(source.dependsOn, {'a'});
    final graph = JobDagAdmissionPolicy([DagJobNode(id: 'a'), source]);
    expect(() => graph.nodes.clear(), throwsUnsupportedError);
    expect(() => source.dependsOn.add('other'), throwsUnsupportedError);
  });
}
