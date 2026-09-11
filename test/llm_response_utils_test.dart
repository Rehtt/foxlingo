import 'package:flutter_test/flutter_test.dart';
import 'package:foxlingo/utils/llm_response_utils.dart';

void main() {
  test('stripThinkTags removes a complete think block', () {
    expect(
      LlmResponseUtils.stripThinkTags(
        '<think>planning the answer</think>\nwolf\nfantasy',
      ),
      'wolf\nfantasy',
    );
  });

  test('stripThinkTags drops text before a leftover closing tag', () {
    expect(
      LlmResponseUtils.stripThinkTags(
        'internal monologue</think>\n{"bbox":[0,0,1,1]}',
      ),
      '{"bbox":[0,0,1,1]}',
    );
  });

  test('stripThinkTags drops an unclosed opening tag and the rest', () {
    expect(
      LlmResponseUtils.stripThinkTags('keep this\n<think>truncated'),
      'keep this',
    );
  });

  test('stripThinkTags leaves text without tags unchanged', () {
    expect(LlmResponseUtils.stripThinkTags('  title\nbody  '), 'title\nbody');
  });

  test('stripThinkTags then stripCodeFence handles a fenced answer', () {
    final stripped = LlmResponseUtils.stripThinkTags(
      '<think>reason</think>\n```json\n[]\n```',
    );
    expect(LlmResponseUtils.stripCodeFence(stripped), '[]');
  });
}
