import 'package:flutter_test/flutter_test.dart';

import 'prefixes.dart';

void main() {
  group('prefixEnds', () {
    test('yields every position 0..length for ordinary text', () {
      const source = '# Title\n\nhello **world**\n';
      expect(prefixEnds(source).toList(), [
        for (var i = 0; i <= source.length; i++) i,
      ]);
    });

    test('thins a long base64 data URI payload to a few positions', () {
      final payload = 'A' * 5000;
      final source = 'x ![a](data:image/png;base64,$payload) y';
      final start = source.indexOf(payload);
      final end = start + payload.length;
      final ends = prefixEnds(source).toList();
      expect(ends, orderedEquals([...ends]..sort()));
      expect(ends.toSet().length, ends.length);
      final inside = ends.where((e) => e > start && e < end).toList();
      expect(inside.length, lessThanOrEqualTo(3));
      expect(
        ends,
        containsAll([start, start + 1, (start + end) ~/ 2, end - 1, end]),
      );
      // Everything outside the payload is still visited.
      expect(ends.where((e) => e <= start).length, start + 1);
      expect(ends.where((e) => e >= end).length, source.length - end + 1);
      expect(ends.first, 0);
      expect(ends.last, source.length);
    });

    test('thins any long run of base64 characters', () {
      final run = 'Ab+/' * 100;
      final source = 'token $run end';
      final ends = prefixEnds(source).toList();
      expect(ends.length, lessThan(source.length ~/ 4));
    });

    test('keeps runs of at most 64 characters untouched', () {
      final source = 'k ${'a' * 64} k';
      expect(prefixEnds(source).length, source.length + 1);
    });
  });
}
