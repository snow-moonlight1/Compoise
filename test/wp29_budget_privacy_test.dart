import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrixflow_native/experiments/wp29_hosted_ai/wp29_hosted_ai.dart';

import '../tool/wp29_hosted_ai_demo.dart';

void main() {
  test('heuristic is labeled by staying off the verified quote path', () {
    const counter = HeuristicTokenCounter();
    expect(counter.estimate(''), 0);
    expect(counter.estimate('abcd'), 1);
    expect(counter.estimate('abc'), 1);
    expect(counter.estimate('abcd中'), 2);
  });

  test('calculator keeps quotes, overrides, and assumptions apart', () {
    const calculator = CostCalculator();
    final flash = quoteById('deepseek-flash-offpeak');
    const scenario = CostScenario(
      calls: 1,
      inputTokensPerCall: 1000000,
      outputTokensPerCall: 1000000,
    );
    final priced = calculator.estimate(flash, scenario);
    expect(priced.vendorTokenCost, closeTo(0.75, 1e-9));
    expect(priced.assumptionCost, 0);
    expect(priced.quote.isVendorQuote, isTrue);

    final cached = calculator.estimate(
      flash,
      const CostScenario(
        calls: 1,
        inputTokensPerCall: 1000000,
        cachedInputTokensPerCall: 1000000,
        outputTokensPerCall: 1000000,
      ),
    );
    expect(cached.vendorTokenCost, closeTo(0.603, 1e-9));

    final overridden = calculator.estimate(
      flash.override(outputPerMillion: 1),
      scenario,
    );
    expect(overridden.quote.kind, QuoteKind.userOverride);
    expect(overridden.quote.isVendorQuote, isFalse);
    expect(overridden.vendorTokenCost, closeTo(1.15, 1e-9));

    final assumed = calculator.estimate(
      flash,
      const CostScenario(
        calls: 1,
        inputTokensPerCall: 1000000,
        outputTokensPerCall: 1000000,
        retryFactor: 1.5,
        abuseFraction: 0.25,
      ),
    );
    expect(assumed.vendorTokenCost, closeTo(0.75, 1e-9));
    expect(assumed.assumptionCost, closeTo(0.5625, 1e-9));
    expect(assumed.lines.where((line) => line.assumption), hasLength(2));

    expect(
      () => calculator.estimate(quoteById('preset-doubao-pro-32k'), scenario),
      throwsA(isA<UnverifiedQuote>()),
    );
    expect(
      wp29PriceCatalog.where((quote) => quote.kind == QuoteKind.verified),
      everyElement(
        predicate<PriceQuote>(
          (quote) => quote.retrievedOn == '2026-10-04' && quote.billable,
        ),
      ),
    );
  });

  test('privacy log redacts sealed task text and banned fields', () {
    final log = PrivacyLog();
    const secret = 'SYNTHETIC-WP29-TASK-9f3c-not-a-user';
    log.seal(secret);
    log.sealBytes(_sampleBytes());
    log.event('note', {'status': 'prefix $secret suffix', 'task_text': secret});
    final dump = log.dump();
    expect(dump, isNot(contains(secret)));
    expect(dump, contains('redacted'));
  });

  test('demo stays offline and does not print the synthetic task', () async {
    final buffer = StringBuffer();
    expect(await runWp29Demo(buffer), 0);
    final text = buffer.toString();
    expect(text, contains('demo_ok'));
    expect(text, isNot(contains(demoTaskText)));
    expect(text, contains('cost_unverified_refused=true'));
    expect(text, contains('quote=false'));
  });

  test('experiment sources do not touch production AI or HTTP clients', () {
    final files = <File>[
      ...Directory(
        'lib/experiments/wp29_hosted_ai',
      ).listSync().whereType<File>(),
      File('tool/wp29_hosted_ai_demo.dart'),
    ];
    expect(files, isNotEmpty);
    for (final file in files) {
      final source = file.readAsStringSync();
      expect(source, isNot(contains('ai_service.dart')));
      expect(source, isNot(contains('credential_store.dart')));
      expect(source, isNot(contains('storage.dart')));
      expect(source, isNot(contains('package:http')));
      expect(source, isNot(contains('HttpClient')));
      expect(source, isNot(contains('screens/')));
      if (file.path.replaceAll('\\', '/').contains('lib/experiments/')) {
        expect(source, isNot(contains('dart:io')));
        expect(source, isNot(contains('models.dart')));
      }
    }
  });
}

Uint8List _sampleBytes() => Uint8List.fromList(const [1, 2, 3, 4, 9, 9, 8, 7]);
