/// Counts tokens for the client cap. This is not a vendor tokenizer.
abstract class TokenCounter {
  int estimate(String text);
}

/// Documented assumption: one token per non-ASCII code unit, and one token
/// per four ASCII code units rounded up. Not a quote and not a billed count.
class HeuristicTokenCounter implements TokenCounter {
  const HeuristicTokenCounter();

  @override
  int estimate(String text) {
    var ascii = 0;
    var other = 0;
    for (final unit in text.codeUnits) {
      if (unit < 128) {
        ascii++;
      } else {
        other++;
      }
    }
    if (ascii == 0 && other == 0) return 0;
    return other + (ascii + 3) ~/ 4;
  }
}

class ExactTokenCounter implements TokenCounter {
  final int tokens;

  const ExactTokenCounter(this.tokens);

  @override
  int estimate(String text) => tokens;
}

class BudgetExceeded implements Exception {
  const BudgetExceeded();
}

class TokenBudget {
  final int limit;
  final TokenCounter counter;
  int spent = 0;
  int held = 0;
  int unapplied = 0;

  TokenBudget({required this.limit, TokenCounter? counter})
    : counter = counter ?? const HeuristicTokenCounter() {
    if (limit < 0) throw ArgumentError.value(limit, 'limit');
  }

  int get remaining {
    final left = limit - spent - held;
    return left < 0 ? 0 : left;
  }

  bool get overLimit => spent > limit;

  void hold(int tokens) {
    if (tokens < 0) throw ArgumentError.value(tokens, 'tokens');
    if (spent + held + tokens > limit) throw const BudgetExceeded();
    held += tokens;
  }

  void release(int tokens) {
    held -= tokens;
    if (held < 0) held = 0;
  }

  /// Records reported usage in place of a hold. Returns false when [spent]
  /// crosses [limit]. The usage is kept either way.
  bool settle(int holdAmount, int actual) {
    if (actual < 0) throw ArgumentError.value(actual, 'actual');
    release(holdAmount);
    spent += actual;
    return spent <= limit;
  }

  void recordUnapplied(int actual) {
    if (actual < 0) throw ArgumentError.value(actual, 'actual');
    spent += actual;
    unapplied += actual;
  }
}

enum QuoteKind { verified, unverified, userOverride }

class PriceQuote {
  final String id;
  final String vendor;
  final String model;
  final String sourceUrl;
  final String retrievedOn;
  final String currency;
  final double? inputPerMillion;
  final double? cachedInputPerMillion;
  final double? outputPerMillion;
  final String condition;
  final QuoteKind kind;
  final String note;

  const PriceQuote({
    required this.id,
    required this.vendor,
    required this.model,
    required this.sourceUrl,
    required this.retrievedOn,
    required this.currency,
    required this.inputPerMillion,
    required this.cachedInputPerMillion,
    required this.outputPerMillion,
    required this.condition,
    required this.kind,
    required this.note,
  });

  bool get billable =>
      kind != QuoteKind.unverified &&
      inputPerMillion != null &&
      outputPerMillion != null;

  bool get isVendorQuote => kind == QuoteKind.verified;

  PriceQuote override({
    double? inputPerMillion,
    double? cachedInputPerMillion,
    double? outputPerMillion,
  }) {
    return PriceQuote(
      id: '$id#override',
      vendor: vendor,
      model: model,
      sourceUrl: sourceUrl,
      retrievedOn: retrievedOn,
      currency: currency,
      inputPerMillion: inputPerMillion ?? this.inputPerMillion,
      cachedInputPerMillion:
          cachedInputPerMillion ?? this.cachedInputPerMillion,
      outputPerMillion: outputPerMillion ?? this.outputPerMillion,
      condition: condition,
      kind: QuoteKind.userOverride,
      note: 'Modified locally. Not the vendor quote retrieved on $retrievedOn.',
    );
  }
}

class UnverifiedQuote implements Exception {
  final String quoteId;
  final String meter;

  const UnverifiedQuote(this.quoteId, [this.meter = '']);

  @override
  String toString() => 'UnverifiedQuote($quoteId,$meter)';
}

class CostScenario {
  final int calls;
  final int inputTokensPerCall;
  final int outputTokensPerCall;
  final int cachedInputTokensPerCall;

  /// Multiplier on the vendor token cost. `1` adds nothing. Any other value
  /// is an assumption, not a vendor retry price.
  final double retryFactor;

  /// Fraction of the vendor token cost added as an abuse reserve.
  /// `0` adds nothing. This is an assumption, not a quote.
  final double abuseFraction;

  const CostScenario({
    required this.calls,
    required this.inputTokensPerCall,
    required this.outputTokensPerCall,
    this.cachedInputTokensPerCall = 0,
    this.retryFactor = 1,
    this.abuseFraction = 0,
  });
}

class CostLine {
  final String label;
  final double amount;
  final bool assumption;

  const CostLine(this.label, this.amount, {required this.assumption});
}

class CostEstimate {
  final PriceQuote quote;
  final List<CostLine> lines;
  final double vendorTokenCost;
  final double assumptionCost;

  const CostEstimate({
    required this.quote,
    required this.lines,
    required this.vendorTokenCost,
    required this.assumptionCost,
  });

  double get totalWithAssumptions => vendorTokenCost + assumptionCost;

  bool get assumptionsAreNotQuotes => true;
}

class CostCalculator {
  const CostCalculator();

  CostEstimate estimate(PriceQuote quote, CostScenario scenario) {
    if (!quote.billable) {
      throw UnverifiedQuote(quote.id);
    }
    if (scenario.calls < 0 ||
        scenario.inputTokensPerCall < 0 ||
        scenario.outputTokensPerCall < 0 ||
        scenario.cachedInputTokensPerCall < 0) {
      throw ArgumentError('token counts must be >= 0');
    }
    if (scenario.retryFactor < 1 || scenario.abuseFraction < 0) {
      throw ArgumentError('assumption factors must not be negative');
    }
    final cached = scenario.calls * scenario.cachedInputTokensPerCall;
    final input = scenario.calls * scenario.inputTokensPerCall;
    if (cached > input) {
      throw ArgumentError('cached tokens exceed input tokens');
    }
    if (cached > 0 && quote.cachedInputPerMillion == null) {
      throw UnverifiedQuote(quote.id, 'cached input');
    }
    const million = 1000000.0;
    final inputCost = (input - cached) / million * quote.inputPerMillion!;
    final cacheCost = cached / million * (quote.cachedInputPerMillion ?? 0);
    final outputCost =
        scenario.calls *
        scenario.outputTokensPerCall /
        million *
        quote.outputPerMillion!;
    final vendor = inputCost + cacheCost + outputCost;
    final lines = <CostLine>[
      CostLine('input', inputCost, assumption: false),
      if (cached > 0) CostLine('cached_input', cacheCost, assumption: false),
      CostLine('output', outputCost, assumption: false),
    ];
    var assumptions = 0.0;
    if (scenario.retryFactor != 1) {
      final extra = vendor * (scenario.retryFactor - 1);
      assumptions += extra;
      lines.add(CostLine('retry_assumption', extra, assumption: true));
    }
    if (scenario.abuseFraction != 0) {
      final extra = vendor * scenario.abuseFraction;
      assumptions += extra;
      lines.add(CostLine('abuse_assumption', extra, assumption: true));
    }
    return CostEstimate(
      quote: quote,
      lines: lines,
      vendorTokenCost: vendor,
      assumptionCost: assumptions,
    );
  }
}
