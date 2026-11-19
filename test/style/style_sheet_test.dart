import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter/foundation.dart' show DiagnosticableTree;
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart' as plus;
import 'package:flutter_markdown_x/flutter_markdown_x.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../support/sdk_material.dart';

/// Every flutter_markdown field of a style sheet (either package), by name.
Map<String, Object?> _fmFields(dynamic s) => {
  'a': s.a,
  'p': s.p,
  'pPadding': s.pPadding,
  'code': s.code,
  'h1': s.h1,
  'h1Padding': s.h1Padding,
  'h2': s.h2,
  'h2Padding': s.h2Padding,
  'h3': s.h3,
  'h3Padding': s.h3Padding,
  'h4': s.h4,
  'h4Padding': s.h4Padding,
  'h5': s.h5,
  'h5Padding': s.h5Padding,
  'h6': s.h6,
  'h6Padding': s.h6Padding,
  'em': s.em,
  'strong': s.strong,
  'del': s.del,
  'blockquote': s.blockquote,
  'img': s.img,
  'checkbox': s.checkbox,
  'blockSpacing': s.blockSpacing,
  'listIndent': s.listIndent,
  'listBullet': s.listBullet,
  'listBulletPadding': s.listBulletPadding,
  'tableHead': s.tableHead,
  'tableBody': s.tableBody,
  'tableHeadAlign': s.tableHeadAlign,
  'tablePadding': s.tablePadding,
  'tableBorder': s.tableBorder,
  'tableColumnWidth': s.tableColumnWidth,
  'tableScrollbarThumbVisibility': s.tableScrollbarThumbVisibility,
  'tableCellsPadding': s.tableCellsPadding,
  'tableCellsDecoration': s.tableCellsDecoration,
  'tableHeadCellsPadding': s.tableHeadCellsPadding,
  'tableHeadCellsDecoration': s.tableHeadCellsDecoration,
  'tableVerticalAlignment': s.tableVerticalAlignment,
  'blockquotePadding': s.blockquotePadding,
  'blockquoteDecoration': s.blockquoteDecoration,
  'codeblockPadding': s.codeblockPadding,
  'codeblockDecoration': s.codeblockDecoration,
  'horizontalRuleDecoration': s.horizontalRuleDecoration,
  'textAlign': s.textAlign,
  'h1Align': s.h1Align,
  'h2Align': s.h2Align,
  'h3Align': s.h3Align,
  'h4Align': s.h4Align,
  'h5Align': s.h5Align,
  'h6Align': s.h6Align,
  'unorderedListAlign': s.unorderedListAlign,
  'orderedListAlign': s.orderedListAlign,
  'blockquoteAlign': s.blockquoteAlign,
  'codeblockAlign': s.codeblockAlign,
  'superscriptFontFeatureTag': s.superscriptFontFeatureTag,
  'textScaler': s.textScaler,
};

/// The fields that flutter_markdown_plus changed from 0.7.7+1. The default is 0.7.7+1.
const _blockquoteFields = {'blockquotePadding', 'blockquoteDecoration'};

/// Intentional differences of `fromTheme`: the checkbox color is `colorScheme.primary` (not
/// `theme.primaryColor`, which is almost black in a dark theme), and the blockquote box is a dark
/// surface in a dark theme (see the contrast tests below and doc/flutter_markdown_compat.md).
const _intentionalFields = {'checkbox'};

/// A field's full diagnostic description (every property, nested), or `toString` for the rest.
String _describe(Object? value) =>
    value is DiagnosticableTree ? value.toStringDeep() : '$value';

/// `==`, falling back to the full description. `package:material_ui` and `package:cupertino_ui`
/// have their own `MaterialColor` / `CupertinoDynamicColor` (e.g. the link color `Colors.blue`),
/// which never equal the SDK's even with identical channels, because `Color.==` compares the
/// runtime type. The description lists the class and every channel of those colors.
void _expectSameValue(Object? ours, Object? theirs, String reason) {
  if (ours == theirs) return;
  expect(_describe(ours), _describe(theirs), reason: reason);
}

void _expectSameAsPlus(
  MarkdownStyleSheet ours,
  dynamic theirs, {
  Set<String> except = const {},
}) {
  final mine = _fmFields(ours);
  final other = _fmFields(theirs);
  expect(mine.keys, other.keys);
  for (final name in mine.keys) {
    if (_blockquoteFields.contains(name)) continue;
    if (except.contains(name)) continue;
    _expectSameValue(mine[name], other[name], name);
  }
}

class _Subclass extends MarkdownStyleSheet {
  _Subclass() : super(blockSpacing: 1);
}

/// A theme with resolved font sizes, as `MaterialApp` provides to its descendants.
ThemeData _localized(ThemeData theme) =>
    ThemeData.localize(theme, Typography.englishLike2021);

void main() {
  // The same theme in material_ui (ours) and in the SDK (flutter_markdown_plus).
  final themes = <String, ThemePair>{
    'material 3 light': themePair(),
    'material 3 dark': themePair(brightness: Brightness.dark),
    'material 2': themePair(useMaterial3: false),
  };

  group('factories match flutter_markdown_plus', () {
    for (final entry in themes.entries) {
      test('fromTheme (${entry.key})', () {
        final pair = entry.value;
        _expectSameAsPlus(
          MarkdownStyleSheet.fromTheme(pair.ours),
          plus.MarkdownStyleSheet.fromTheme(pair.theirs),
          except: _intentionalFields,
        );
        // The checkbox differs from flutter_markdown in its color only.
        final theirs = plus.MarkdownStyleSheet.fromTheme(pair.theirs);
        expect(
          MarkdownStyleSheet.fromTheme(pair.ours).checkbox,
          (theirs.checkbox as TextStyle).copyWith(
            color: pair.ours.colorScheme.primary,
          ),
        );
      });
      test('largeFromTheme (${entry.key})', () {
        _expectSameAsPlus(
          MarkdownStyleSheet.largeFromTheme(entry.value.ours),
          plus.MarkdownStyleSheet.largeFromTheme(entry.value.theirs),
          except: _intentionalFields,
        );
      });
    }

    for (final brightness in Brightness.values) {
      test('fromCupertinoTheme (${brightness.name})', () {
        _expectSameAsPlus(
          MarkdownStyleSheet.fromCupertinoTheme(
            CupertinoThemeData(brightness: brightness),
          ),
          plus.MarkdownStyleSheet.fromCupertinoTheme(
            sdkCupertinoTheme(brightness),
          ),
        );
      });
    }

    test('blockquote constants of fromTheme are those of 0.7.7+1', () {
      final sheet = MarkdownStyleSheet.fromTheme(_localized(ThemeData()));
      expect(sheet.blockquotePadding, const EdgeInsets.all(8.0));
      expect(
        sheet.blockquoteDecoration,
        BoxDecoration(
          color: Colors.blue.shade100,
          borderRadius: BorderRadius.circular(2.0),
        ),
      );
      final large = MarkdownStyleSheet.largeFromTheme(_localized(ThemeData()));
      expect(large.blockquotePadding, sheet.blockquotePadding);
      expect(large.blockquoteDecoration, sheet.blockquoteDecoration);
    });

    group('contrast in dark themes', () {
      // WCAG contrast ratio of two opaque colors.
      double contrast(Color a, Color b) {
        final l1 = a.computeLuminance();
        final l2 = b.computeLuminance();
        final hi = l1 > l2 ? l1 : l2;
        final lo = l1 > l2 ? l2 : l1;
        return (hi + 0.05) / (lo + 0.05);
      }

      // The minimum for graphical objects such as the checkbox icon (WCAG 1.4.11).
      const graphicMin = 3.0;
      // The minimum for body text (WCAG 1.4.3, AA).
      const textMin = 4.5;

      final darkThemes = <String, ThemeData>{
        'material 3 dark': _localized(ThemeData.dark(useMaterial3: true)),
        'material 2 dark': _localized(ThemeData.dark(useMaterial3: false)),
        'material 3 dark seeded': _localized(
          ThemeData(
            useMaterial3: true,
            colorSchemeSeed: Colors.teal,
            brightness: Brightness.dark,
          ),
        ),
      };
      for (final entry in darkThemes.entries) {
        final theme = entry.value;
        final background = theme.scaffoldBackgroundColor;
        test('checkbox is visible on the scaffold (${entry.key})', () {
          for (final sheet in [
            MarkdownStyleSheet.fromTheme(theme),
            MarkdownStyleSheet.largeFromTheme(theme),
          ]) {
            expect(
              contrast(sheet.checkbox!.color!, background),
              greaterThanOrEqualTo(graphicMin),
            );
          }
        });
        test('blockquote text is readable on its box (${entry.key})', () {
          final sheet = MarkdownStyleSheet.fromTheme(theme);
          final box = (sheet.blockquoteDecoration! as BoxDecoration).color!;
          final text = sheet.blockquote!.color!;
          expect(contrast(text, box), greaterThanOrEqualTo(textMin));
        });
        test(
          'link color stays distinguishable on the scaffold (${entry.key})',
          () {
            final sheet = MarkdownStyleSheet.fromTheme(theme);
            expect(
              contrast(sheet.a!.color!, background),
              greaterThanOrEqualTo(graphicMin),
            );
          },
        );
      }

      test(
        'checkbox of fromCupertinoTheme is visible on a dark background',
        () {
          final theme = CupertinoThemeData(brightness: Brightness.dark);
          final sheet = MarkdownStyleSheet.fromCupertinoTheme(theme);
          final background = CupertinoColors.systemBackground.darkColor;
          expect(
            contrast(sheet.checkbox!.color!, background),
            greaterThanOrEqualTo(graphicMin),
          );
        },
      );

      test('light themes keep the flutter_markdown blockquote box', () {
        final sheet = MarkdownStyleSheet.fromTheme(
          _localized(ThemeData(useMaterial3: true)),
        );
        expect(
          (sheet.blockquoteDecoration! as BoxDecoration).color,
          Colors.blue.shade100,
        );
      });
    });

    test('fromTheme sets the extensions from the theme', () {
      final light = MarkdownStyleSheet.fromTheme(_localized(ThemeData.light()));
      final dark = MarkdownStyleSheet.fromTheme(_localized(ThemeData.dark()));
      expect(light.codeSyntax, MarkdownXSyntaxColors.light);
      expect(dark.codeSyntax, MarkdownXSyntaxColors.dark);
      expect(light.alerts, MarkdownXAlertStyle.light);
      expect(dark.alerts, MarkdownXAlertStyle.dark);
      expect(light.mark?.backgroundColor, isNotNull);
      expect(light.citation, isNotNull);
      expect(light.codeBlockOptions, isNull);
      expect(light.listItemSpacing, isNull);
    });
  });

  group('styles', () {
    test('has exactly the 19 flutter_markdown keys', () {
      final sheet = MarkdownStyleSheet.fromTheme(_localized(ThemeData()));
      expect(sheet.styles.keys.toSet(), {
        'a',
        'p',
        'li',
        'code',
        'pre',
        'h1',
        'h2',
        'h3',
        'h4',
        'h5',
        'h6',
        'em',
        'strong',
        'del',
        'blockquote',
        'img',
        'table',
        'th',
        'tr',
        'td',
      });
      expect(sheet.styles['li'], sheet.p);
      expect(sheet.styles['th'], sheet.tableHead);
      expect(sheet.styles['td'], sheet.tableBody);
      expect(sheet.styles['sub'], isNull);
    });
  });

  group('copyWith', () {
    final base = MarkdownStyleSheet.fromTheme(_localized(ThemeData()));

    test('keeps every field without arguments', () {
      expect(base.copyWith(), base);
    });

    test('carries tableScrollbarThumbVisibility over', () {
      final sheet = MarkdownStyleSheet(tableScrollbarThumbVisibility: true);
      expect(
        sheet.copyWith(blockSpacing: 3).tableScrollbarThumbVisibility,
        true,
      );
      expect(
        sheet
            .copyWith(tableScrollbarThumbVisibility: false)
            .tableScrollbarThumbVisibility,
        false,
      );
    });

    test('carries the extensions over and replaces them', () {
      final sheet = base.copyWith(listItemSpacing: 5, mark: const TextStyle());
      final next = sheet.copyWith(blockSpacing: 1);
      expect(next.listItemSpacing, 5);
      expect(next.mark, const TextStyle());
      expect(next.copyWith(listItemSpacing: 6).listItemSpacing, 6);
      const fade = Duration(milliseconds: 90);
      expect(
        base
            .copyWith(imageFadeInDuration: fade)
            .copyWith(blockSpacing: 1)
            .imageFadeInDuration,
        fade,
      );
      expect(
        base
            .copyWith(
              codeBlockOptions: const MarkdownXCodeBlockOptions(
                showLanguage: true,
              ),
            )
            .codeBlockOptions,
        const MarkdownXCodeBlockOptions(showLanguage: true),
      );
    });

    test(
      'textScaler and the deprecated textScaleFactor exclude each other',
      () {
        // ignore: deprecated_member_use_from_same_package
        final byFactor = MarkdownStyleSheet(textScaleFactor: 2);
        expect(byFactor.textScaler, const TextScaler.linear(2));
        final replaced = byFactor.copyWith(textScaler: TextScaler.noScaling);
        expect(replaced.textScaler, TextScaler.noScaling);
        // ignore: deprecated_member_use_from_same_package
        expect(replaced.textScaleFactor, isNull);
        expect(
          () => MarkdownStyleSheet(
            // ignore: deprecated_member_use_from_same_package
            textScaleFactor: 2,
            textScaler: TextScaler.noScaling,
          ),
          throwsAssertionError,
        );
      },
    );
  });

  group('merge', () {
    test('returns the same sheet for null', () {
      final sheet = MarkdownStyleSheet.fromTheme(_localized(ThemeData()));
      expect(identical(sheet.merge(null), sheet), isTrue);
    });

    test('merges text styles and replaces the other fields', () {
      final base = MarkdownStyleSheet.fromTheme(_localized(ThemeData()));
      final merged = base.merge(
        MarkdownStyleSheet(
          a: const TextStyle(fontSize: 31),
          blockSpacing: 3,
          blockquotePadding: const EdgeInsets.all(1),
        ),
      );
      expect(merged.a?.fontSize, 31);
      expect(merged.a?.color, Colors.blue);
      expect(merged.blockSpacing, 3);
      expect(merged.blockquotePadding, const EdgeInsets.all(1));
      // A field that the other sheet leaves null keeps the base value.
      expect(merged.listIndent, base.listIndent);
      expect(merged.tableColumnWidth, base.tableColumnWidth);
    });

    test('does not throw when a base text style is null', () {
      final merged = MarkdownStyleSheet().merge(
        MarkdownStyleSheet(a: const TextStyle(fontSize: 2)),
      );
      expect(merged.a, const TextStyle(fontSize: 2));
    });

    test('keeps the base text scaler unless the other one sets it', () {
      final base = MarkdownStyleSheet(textScaler: const TextScaler.linear(1.5));
      expect(
        base.merge(MarkdownStyleSheet()).textScaler,
        const TextScaler.linear(1.5),
      );
      expect(
        base
            .merge(MarkdownStyleSheet(textScaler: TextScaler.noScaling))
            .textScaler,
        TextScaler.noScaling,
      );
    });

    test('merges the extensions', () {
      final base = MarkdownStyleSheet(
        mark: const TextStyle(fontSize: 1),
        listItemSpacing: 2,
      );
      final merged = base.merge(
        MarkdownStyleSheet(
          mark: const TextStyle(fontSize: 5),
          listItemSpacing: 7,
        ),
      );
      expect(merged.mark?.fontSize, 5);
      expect(merged.listItemSpacing, 7);
      expect(base.merge(MarkdownStyleSheet()).listItemSpacing, 2);
      const fade = Duration(milliseconds: 90);
      expect(
        base
            .merge(MarkdownStyleSheet(imageFadeInDuration: fade))
            .imageFadeInDuration,
        fade,
      );
    });
  });

  group('equality', () {
    test('imageFadeInDuration takes part in equality', () {
      expect(
        MarkdownStyleSheet(imageFadeInDuration: Duration.zero),
        isNot(MarkdownStyleSheet()),
      );
      expect(
        MarkdownStyleSheet(imageFadeInDuration: Duration.zero),
        MarkdownStyleSheet(imageFadeInDuration: Duration.zero),
      );
    });

    test('two sheets built from the same theme are equal', () {
      final a = MarkdownStyleSheet.fromTheme(_localized(ThemeData()));
      final b = MarkdownStyleSheet.fromTheme(_localized(ThemeData()));
      expect(identical(a, b), isFalse);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a.copyWith(blockSpacing: 10), a.copyWith(blockSpacing: 10));
    });

    test('a changed field makes the sheets different', () {
      final a = MarkdownStyleSheet.fromTheme(_localized(ThemeData()));
      expect(a.copyWith(blockSpacing: 11), isNot(a));
      expect(a.copyWith(tableScrollbarThumbVisibility: true), isNot(a));
    });

    test('every extension takes part in == and hashCode', () {
      final a = MarkdownStyleSheet.fromTheme(_localized(ThemeData()));
      final variants = <MarkdownStyleSheet>[
        a.copyWith(mark: const TextStyle(fontSize: 3)),
        a.copyWith(codeSyntax: MarkdownXSyntaxColors.monokai),
        a.copyWith(
          codeBlockOptions: const MarkdownXCodeBlockOptions(
            showCopyButton: true,
          ),
        ),
        a.copyWith(alerts: MarkdownXAlertStyle.dark),
        a.copyWith(
          citation: const MarkdownXCitationStyle(
            background: Color(0xFF000000),
            foreground: Color(0xFFFFFFFF),
          ),
        ),
        a.copyWith(listItemSpacing: 3),
      ];
      for (final variant in variants) {
        expect(variant, isNot(a));
        expect(variant.hashCode, isNot(a.hashCode));
      }
    });

    test('a subclass is never equal', () {
      final sub = _Subclass();
      expect(sub == MarkdownStyleSheet(blockSpacing: 1), isFalse);
      expect(MarkdownStyleSheet(blockSpacing: 1) == sub, isFalse);
      expect(sub == sub, isTrue);
    });
  });
}
