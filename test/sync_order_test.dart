import 'package:compoise/models.dart';
import 'package:compoise/sync/sync_remote.dart';
import 'package:flutter_test/flutter_test.dart';

import 'sync_fakes.dart';

Future<Device> _device(
  MemorySyncRemote remote,
  String name,
  TestClock clock,
) async {
  final device = Device(remote, name: name, clock: clock.call);
  await device.load();
  return device;
}

/// A drag reorder: move [id] to [index] in the task list.
void _reorder(FakeHost host, String id, int index) {
  final task = host.task(id);
  host.tasks.remove(task);
  host.tasks.insert(index, task);
  host.revision++;
}

List<String> _ids(FakeHost host) => [for (final t in host.tasks) t.id];

void main() {
  late MemorySyncRemote remote;
  late TestClock clock;

  setUp(() {
    remote = MemorySyncRemote();
    clock = TestClock();
  });

  test('a custom order syncs to the other device', () async {
    final a = await _device(remote, 'A', clock);
    for (final id in ['t1', 't2', 't3', 't4']) {
      a.host.addTask(id, id);
    }
    await a.engine.createVault(remote, provider: 'memory');
    final b = await _device(remote, 'B', clock);
    await b.engine.joinVault(remote, provider: 'memory');
    expect(_ids(b.host), ['t1', 't2', 't3', 't4']);

    _reorder(a.host, 't4', 0);
    _reorder(a.host, 't2', 3);
    await a.engine.sync();
    await b.engine.sync();
    expect(_ids(a.host), ['t4', 't1', 't3', 't2']);
    expect(_ids(b.host), _ids(a.host));
  });

  test('a drop into another quadrant keeps its slot after sync', () async {
    final a = await _device(remote, 'A', clock);
    a.host.addTask('a1', 'a1');
    a.host.addTask('a2', 'a2');
    a.host.addTask('p1', 'p1', quadrant: qPlan);
    await a.engine.createVault(remote, provider: 'memory');
    final b = await _device(remote, 'B', clock);
    await b.engine.joinVault(remote, provider: 'memory');

    a.host.task('p1').quadrant = qDo;
    _reorder(a.host, 'p1', 1);
    await a.engine.sync();
    await b.engine.sync();
    expect(_ids(b.host), ['a1', 'p1', 'a2']);
    expect(b.host.task('p1').quadrant, qDo);
  });

  test('a reorder and an offline add on another device converge', () async {
    final a = await _device(remote, 'A', clock);
    for (final id in ['t1', 't2', 't3']) {
      a.host.addTask(id, id);
    }
    await a.engine.createVault(remote, provider: 'memory');
    final b = await _device(remote, 'B', clock);
    await b.engine.joinVault(remote, provider: 'memory');

    _reorder(a.host, 't3', 0);
    b.host.addTask('n1', 'from B');
    await a.engine.sync();
    await b.engine.sync();
    await a.engine.sync();
    expect(_ids(a.host), _ids(b.host));
    final ids = _ids(a.host);
    expect(ids.indexOf('t3'), lessThan(ids.indexOf('t1')));
    expect(ids.indexOf('t1'), lessThan(ids.indexOf('t2')));
    expect(ids, contains('n1'));
  });
}
