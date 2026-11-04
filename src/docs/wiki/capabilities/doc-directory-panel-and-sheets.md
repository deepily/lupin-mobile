---
capability: doc-directory-panel-and-sheets
pin_algorithm: py3.13.xebd695/dart-analyzer-parseString/7.7.1
pins:
  - lupin-mobile:lib.features.docs.presentation.doc_directory_view.DocDirectoryView@8d29f24a2e
  - lupin-mobile:lib.features.docs.presentation.doc_directory_view.DocRootsPanel@804aa88f78
  - lupin-mobile:lib.features.docs.presentation.doc_directory_view.DocRoot@20ea51addc
  - lupin-mobile:lib.features.docs.presentation.doc_directory_view.rootsFor@e063af2cc3
  - lupin-mobile:lib.features.docs.presentation.doc_directory_view.formatByteSize@210957b930
  - lupin-mobile:lib.features.docs.presentation.doc_panel.DocPanelPlacement@eac2277a92
  - lupin-mobile:lib.features.docs.presentation.doc_panel.docPanelPlacementFor@2bc23862da
  - lupin-mobile:lib.features.docs.presentation.doc_panel.docPlacementIsChoosable@75d0a81b28
  - lupin-mobile:lib.features.docs.presentation.doc_panel.showDocPanel@5d7e40bf4b
  - lupin-mobile:lib.features.docs.presentation.doc_upload_sheet.pickDocFileWithPlugin@77ddb11f00
  - lupin-mobile:lib.features.docs.presentation.doc_upload_sheet.showDocUploadConflictSheet@a9a828b703
---
# Doc directory, panel and sheets

The folder view, roots panel, panel placement and upload sheets of [[doc-viewer-client]]. The link and upload helpers are on [[doc-links-models-and-upload]].

## What it does
- `DocDirectoryView` lists a folder, folders first and then files in the server's order. A tap opens the entry in place.
- `DocRootsPanel` lists every browsable root. It is folded by default and fetches on its first unfold. `DocRoot` is a label and the link that opens it.
- `rootsFor` puts `io` first. A scope with no prefixes, or a wildcard prefix, is offered at its root. Otherwise it gets one entry per allowed prefix, trailing slash dropped.
- `formatByteSize` prints `n B` under 1 KB, then one decimal of KB, then one decimal of MB.
- `docPanelPlacementFor` returns `bottomHalf` on any screen narrower than 600 logical pixels. At 600 or wider it returns `rightHalf`, unless `belowWhenWide` is set. `docPlacementIsChoosable` is true from 600 up, and only then does the viewer offer the beside-or-below toggle.
- `DocPanelPlacement` has the two values `rightHalf` and `bottomHalf`.
- `showDocPanel` opens a fetchable link in a `DocViewerScreen` over half the screen, with the rest behind a light scrim. A tap on the scrim, the back arrow or the back gesture closes it. It does not read `belowWhenWide`.
- `pickDocFileWithPlugin` opens the system file chooser and returns null if the user backs out or no bytes come back. Setting `platformDocFilePicker` to null hides Upload everywhere.
- `showDocUploadConflictSheet` asks after a 409: Replace, Rename to the suggested name or Cancel. Rename shows only when the server suggested a name, and dismissal returns null.

## Don't
- Don't use width alone to guess an unfolded phone from an aspect ratio. The 600 pixel boundary is Material's compact-to-medium line.
