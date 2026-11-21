/// What one request to an AI model used, as the provider reported it.
class AiCall {
  const AiCall({required this.model, required this.inputTokens, required this.outputTokens});
  final String model;
  final int inputTokens;
  final int outputTokens;

  /// US dollars, from the published per-token price; null when FitTrack doesn't know the
  /// price (Gemini and OpenAI change theirs often, so only tokens are counted for them).
  double? get usd {
    final p = priceFor(model);
    if (p == null) return null;
    return inputTokens / 1e6 * p.$1 + outputTokens / 1e6 * p.$2;
  }
}

/// Anthropic list prices, US$ per million tokens (input, output). Includes the models a
/// declined request can fall back to. Thinking counts as output and is in output_tokens.
const _claudePrices = <String, (double, double)>{
  'claude-haiku-5-5': (0.10, 0.50),
  'claude-sonnet-5-5': (2, 10),
  'claude-opus-5-5': (4, 20),
  'claude-sonnet-5': (2, 10),
  'claude-opus-5': (5, 25),
  'claude-opus-4-8': (5, 25),
  'claude-sonnet-4-6': (3, 15),
  'claude-haiku-4-5': (1, 5),
};

(double, double)? priceFor(String model) {
  // Longest match first, so 'claude-opus-5-5' isn't read as 'claude-opus-5'.
  final keys = _claudePrices.keys.toList()..sort((a, b) => b.length.compareTo(a.length));
  for (final k in keys) {
    if (model.startsWith(k)) return _claudePrices[k];
  }
  return null;
}

/// One photo (or label) sent: all the requests it took, summed. Smart mode can be two.
class AiUsage {
  AiUsage({
    required this.at,
    required this.kind,
    required this.model,
    required this.inputTokens,
    required this.outputTokens,
    this.usd,
  });

  factory AiUsage.ofCalls(String kind, List<AiCall> calls, {DateTime? at}) {
    final priced = calls.every((c) => c.usd != null);
    return AiUsage(
      at: at ?? DateTime.now(),
      kind: kind,
      model: calls.last.model,
      inputTokens: calls.fold(0, (a, c) => a + c.inputTokens),
      outputTokens: calls.fold(0, (a, c) => a + c.outputTokens),
      usd: priced ? calls.fold<double>(0, (a, c) => a + c.usd!) : null,
    );
  }

  final DateTime at;

  /// 'meal' or 'label'.
  final String kind;

  /// The model that gave the final answer.
  final String model;
  final int inputTokens;
  final int outputTokens;
  final double? usd;

  Map<String, dynamic> toJson() => {
    'at': at.millisecondsSinceEpoch,
    'kind': kind,
    'model': model,
    'in': inputTokens,
    'out': outputTokens,
    if (usd != null) 'usd': usd,
  };

  factory AiUsage.fromJson(Map<String, dynamic> j) => AiUsage(
    at: DateTime.fromMillisecondsSinceEpoch((j['at'] as num).toInt()),
    kind: (j['kind'] as String?) ?? 'meal',
    model: (j['model'] as String?) ?? '',
    inputTokens: ((j['in'] as num?) ?? 0).toInt(),
    outputTokens: ((j['out'] as num?) ?? 0).toInt(),
    usd: (j['usd'] as num?)?.toDouble(),
  );
}

/// A typical meal photo (about 1,700 tokens in, 1,500 out with thinking), for a cost estimate
/// before any real photos have been sent. Smart assumes a quarter of photos go on to Opus.
double? estimatedPhotoUsd(String modelId) {
  double cost(String m) => AiCall(model: m, inputTokens: 1700, outputTokens: 1500).usd ?? 0;
  if (modelId == 'claude-smart') return cost('claude-haiku-5-5') + 0.25 * cost('claude-opus-5-5');
  return priceFor(modelId) == null ? null : cost(modelId);
}

/// "0.09¢", "1.8¢", "40¢", "US$1.25".
String formatUsd(double usd) {
  if (usd <= 0) return '0¢';
  if (usd < 0.01) return '${(usd * 100).toStringAsFixed(2)}¢';
  if (usd < 0.1) return '${(usd * 100).toStringAsFixed(1)}¢';
  if (usd < 1) return '${(usd * 100).round()}¢';
  return 'US\$${usd.toStringAsFixed(2)}';
}
