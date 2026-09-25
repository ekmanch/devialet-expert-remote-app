import 'package:flutter_test/flutter_test.dart';

import 'package:devialet_expert_remote_app/domain/amp_trace.dart';
import 'package:devialet_expert_remote_app/domain/model_name_resolver.dart';

import '../networking/fake_model_name_source.dart';
import 'support/fake_time.dart';

const host = 'Expert140Pro-K48A00904ZE1V.local';
const amp = '192.0.2.22';

void main() {
  late FakeModelNameSource source;
  late FakeClock clock;
  late List<String> applied;
  late List<String> lines;

  ModelNameResolver make({Duration budget = kMdnsSessionBudget}) {
    source = FakeModelNameSource();
    clock = FakeClock();
    applied = [];
    lines = [];
    return ModelNameResolver(
      source: source,
      apply: (ip, model) => applied.add('$ip $model'),
      clock: clock,
      trace: AmpTrace(lines.add, clock),
      sessionBudget: budget,
    );
  }

  List<String> events() => [for (final l in lines) l.replaceFirst(RegExp(r'^\[amp\] \d+ms '), '')];
  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test('a hit for a known IP is applied once; a repeat hit does nothing (resolved once)', () async {
    final r = make()..start();
    r.onAmpHeard(amp);
    source.emit(host);
    await settle();
    expect(applied, ['$amp Devialet Expert 140 Pro']);
    source.emit(host);
    source.emit('Other-serial.local', ip: amp);
    await settle();
    expect(applied, hasLength(1), reason: 'never re-applied, never overwritten');
    expect(r.unresolved, isEmpty);
  });

  test('trust gate + replay: an unheard IP is cached, not applied; hearing it later applies from the cache with no new hit', () async {
    final r = make()..start();
    source.emit(host, ip: '192.0.2.99');
    await settle();
    expect(applied, isEmpty, reason: 'the service type is not Devialet-specific');
    expect(events(), contains('mdns hit host=$host ip=192.0.2.99 known=false'));
    r.onAmpHeard('192.0.2.99');
    expect(applied, ['192.0.2.99 Devialet Expert 140 Pro'], reason: 'mDNS answered before the first UDP packet');
    // Counter-half (checklist 20): without the cache, hearing the IP later
    // would open a session and wait for a hit that already went by.
    expect(source.activeSubscriptions, 0, reason: 'nothing left to resolve: the session closed');
  });

  test('sessions: open on start, close when everything known is resolved, reopen for a new unresolved IP', () async {
    final r = make()..start();
    expect(source.browseCalls, 1);
    expect(source.activeSubscriptions, 1);
    r.onAmpHeard(amp);
    source.emit(host);
    await settle();
    expect(source.activeSubscriptions, 0);
    expect(events().last, 'mdns session close reason=resolved');
    r.onAmpHeard('192.0.2.23');
    expect(source.activeSubscriptions, 1);
    expect(source.browseCalls, 2);
    expect(events().last, 'mdns session open reason=new-ip');
    // A hit for the other amp does not close it: .23 is still unresolved.
    source.emit(host, ip: amp);
    await settle();
    expect(source.activeSubscriptions, 1);
    expect(r.unresolved, {'192.0.2.23'});
  });

  test('a session with nothing heard yet stays open even when nothing is known (the startup query)', () async {
    make().start();
    await settle();
    expect(source.activeSubscriptions, 1, reason: 'no hit, no close: the first UDP packet is still to come');
  });

  test('the budget closes a hit-less session on the tick; the lock-holding source is cancelled', () async {
    final r = make(budget: const Duration(seconds: 10))..start();
    r.onAmpHeard('192.0.2.50'); // never answers mDNS
    clock.advance(const Duration(seconds: 9));
    r.onTick();
    expect(source.activeSubscriptions, 1);
    clock.advance(const Duration(seconds: 1));
    r.onTick();
    expect(source.activeSubscriptions, 0);
    expect(events().last, 'mdns session close reason=budget');
    r.onTick();
    expect(source.browseCalls, 1, reason: 'a tick never reopens');
  });

  test('failure: one "unavailable" line, no apply, no crash; a new IP retries once; ticks never add lines', () async {
    final r = make()..start();
    source.fail(StateError('bind 5353'));
    await settle();
    expect(events().where((e) => e.startsWith('mdns unavailable')).length, 1);
    expect(source.activeSubscriptions, 0);
    for (var i = 0; i < 5; i++) {
      clock.advance(const Duration(seconds: 1));
      r.onTick();
    }
    expect(events().where((e) => e.startsWith('mdns unavailable')).length, 1, reason: 'bounded by distinct IPs, not time');
    source.failOnSubscribe = StateError('bind 5353 again');
    r.onAmpHeard(amp);
    await settle();
    expect(events().where((e) => e.startsWith('mdns unavailable')).length, 2, reason: 'one retry per new IP');
    expect(source.browseCalls, 2);
    r.onAmpHeard(amp);
    await settle();
    expect(source.browseCalls, 2, reason: 'the same IP again is not new');
    expect(applied, isEmpty);
  });

  test('a hostname that parses to nothing settles the IP without an apply and without a re-attempt storm', () async {
    final r = make()..start();
    r.onAmpHeard(amp);
    source.emit('-serial.local.');
    await settle();
    expect(applied, isEmpty);
    expect(r.unresolved, isEmpty);
    expect(source.activeSubscriptions, 0, reason: 'settled: the session closed');
    expect(events().where((e) => e.startsWith('mdns applied')), isEmpty);
  });

  test('dispose closes the session and ignores everything after', () async {
    final r = make()..start();
    r.dispose();
    expect(source.activeSubscriptions, 0);
    expect(events().last, 'mdns session close reason=dispose');
    r.onAmpHeard(amp);
    expect(source.browseCalls, 1);
  });
}
