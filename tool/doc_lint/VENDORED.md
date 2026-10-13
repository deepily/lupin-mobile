# Vendored doc linter

Copied from lupin `src/cosa/repo/doc_lint/` at lupin sha `53e7b4980`, plus
`src/conf/dm-tutor-lowercase-words.txt` (now `tool/data/dm-tutor-lowercase-words.txt`).

Entry points: `tool/lint_dart_docs.py` (Dart doc comments) and `tool/lint_markdown.py` (markdown pages).

Two edits from the original, both in the word-list lookup:
- `word_list.py` reads `tool/data/` instead of the linted tree or `LUPIN_ROOT`; `configure_root` is removed.
- `cli.py` no longer imports or calls `configure_root`.

`__init__.py` is this repository's own one-line file. Everything else is byte-identical. Drift check: compare the sha256 of each source file below with
`sha256sum` of the lupin file at its current sha (word_list.py and cli.py differ by design).

```
f31b34f18f6fbc19468d8c8d771cef17d22da14d055e7ffe6f141fa718e3711f  dartdoc_lint.py (lupin original)
2a141c1023c04e8e10285c1a9d84b89eb540d821ce6f9490c7e470eebd98b5a0  md_lint.py (lupin original)
54afabb00536249b663b7b576b15c0af430fb05d2823a66931bafbab5552c59f  links.py (lupin original)
f19075161bbac6f61e049b9151f5543e9ee91b81dd2ede6b91f3c70758d5f097  cli.py (lupin original)
e3bc651346b5b579107e64f79a8f015fcefd37e8603bc41a2210d2f7ddcc0f8b  text_rules.py (lupin original)
f5dec67f3932ddb69a8c1113c412ebc364d968078deff051dfe22abda0e70600  rule_lists.py (lupin original)
f01c16edb38b2c48190f2fb13027696503ba48e6817507b2cb4a7357d78b40eb  word_list.py (lupin original)
86ffcd1a3abcccd2d7b07f56a23726a7202f8839e4565ec67ad5fceceb0560c1  changed_ranges.py (lupin original)
9ad50925f12e0ccb326dd86bab0f2ba224858860d8fa796a608138740bcd8860  marker_counts.py (lupin original)
c4369342168ecf025493b69536c74ab978f93341a10d459810af7767cad0644b  dm-tutor-lowercase-words.txt
```
