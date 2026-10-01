# Vendored doc linter

Copied from lupin `src/cosa/repo/doc_lint/` at lupin sha `f4637ecee`, plus
`src/conf/dm-tutor-lowercase-words.txt` (now `tool/data/dm-tutor-lowercase-words.txt`).

Two edits from the original, both in the word-list lookup:
- `word_list.py` reads `tool/data/` instead of the linted tree or `LUPIN_ROOT`; `configure_root` is removed.
- `cli.py` no longer calls `configure_root`.

Everything else is byte-identical. Drift check: compare the sha256 of each source file below with
`sha256sum` of the lupin file at its current sha (word_list.py and cli.py differ by design).

```
9506b08f2a155353fd2dd77f2b6bcb45952a856500be6a55d0cd468af3abab98  dartdoc_lint.py (lupin original)
6a41e8972e2c794cc88373d99bffdc3915835d95453fd74001f689e94e6fe68e  cli.py (lupin original)
2c18e04cf7fe26a8d8c3c74d2da1a8be04c46b7059083a5bd74941089b2b3dbd  text_rules.py (lupin original)
c94b237e2ac1bd081fdb38aa1a72cdae076119525c8a727c4c264c3f01f3a65b  rule_lists.py (lupin original)
92e40182305dacb0c27581b69d79f2d430c3a754692a0bdf83d7710ab9f3abad  word_list.py (lupin original)
0b2c9de71efbd0de0378f38f673a762e94a3b511f883495af67d2adf5d270d50  changed_ranges.py (lupin original)
ea7558d642d34f65ccf4222afb615c0fc0d08dc6615ecdbae02e970ae2815ffe  marker_counts.py (lupin original)
c4369342168ecf025493b69536c74ab978f93341a10d459810af7767cad0644b  dm-tutor-lowercase-words.txt
```
