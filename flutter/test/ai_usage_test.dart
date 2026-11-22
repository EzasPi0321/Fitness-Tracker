import 'package:fittrack/data/app_state.dart';
import 'package:fittrack/models/ai_usage.dart';
import 'package:fittrack/services/ai_vision.dart';
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

  test('formats costs in dollars, never cents', () {
    expect(formatUsd(0.0003), 'less than US\$0.01');
    expect(formatUsd(0.018), 'US\$0.02');
    expect(formatUsd(0.4), 'US\$0.40');
    expect(formatUsd(1.25), 'US\$1.25');
    expect(formatUsd(0), 'US\$0.00');
  });

  test('plain water goes to the Water card; watermelon and coconut water don’t', () {
    DetectedFood f(String name, double kcal) =>
        DetectedFood(name: name, grams: 600, calories: kcal, protein: 0, carbs: 0, fat: 0, confidence: 0.9);
    expect(f('Mount Franklin bottled spring water', 0).isPlainWater, isTrue);
    expect(f('Sparkling water', 0).isPlainWater, isTrue);
    expect(f('Watermelon slice', 90).isPlainWater, isFalse);
    expect(f('Coconut water', 110).isPlainWater, isFalse);
    expect(f('Vitamin water', 0).isPlainWater, isFalse);
  });
}
