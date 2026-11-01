import 'package:flutter_test/flutter_test.dart';
import 'package:lupin_mobile/features/docs/data/task_link.dart';

const _id = 'a25f51b3-8c0e-4f58-a1f8-f189e250d36c';

void main() {
  group( 'classifyTaskHref', () {
    test( 'an approve address is an approve link, whatever the label', () {
      final link = classifyTaskHref( '/app/tasks/approve?row=$_id' );
      expect( link!.kind, TaskLinkKind.approve );
      expect( link.id,    _id );
    } );

    test( 'a view address is a view link', () {
      expect( classifyTaskHref( '/app/tasks/view?row=$_id' )!.kind, TaskLinkKind.view );
    } );

    test( 'anything else is not a task link', () {
      for ( final href in <String?>[
        null, '', '/app/docs?path=a/b.md', '/app/tasks/approve', '/app/tasks/approve?row=',
        '/app/tasks/approve?row=a25f51b3', '/app/tasks/approve?row=${_id}x',
        '/app/tasks/other?row=$_id', 'https://x.test/app/tasks/approve?row=$_id',
      ] ) {
        expect( classifyTaskHref( href ), isNull, reason: '$href' );
      }
    } );
  } );
}
