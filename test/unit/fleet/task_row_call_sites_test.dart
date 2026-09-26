import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 🔴 AN OPTIONAL NAMED ARGUMENT CAN VANISH AND NOTHING NOTICES. Row d5bbd786.
///
/// Measured twice on 2026-09-23: the Holding Area lost `unsentLabel` in a rebase, and
/// the Task List's could be deleted with all 1902 tests green. Dart does not object
/// (the argument is optional), git does not conflict (the whole expression was
/// replaced), and bloc tests do not redden (they assert state, not what the row wears).
///
/// ⇒ This scans every `TaskRow(` call in `lib/` and requires each constructor
/// parameter to be either PASSED or OPTED OUT with a reason, on the line above the call
/// or inside its argument list:
///
/// ```dart
/// // taskrow-omit: unsentLabel a lookup result is read-only, nothing is ever unsent
/// TaskRow( model: row ),
/// ```
///
/// A new parameter on `TaskRow` therefore turns this red at every call site until each
/// one decides, in writing, whether it wants it.
///
/// ⚠️ WHY A SOURCE SCAN. Flutter has no runtime reflection, and a widget test only
/// sees what one pane renders. The question here is about the SOURCE of every caller.

final _sharedTaskRowCall = RegExp(r"(?<![A-Za-z0-9_])TaskRow\s*\(");
final _optOut = RegExp(r"//\s*taskrow-omit:\s*(\w+)[ \t]*([^\n]*)");

/// The parameter names of `TaskRow`'s constructor, minus `key`.
Set<String> constructorParams(String taskRowSource) {
  final ctor = RegExp(r"const\s+TaskRow\s*\(\s*\{([\s\S]*?)\}\s*\)").firstMatch(taskRowSource);
  if (ctor == null) return <String>{};
  return RegExp(r"this\.(\w+)").allMatches(ctor.group(1)!).map((m) => m.group(1)!).toSet();
}

/// One `TaskRow(` call: the arguments it passes and the opt-outs that cover it.
class CallSite {
  final String where;
  final Set<String> passed;
  final Map<String, String> optOuts;

  CallSite(this.where, this.passed, this.optOuts);
}

/// Every `TaskRow(` call in [source], skipping ones inside `//` comments.
List<CallSite> callSites(String source, String path) {
  final sites = <CallSite>[];
  for (final m in _sharedTaskRowCall.allMatches(source)) {
    final lineStart = source.lastIndexOf("\n", m.start) + 1;
    if (source.substring(lineStart, m.start).contains("//")) continue;

    final args = _argumentText(source, m.end);
    final line = "\n".allMatches(source.substring(0, m.start)).length + 1;

    final optOuts = <String, String>{};
    for (final o in _optOut.allMatches(_commentBlockAbove(source, lineStart) + "\n" + args)) {
      optOuts[o.group(1)!] = o.group(2)!.trim();
    }
    sites.add(CallSite("$path:$line", _namedArguments(args), optOuts));
  }
  return sites;
}

/// The text between the call's `(` (ending at [openEnd]) and its matching `)`.
String _argumentText(String source, int openEnd) {
  var depth = 1;
  for (var i = openEnd; i < source.length; i++) {
    final c = source[i];
    if (c == "(" || c == "[" || c == "{") depth++;
    if (c == ")" || c == "]" || c == "}") depth--;
    if (depth == 0) return source.substring(openEnd, i);
  }
  return source.substring(openEnd);
}

/// The contiguous `//` lines directly above the line starting at [lineStart].
String _commentBlockAbove(String source, int lineStart) {
  final lines = source.substring(0, lineStart).split("\n");
  final block = <String>[];
  for (var i = lines.length - 1; i >= 0; i--) {
    final t = lines[i].trim();
    if (t.isEmpty && block.isEmpty) continue;
    if (!t.startsWith("//")) break;
    block.insert(0, t);
  }
  return block.join("\n");
}

/// The names of the TOP-LEVEL named arguments in [args]. A nested call's arguments
/// (`bloc.add( Foo( id: x ) )`) are not this call's, so depth is tracked.
Set<String> _namedArguments(String args) {
  final code = args.replaceAll(RegExp(r"//[^\n]*"), "");
  final segments = <String>[];
  var depth = 0;
  var start = 0;
  for (var i = 0; i < code.length; i++) {
    final c = code[i];
    if (c == "(" || c == "[" || c == "{") depth++;
    if (c == ")" || c == "]" || c == "}") depth--;
    if (c == "," && depth == 0) {
      segments.add(code.substring(start, i));
      start = i + 1;
    }
  }
  segments.add(code.substring(start));
  return segments
      .map((s) => RegExp(r"^\s*(\w+)\s*:").firstMatch(s)?.group(1))
      .whereType<String>()
      .toSet();
}

/// Every complaint about [site] against [params]. Empty means the call site is honest.
List<String> complaints(CallSite site, Set<String> params) {
  final out = <String>[];
  for (final p in params.difference(site.passed)) {
    final why = site.optOuts[p];
    if (why == null) {
      out.add("${site.where} omits `$p` with no `// taskrow-omit: $p <why>`");
    } else if (why.isEmpty) {
      out.add("${site.where} opts out of `$p` without saying why");
    }
  }
  for (final p in site.optOuts.keys) {
    if (!params.contains(p)) out.add("${site.where} opts out of `$p`, which TaskRow does not have");
    if (site.passed.contains(p)) out.add("${site.where} opts out of `$p` but passes it");
  }
  return out;
}

void main() {
  const params = {"model", "verbs", "unsentLabel"};

  // 🔴 THE SCANNER IS TESTED ON ITS OWN, BECAUSE A GUARD THAT MATCHES NOTHING PASSES.
  group("the scanner", () {
    test("reads the constructor's parameters, and not key", () {
      const src = "const TaskRow( {\n  super.key,\n  required this.model,\n  this.verbs = const [],\n} );";
      expect(constructorParams(src), {"model", "verbs"});
    });

    test("an omitted argument with no opt-out is a complaint", () {
      final site = callSites("x = TaskRow( model: m, verbs: v );", "f.dart").single;
      expect(complaints(site, params), [contains("omits `unsentLabel`")]);
    });

    test("an opt-out on the line above covers the omission", () {
      const src = "// taskrow-omit: unsentLabel read-only\n// taskrow-omit: verbs read-only\nTaskRow( model: m )";
      expect(complaints(callSites(src, "f.dart").single, params), isEmpty);
    });

    test("an opt-out with no reason is a complaint", () {
      const src = "// taskrow-omit: unsentLabel\n// taskrow-omit: verbs read-only\nTaskRow( model: m )";
      expect(complaints(callSites(src, "f.dart").single, params), [contains("without saying why")]);
    });

    test("a stale opt-out is a complaint: unknown name, or an argument that is passed", () {
      const src = "// taskrow-omit: pane gone\n// taskrow-omit: verbs x\nTaskRow( model: m, verbs: v, unsentLabel: u )";
      expect(complaints(callSites(src, "f.dart").single, params), hasLength(2));
    });

    test("a nested call's named arguments are not this call's", () {
      const src = "TaskRow( model: m, onVerb: (v) => add( Foo( verbs: v, unsentLabel: u ) ) )";
      expect(callSites(src, "f.dart").single.passed, {"model", "onVerb"});
    });

    test("a comment inside the argument list does not read as an argument", () {
      const src = "TaskRow(\n  // G6: the row wears it\n  model: m,\n)";
      expect(callSites(src, "f.dart").single.passed, {"model"});
    });

    test("a call written in a // comment is not a call site, and FinishedTaskRow is not TaskRow", () {
      expect(callSites("/// TaskRow( model: row, pane: p )", "f.dart"), isEmpty);
      expect(callSites("FinishedTaskRow( model: m )", "f.dart"), isEmpty);
    });
  });

  test("every TaskRow call in lib/ passes each parameter or says why not", () {
    final real = constructorParams(
        File("lib/features/fleet/presentation/task_row.dart").readAsStringSync());
    // A floor, so a constructor the regex stops recognising cannot pass as "no params".
    expect(real, containsAll(["model", "verbs", "onVerb", "onFieldChanged", "ownerOptions", "unsentLabel"]));

    final sites = Directory("lib")
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith(".dart"))
        // The definition's own `const TaskRow( {` would read as a call with no arguments.
        .where((f) => !f.path.endsWith("fleet/presentation/task_row.dart"))
        .expand((f) => callSites(f.readAsStringSync(), f.path))
        .toList();
    // Task List, Holding Area and the ticket lookup today. Fewer means the scan broke.
    expect(sites.length, greaterThanOrEqualTo(3), reason: "the scan found too few call sites");

    final found = sites.expand((s) => complaints(s, real)).toList();
    expect(found, isEmpty, reason: found.join("\n"));
  });
}
