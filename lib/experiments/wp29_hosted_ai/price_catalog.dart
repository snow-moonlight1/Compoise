import 'budget.dart';

/// Prices read from vendor pages on 2026-10-04.
///
/// A row with [QuoteKind.verified] copies a figure that was on the page.
/// A row with [QuoteKind.unverified] has no figure. Nothing here is a
/// long-term free-operation claim, a promotion, or a cache-write charge.
const priceRetrievedOn = '2026-10-04';

const deepSeekPricingUrl = 'https://api-docs.deepseek.com/quick_start/pricing';
const openAiPricingUrl = 'https://developers.openai.com/api/docs/pricing';
const anthropicPricingUrl =
    'https://platform.claude.com/docs/en/about-claude/pricing';
const bailianQwenPlusUrl = 'https://help.aliyun.com/zh/model-studio/qwen-plus';
const volcenginePriceUrl = 'https://www.volcengine.com/docs/82379/1544106';

final List<PriceQuote> wp29PriceCatalog = [
  PriceQuote(
    id: 'deepseek-flash-offpeak',
    vendor: 'DeepSeek',
    model: 'deepseek-flash',
    sourceUrl: deepSeekPricingUrl,
    retrievedOn: priceRetrievedOn,
    currency: 'USD',
    inputPerMillion: 0.15,
    cachedInputPerMillion: 0.003,
    outputPerMillion: 0.6,
    condition:
        'Cache-miss input, cache-hit input, and output. Off-peak. '
        'Peak hours on that page are 01:00-04:00 and 06:00-10:00 UTC, '
        'Monday-Friday, excluding Chinese public holidays.',
    kind: QuoteKind.verified,
    note:
        'Page also lists deepseek-v4-pro and says legacy flash names route '
        'to DeepSeek-V4.1-Flash at the flash price. Concurrency limit on '
        'the same row is 2500. Cache-hit is not a cache-write price.',
  ),
  PriceQuote(
    id: 'deepseek-flash-peak',
    vendor: 'DeepSeek',
    model: 'deepseek-flash',
    sourceUrl: deepSeekPricingUrl,
    retrievedOn: priceRetrievedOn,
    currency: 'USD',
    inputPerMillion: 0.3,
    cachedInputPerMillion: 0.006,
    outputPerMillion: 1.2,
    condition: 'Peak window printed on the DeepSeek pricing page.',
    kind: QuoteKind.verified,
    note: 'Off-peak is half of these rates, per that page.',
  ),
  PriceQuote(
    id: 'deepseek-v4-pro-offpeak',
    vendor: 'DeepSeek',
    model: 'deepseek-v4-pro',
    sourceUrl: deepSeekPricingUrl,
    retrievedOn: priceRetrievedOn,
    currency: 'USD',
    inputPerMillion: 0.66,
    cachedInputPerMillion: 0.022,
    outputPerMillion: 1.98,
    condition: 'Off-peak cache-miss input, cache-hit input, and output.',
    kind: QuoteKind.verified,
    note: 'Peak on the same row is 1.32 / 0.044 / 3.96. Concurrency limit 500.',
  ),
  PriceQuote(
    id: 'openai-gpt-6-luna-short',
    vendor: 'OpenAI',
    model: 'gpt-6-luna',
    sourceUrl: openAiPricingUrl,
    retrievedOn: priceRetrievedOn,
    currency: 'USD',
    inputPerMillion: 0.10,
    cachedInputPerMillion: 0.01,
    outputPerMillion: 0.50,
    condition:
        'Standard processing, short-context column. Per 1M tokens. '
        'The fetched table did not print a token cutoff beside the column.',
    kind: QuoteKind.verified,
    note:
        'Same row cache-write column is 0.125 per 1M tokens. This catalog '
        'does not bill cache writes. Long-context column on the same row is '
        '0.20 / 0.02 / 0.25 / 0.75 (input, cached input, cache write, output). '
        'The page says Responses, Chat Completions, Realtime, Batch, and '
        'Assistants are not priced separately.',
  ),
  PriceQuote(
    id: 'openai-gpt-6-luna-long',
    vendor: 'OpenAI',
    model: 'gpt-6-luna',
    sourceUrl: openAiPricingUrl,
    retrievedOn: priceRetrievedOn,
    currency: 'USD',
    inputPerMillion: 0.20,
    cachedInputPerMillion: 0.02,
    outputPerMillion: 0.75,
    condition: 'Standard processing, long-context column. Per 1M tokens.',
    kind: QuoteKind.verified,
    note:
        'Cache-write column is 0.25 per 1M tokens and is not billed here. '
        'Regional processing and FedRAMP are a separate 10% uplift on that '
        'page for models released on or after 2026-03-05.',
  ),
  PriceQuote(
    id: 'anthropic-sonnet-5-5',
    vendor: 'Anthropic',
    model: 'claude-sonnet-5-5',
    sourceUrl: anthropicPricingUrl,
    retrievedOn: priceRetrievedOn,
    currency: 'USD',
    inputPerMillion: 2,
    cachedInputPerMillion: 0.20,
    outputPerMillion: 10,
    condition:
        'Standard. Not batch, not fast mode, not the US inference_geo 1.1x.',
    kind: QuoteKind.verified,
    note:
        'Same row shows 5-minute cache write 2.50 and 1-hour cache write 4 '
        'per 1M tokens. Those writes are not billed by this calculator. '
        'Batch on that page is half of input and output.',
  ),
  PriceQuote(
    id: 'anthropic-haiku-4-5',
    vendor: 'Anthropic',
    model: 'claude-haiku-4-5',
    sourceUrl: anthropicPricingUrl,
    retrievedOn: priceRetrievedOn,
    currency: 'USD',
    inputPerMillion: 1,
    cachedInputPerMillion: 0.10,
    outputPerMillion: 5,
    condition: 'Standard. Not batch and not the US inference_geo 1.1x.',
    kind: QuoteKind.verified,
    note: 'Same row cache writes are 1.25 (5m) and 2 (1h) per 1M tokens.',
  ),
  PriceQuote(
    id: 'anthropic-opus-5-5',
    vendor: 'Anthropic',
    model: 'claude-opus-5-5',
    sourceUrl: anthropicPricingUrl,
    retrievedOn: priceRetrievedOn,
    currency: 'USD',
    inputPerMillion: 4,
    cachedInputPerMillion: 0.20,
    outputPerMillion: 20,
    condition: 'Standard. Not fast mode and not the US inference_geo 1.1x.',
    kind: QuoteKind.verified,
    note:
        'Input and output come from the model row. Cache hit 0.20 is the '
        'page prose: 5% of the 4 USD input price. The table cell for that '
        'hit was blank in the fetch, so this row follows the prose. '
        'Fast mode on the same page is 8 input / 40 output.',
  ),
  PriceQuote(
    id: 'bailian-qwen-plus-beijing-128k',
    vendor: 'Alibaba Cloud Model Studio',
    model: 'qwen-plus',
    sourceUrl: bailianQwenPlusUrl,
    retrievedOn: priceRetrievedOn,
    currency: 'CNY',
    inputPerMillion: 0.8,
    cachedInputPerMillion: 0.16,
    outputPerMillion: 2,
    condition:
        'China (Beijing), input <= 128k tokens, non-thinking, not batch. '
        'List price. The page says promotions are excluded.',
    kind: QuoteKind.verified,
    note:
        'Thinking output on the same table is 8 CNY per 1M tokens and is '
        'not this row. The page says this qwen-plus matches snapshot '
        'qwen-plus-2025-12-01. The fetched page did not show an update '
        'timestamp. Implicit cache hit is 0.16; explicit cache create/hit '
        'are different meters and are not billed here.',
  ),
  PriceQuote(
    id: 'volcengine-doubao-seed-2-1-lite',
    vendor: 'Volcengine Ark',
    model: 'doubao-seed-2.1-lite',
    sourceUrl: volcenginePriceUrl,
    retrievedOn: priceRetrievedOn,
    currency: 'CNY',
    inputPerMillion: 0.80,
    cachedInputPerMillion: 0.16,
    outputPerMillion: 2.70,
    condition:
        'Online inference price table, non-audio input, input-length band '
        '[0, 1024] in the column labeled 千 token.',
    kind: QuoteKind.verified,
    note:
        'Audio input is 12 CNY per 1M tokens on that row and is not used. '
        'Cache storage is 0.017 CNY per 1M tokens per hour and is not used. '
        'The product preset id doubao-pro-32k is a different row.',
  ),
  PriceQuote(
    id: 'preset-doubao-pro-32k',
    vendor: 'Volcengine Ark',
    model: 'doubao-pro-32k',
    sourceUrl: volcenginePriceUrl,
    retrievedOn: priceRetrievedOn,
    currency: 'CNY',
    inputPerMillion: null,
    cachedInputPerMillion: null,
    outputPerMillion: null,
    condition: 'Current product preset id.',
    kind: QuoteKind.unverified,
    note:
        'This id was not on the fetched Ark price table. No number is filled in.',
  ),
];

PriceQuote quoteById(String id) {
  for (final quote in wp29PriceCatalog) {
    if (quote.id == id) return quote;
  }
  throw ArgumentError.value(id, 'id', 'unknown quote');
}
