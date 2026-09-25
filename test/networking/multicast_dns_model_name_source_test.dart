import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:multicast_dns/multicast_dns.dart';

import 'package:devialet_expert_remote_app/networking/model_name_source.dart';
import 'package:devialet_expert_remote_app/networking/multicast_dns_model_name_source.dart';

import 'fake_model_name_source.dart';

/// A scripted `MDnsClient`: every lookup answers from [records] by (type,
/// name), instantly. Records what the adapter did to it.
class FakeMDnsClient extends MDnsClient {
  FakeMDnsClient({this.startError, this.records = const []});

  final Object? startError;
  final List<ResourceRecord> records;
  bool started = false;
  int stops = 0;
  final List<String> queries = [];

  @override
  Future<void> start({
    InternetAddress? listenAddress,
    NetworkInterfacesFactory? interfacesFactory,
    int mDnsPort = 5353,
    InternetAddress? mDnsAddress,
    Function? onError,
  }) async {
    final e = startError;
    if (e != null) throw e;
    started = true;
  }

  @override
  Stream<T> lookup<T extends ResourceRecord>(ResourceRecordQuery query, {Duration timeout = const Duration(seconds: 5)}) {
    queries.add('${query.resourceRecordType} ${query.fullyQualifiedName}');
    return Stream.fromIterable(
      records.whereType<T>().where((r) => r.resourceRecordType == query.resourceRecordType && r.name == query.fullyQualifiedName),
    );
  }

  @override
  void stop() {
    stops++;
    started = false;
  }
}

const service = MulticastDnsModelNameSource.serviceName;
const instance = 'My Devialet.$service';
const host = 'Expert140Pro-K48A00904ZE1V.local';

List<ResourceRecord> amp({String inst = instance, String target = host, String ip = '192.0.2.22'}) => [
  PtrResourceRecord(service, 0, domainName: inst),
  SrvResourceRecord(inst, 0, target: target, port: 80, priority: 0, weight: 0),
  IPAddressResourceRecord(target, 0, address: InternetAddress(ip)),
];

Future<Iterable<NetworkInterface>> noInterfaces(InternetAddressType _) async => const [];

void main() {
  late FakeMulticastLock lock;
  late List<FakeMDnsClient> clients;

  MulticastDnsModelNameSource make({
    List<ResourceRecord> records = const [],
    Object? startError,
    Duration interval = const Duration(milliseconds: 40),
  }) {
    lock = FakeMulticastLock();
    clients = [];
    return MulticastDnsModelNameSource(
      lock: lock,
      newClient: () {
        final c = FakeMDnsClient(startError: startError, records: records);
        clients.add(c);
        return c;
      },
      interfaces: noInterfaces,
      queryInterval: interval,
      lookupWindow: const Duration(milliseconds: 10),
    );
  }

  Future<void> settle([int ms = 5]) => Future<void>.delayed(Duration(milliseconds: ms));

  test('one cycle: PTR → SRV → A yields one hit; the lock is held from listen to cancel', () async {
    final src = make(records: amp());
    final hits = <ModelNameHit>[];
    final sub = src.browse().listen(hits.add);
    await settle();
    expect(hits, [(hostname: host, ip: '192.0.2.22')]);
    expect(clients.single.queries, ['12 $service', '33 $instance', '1 $host']);
    expect(clients.single.stops, 1);
    expect((lock.acquired, lock.released), (1, 0));
    await sub.cancel();
    expect((lock.acquired, lock.released), (1, 1));
  });

  test('two instances → two hits; a duplicate PTR → one; an AAAA-only host → nothing', () async {
    final records = [
      ...amp(),
      ...amp(inst: 'Other.$service', target: 'Expert220Pro-X.local', ip: '192.0.2.23'),
      PtrResourceRecord(service, 0, domainName: instance), // duplicate
      PtrResourceRecord(service, 0, domainName: 'Six.$service'),
      SrvResourceRecord('Six.$service', 0, target: 'six.local', port: 80, priority: 0, weight: 0),
      IPAddressResourceRecord('six.local', 0, address: InternetAddress('fe80::1')),
    ];
    final src = make(records: records);
    final hits = <ModelNameHit>[];
    final sub = src.browse().listen(hits.add);
    await settle();
    expect(hits.map((h) => h.ip), ['192.0.2.22', '192.0.2.23']);
    await sub.cancel();
  });

  test('start() throwing is terminal: one error, stream closed, lock released once, no stop() on the unstarted client', () async {
    final src = make(startError: const SocketException('bind 5353'));
    final errors = <Object>[];
    var done = false;
    src.browse().listen((_) {}, onError: errors.add, onDone: () => done = true);
    await settle();
    expect(errors.single, isA<SocketException>());
    expect(done, isTrue);
    expect((lock.acquired, lock.released), (1, 1));
    expect(clients.single.stops, 0);
    expect(clients, hasLength(1), reason: 'no further cycles');
  });

  test('a lock that cannot be acquired is the same terminal error, with no client at all', () async {
    final src = make(records: amp());
    lock.failAcquire = StateError('no channel');
    final errors = <Object>[];
    src.browse().listen((_) {}, onError: errors.add);
    await settle();
    expect(errors.single, isA<StateError>());
    expect(clients, isEmpty);
    expect(lock.released, 0, reason: 'never held');
  });

  test('cycles repeat every queryInterval with a fresh client; cancel stops the in-flight one and ends the loop', () async {
    final src = make(records: amp(), interval: const Duration(milliseconds: 40));
    final hits = <ModelNameHit>[];
    final sub = src.browse().listen(hits.add);
    await settle();
    expect(clients, hasLength(1));
    await settle(60);
    expect(clients, hasLength(2), reason: 'a second query went on the wire after the interval');
    expect(hits, hasLength(2), reason: 'the second cycle re-reports (the resolver dedupes)');
    await sub.cancel();
    final after = clients.length;
    await settle(100);
    expect(clients.length, after, reason: 'no cycle after cancel');
    expect(clients.map((c) => c.stops), everyElement(1));
    expect(lock.released, 1);
  });

  test('why a fresh client per cycle: one long-lived client answers from its cache and never re-queries', () async {
    // The package's own behaviour (multicast_dns 0.3.3 `lookup`): a cache
    // hit short-circuits the wire. Modelled by the fake answering
    // instantly from `records` — a second lookup on the same client is
    // indistinguishable from a first, which is exactly why the adapter
    // cannot reuse one (checklist 29 note in the adapter's doc).
    final client = FakeMDnsClient(records: amp());
    await client.start();
    final first = await client.lookup<PtrResourceRecord>(ResourceRecordQuery.serverPointer(service)).toList();
    final second = await client.lookup<PtrResourceRecord>(ResourceRecordQuery.serverPointer(service)).toList();
    expect(first, second);
    expect(client.queries, hasLength(2), reason: 'the fake counts calls; the real client would have sent one packet');
  });
}
