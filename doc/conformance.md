# Specification conformance

The test suite compares normalized HTML from the Rust parser's intermediate
representation (IR) with the 652 CommonMark 0.31.2 examples and 24 GFM 0.29
extension examples.

## How to run

```sh
flutter test test/conformance
```

The test reports section totals and fails if an example that passed in the
[baseline](../test/conformance/baseline.json) stops passing. Set
`MDX_CONFORMANCE_DUMP=<path>` to save the inputs and HTML diffs. After verifying
newly passing examples, rerun with `MDX_UPDATE_CONFORMANCE=1` and commit the
updated baseline.

Strict comparison normalizes HTML before checking it. Tolerant comparison
also ignores `<p>` directly inside a list item. Both give the same counts in
the results below.

## Results

Measured on 2026-11-18 with the Rust parser.

### CommonMark 0.31.2

Overall: strict 591 / 652 (90.6%), tolerant 591 / 652 (90.6%).

| section | count | strict | tolerant | strict % | tolerant % |
|---|---:|---:|---:|---:|---:|
| Tabs | 11 | 11 | 11 | 100.0% | 100.0% |
| Backslash escapes | 13 | 12 | 12 | 92.3% | 92.3% |
| Entity and numeric character references | 17 | 16 | 16 | 94.1% | 94.1% |
| Precedence | 1 | 1 | 1 | 100.0% | 100.0% |
| Thematic breaks | 19 | 19 | 19 | 100.0% | 100.0% |
| ATX headings | 18 | 18 | 18 | 100.0% | 100.0% |
| Setext headings | 27 | 27 | 27 | 100.0% | 100.0% |
| Indented code blocks | 12 | 12 | 12 | 100.0% | 100.0% |
| Fenced code blocks | 29 | 29 | 29 | 100.0% | 100.0% |
| HTML blocks | 44 | 3 | 3 | 6.8% | 6.8% |
| Link reference definitions | 27 | 27 | 27 | 100.0% | 100.0% |
| Paragraphs | 8 | 8 | 8 | 100.0% | 100.0% |
| Blank lines | 1 | 1 | 1 | 100.0% | 100.0% |
| Block quotes | 25 | 25 | 25 | 100.0% | 100.0% |
| List items | 48 | 48 | 48 | 100.0% | 100.0% |
| Lists | 26 | 26 | 26 | 100.0% | 100.0% |
| Inlines | 1 | 1 | 1 | 100.0% | 100.0% |
| Code spans | 22 | 21 | 21 | 95.5% | 95.5% |
| Emphasis and strong emphasis | 132 | 129 | 129 | 97.7% | 97.7% |
| Links | 90 | 88 | 88 | 97.8% | 97.8% |
| Images | 22 | 22 | 22 | 100.0% | 100.0% |
| Autolinks | 19 | 16 | 16 | 84.2% | 84.2% |
| Raw HTML | 20 | 13 | 13 | 65.0% | 65.0% |
| Hard line breaks | 15 | 13 | 13 | 86.7% | 86.7% |
| Soft line breaks | 2 | 2 | 2 | 100.0% | 100.0% |
| Textual content | 3 | 3 | 3 | 100.0% | 100.0% |

### GFM 0.29 (extensions only)

Overall: strict 23 / 24 (95.8%), tolerant 23 / 24 (95.8%).

| section | count | strict | tolerant |
|---|---:|---:|---:|
| Tables (extension) | 8 | 8 | 8 |
| Task list items (extension) | 2 | 2 | 2 |
| Strikethrough (extension) | 2 | 2 | 2 |
| Autolinks (extension) | 11 | 11 | 11 |
| Disallowed Raw HTML (extension) | 1 | 0 | 0 |


## Classification of failures

| Suite | Cases | What differs |
|---|---:|---|
| CommonMark | 58 | Raw HTML is interpreted under the [HTML policy](html.md). For example, scripts are removed (170), an `<a>` without `href` keeps only its content (613), and supported links are closed (630). Tags outside the allowlist are shown as written, which matches the expected HTML in most cases (201, 524, 536, 617). Some cases also reflect the test serializer, such as the empty `<thead>` it adds to a headerless table (190). |
| CommonMark | 3 | GFM autolinks turn bare URLs and email addresses into links (608, 611, 612). |
| GFM | 1 | The tagfilter fixture (652) expects HTML passthrough with selective escaping. The package instead renders or drops tags according to its HTML policy. |

See [Supported syntax](syntax.md) for feature coverage.
