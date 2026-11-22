import 'package:fittrack/data/app_state.dart';
import 'package:fittrack/models/ai_usage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('prices match the longest model id', () {
    expect(priceFor('claude-opus-5-5'), (4.0, 20.0));
    expect(priceFor('claude-opus-5'), (5.0, 25.0));
    expect(priceFor('gemini-2.5-flash'), isNull);
  });

  test('a Smart photo sums both requests', () {
    final u = AiUsage.ofCalls('meal', const [
      AiCall(model: 'claude-haiku-5-5', inputTokens: 1000000, outputTokens: 0),
      AiCall(model: 'claude-opus-5-5', inputTokens: 0, outputTokens: 1000000),
    ]);
    expect(u.usd, closeTo(20.10, 1e-9));
    expect(u.model, 'claude-opus-5-5');
    final back = AiUsage.fromJson(u.toJson());
    expect(back.usd, closeTo(20.10, 1e-9));
    expect(back.inputTokens, 1000000);
  });

  test('unknown prices stay unpriced', () {
    final u = AiUsage.ofCalls('meal', const [AiCall(model: 'gpt-x', inputTokens: 10, outputTokens: 10)]);
    expect(u.usd, isNull);
  });

  test('balance counts down and gives photos left', () {
    final s = AppState();
    s.setAiBalance(1.0);
    for (var i = 0; i < 4; i++) {
      s.recordAiUsage('meal', const [AiCall(model: 'claude-opus-5-5', inputTokens: 0, outputTokens: 5000)]);
    }
    // Each photo is 10¢; 40¢ spent of US$1.
    expect(s.costPerPhotoUsd, closeTo(0.10, 1e-9));
    expect(s.costPerPhotoIsMeasured, isTrue);
    expect(s.aiBalanceLeftUsd, closeTo(0.60, 1e-9));
    expect(s.photosLeft, 5);
  });

  test('formats small amounts in cents', () {
    expect(formatUsd(0.0009), '0.09¢');
    expect(formatUsd(0.018), '1.8¢');
    expect(formatUsd(0.4), '40¢');
    expect(formatUsd(1.25), 'US\$1.25');
  });
}
