import 'package:flutter/material.dart';

import 'build_info.dart';
import 'testing/test_keys.dart';

/// The drawer's two-line build footer: branch above, date, build number and commit below.
///
/// The branch line is cut with an ellipsis when it does not fit.
/// The detail line shrinks to fit and is never cut, so the build number and commit stay readable.
/// Design: src/scripts/build-apk-on-server.sh
class BuildInfoFooter extends StatelessWidget {
  /// The build to describe; the app passes [BuildInfo.current], tests pass explicit values.
  final BuildInfo info;

  /// Creates the footer for [info].
  const BuildInfoFooter( { super.key, required this.info } );

  @override
  Widget build( BuildContext context ) {
    final style  = Theme.of( context ).textTheme.bodySmall;
    final detail = info.detailLine();
    return Align(
      alignment : Alignment.centerLeft,
      child     : Column(
        mainAxisSize       : MainAxisSize.min,
        crossAxisAlignment : CrossAxisAlignment.start,
        children : [
          Text(
            info.branchLine(),
            key      : const Key( TestKeys.focusDrawerBuildLine ),
            style    : style,
            maxLines : 1,
            overflow : TextOverflow.ellipsis,
          ),
          if ( detail.isNotEmpty )
            FittedBox(
              fit       : BoxFit.scaleDown,
              alignment : Alignment.centerLeft,
              child     : Text(
                detail,
                key      : const Key( TestKeys.focusDrawerBuildDetail ),
                style    : style,
                maxLines : 1,
                softWrap : false,
              ),
            ),
        ],
      ),
    );
  }
}
