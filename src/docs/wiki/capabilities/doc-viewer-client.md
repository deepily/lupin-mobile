---
capability: doc-viewer-client
pin_algorithm: py3.13.xebd695/dart-analyzer-parseString/7.7.1
pins:
  - lupin-mobile:lib.features.docs.data.doc_link.DocLinkKind@8f096e7578
  - lupin-mobile:lib.features.docs.data.doc_link.classifyDocHref@1f78b1f2fd
  - lupin-mobile:lib.features.docs.data.doc_link.parseDocLinks@7e1176ccd1
  - lupin-mobile:lib.features.docs.data.doc_repository.DocRepository@5bcbc8f475
  - lupin-mobile:lib.features.docs.data.doc_models.DocContentKind@357188f661
  - lupin-mobile:lib.features.docs.presentation.doc_viewer_screen.DocViewerScreen@2f0f965036
  - lupin-mobile:lib.features.docs.presentation.doc_split_host.DocSplitHost@8af502830a
  - lupin-mobile:lib.features.docs.presentation.doc_link_tap.openMarkdownHref@43bea31860
  - lupin-mobile:lib.features.docs.data.doc_upload.tokenHasAdminRole@16c14af818
  - lupin-mobile:lib.features.docs.data.doc_upload.DocUploadConflict@3b7a4da05c
  - lupin-mobile:lib.features.docs.presentation.abstract_body.AbstractBody@0ebcb6b10d
  - lupin-mobile:lib.features.docs.presentation.doc_split_host.DocSplitHostState@bc10e3006e
  - lupin-mobile:lib.features.docs.data.doc_link.DocLink@7b51c86621
  - lupin-mobile:lib.features.docs.data.doc_models.DocApiException@5c7e686ceb
---
# Doc viewer client

Opens a repo document or an `io/` file from a notification's abstract link, and browses folders. It renders the server's raw bytes natively. The server half is lupin's `doc-viewer` page. Links come from [[notification-inbox]] and [[focus-mode-chat]].

## What it does
- `parseDocLinks` finds markdown links in an abstract. `classifyDocHref` sorts each href into a `DocLinkKind`: docs, io, external or unknown. It never throws.
- `/app/docs?path=<project>/<rel>` becomes a docs link that fetches `/api/docs/file`. A bare `path=README.md` names no project, so it is unknown. A href with the retired `scope` parameter is also unknown.
- `DocRepository.fetch` picks a `DocContentKind` from the `content-type` header, not the extension. Binary types are never decoded as text. JSON that parses as a listing is a directory.
- `DocRepository.upload` posts a multipart form to `/api/docs/upload`. A 409 raises `DocUploadConflict` with the server's suggested name, and the sheet offers Replace, Rename or Cancel.
- `DocViewerScreen` shows one place at a time and keeps its own back history. Download shares the bytes already held. A binary file shows no preview.
- Upload shows only when `tokenHasAdminRole` says the token is admin. That hides the button; the server's check decides.
- `openMarkdownHref` handles every link tap in rendered markdown. A fetchable link opens in the surrounding `DocSplitHost`, else in a panel. An external URL asks first.
- `AbstractBody` is a compact row that opens the whole abstract as markdown.

## Don't
- Don't pass `?scope=` and don't rewrite old links. The server answers 400.
- Don't decide a file's kind from its extension. A directory has none.

## Invariants
- The upload form field `dir` is `<scope>` or `<scope>/<path>` with no trailing slash. Agent reports and decks are in [[artifact-viewers]].
