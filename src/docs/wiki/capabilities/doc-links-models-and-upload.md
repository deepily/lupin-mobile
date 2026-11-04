---
capability: doc-links-models-and-upload
pin_algorithm: py3.13.xebd695/dart-analyzer-parseString/7.7.1
pins:
  - lupin-mobile:lib.features.docs.data.doc_link.hasFetchableDocLink@c842a3f2eb
  - lupin-mobile:lib.features.docs.data.doc_link.docLinkFor@c87f0bef05
  - lupin-mobile:lib.features.docs.data.doc_link.folderLinkFor@5a3a9af9e4
  - lupin-mobile:lib.features.docs.data.doc_models.DocContent@b8c16c8efa
  - lupin-mobile:lib.features.docs.data.doc_models.DocDirectoryEntry@b0d7b6764f
  - lupin-mobile:lib.features.docs.data.doc_models.DocDirectoryListing@add8aa51e3
  - lupin-mobile:lib.features.docs.data.doc_models.DocScope@29780d433b
  - lupin-mobile:lib.features.docs.data.doc_upload.DocUploadConflictMode@a425870d12
  - lupin-mobile:lib.features.docs.data.doc_upload.PickedDocFile@9c5ec33d0f
  - lupin-mobile:lib.features.docs.data.doc_upload.DocUploadResult@ffafcb2f9a
  - lupin-mobile:lib.features.docs.data.doc_upload.uploadDirFor@f77018d054
  - lupin-mobile:lib.features.docs.data.doc_upload.isIoScope@08108dd254
---
# Doc links, models and upload

The link builders, content models and upload helpers behind [[doc-viewer-client]]. The directory and roots views are on [[doc-directory-panel-and-sheets]].

## What it does
- `hasFetchableDocLink` is true when an abstract has at least one link the app would fetch, so the card badge shows only then.
- `docLinkFor` builds a browse link for a scope and relative path. The `io` scope gives `/api/io/file` with `.` for its root, because that route needs a non-empty path. Any other scope gives `/api/docs/file?path=<scope>/<rel>`.
- `folderLinkFor` gives the folder holding a link's file. A top-level file gives the scope root, and an external or unknown link gives null.
- `DocContent` holds a fetched document: kind, media type verbatim, decoded text, raw bytes and a listing. Download saves the bytes, so markdown saves its source.
- `DocDirectoryEntry` reads `kind` and `rel_path`, with the older `type` and `path` as fallbacks. `DocDirectoryListing` holds the path, scope, parent and entries; a missing entry list is empty.
- `DocScope` is a registered root and its allowed prefixes, from `/api/docs/scopes`. The `io` root is not in that list.
- `DocUploadConflictMode` is refuse, replace or rename. `PickedDocFile` is a name and in-memory bytes. `DocUploadResult` reads path, name, size and `replaced`.
- `uploadDirFor` makes the `dir` field, `<scope>` or `<scope>/<path>` with no trailing slash. `isIoScope` keeps the `io` name in one place.

## Don't
- Don't follow an entry's `view_url` when browsing. For an io mp3 it is a web audio page, and a pdf's has no project segment.
- Don't treat `tokenHasAdminRole` as a gate. It only decides whether Upload is offered, and the server decides whether it works.
