---
capability: agentic-job-forms
pin_algorithm: py3.13.xebd695/dart-analyzer-parseString/7.7.1
pins:
  - lupin-mobile:lib.features.agentic.presentation.agentic_hub_screen.AgenticHubScreen@ada74757b6
  - lupin-mobile:lib.features.agentic.data.agentic_common_models.AgenticJobType@0d3eb4e6a1
  - lupin-mobile:lib.features.agentic.domain.agentic_submission_bloc.AgenticSubmissionBloc@27fdc54171
  - lupin-mobile:lib.features.agentic.data.agentic_repository.AgenticRepository@0ba0877a13
  - lupin-mobile:lib.features.agentic.data.agentic_common_models.AgenticSubmitResponse@ac01e33154
  - lupin-mobile:lib.features.agentic.data.agentic_common_models.AgenticApiException@526a8f9255
  - lupin-mobile:lib.features.agentic.presentation.test_fix_expediter_form.TestFixExpediterForm@ec4a880f1d
  - lupin-mobile:lib.features.agentic.data.deep_research_models.DeepResearchReport@7ef3ea7d3e
  - lupin-mobile:lib.features.agentic.data.bug_fix_expediter_models.BugFixExpediterRequest@2ae8190e8d
  - lupin-mobile:lib.features.agentic.data.chained_models.ResearchToPodcastRequest@a264a3d81b
  - lupin-mobile:lib.features.agentic.data.chained_models.ResearchToPresentationRequest@9479cff0b4
  - lupin-mobile:lib.features.agentic.data.deep_research_models.DeepResearchRequest@8fcbeef01b
---
# Agentic job forms

The nine forms that submit long-running agentic jobs from the phone, the request model behind each, and one bloc that runs them all. The server contract is lupin's `agentic-job-contract` page. Detail pages: [[agentic-requests-and-forms]].

## What it does
- `AgenticHubScreen` lists nine cards and opens a form from each, passing the shared `AgenticSubmissionBloc` down. `AgenticJobType` names the same nine kinds.
- A form sends `AgenticSubmitRequested` with a type and a request object. The bloc emits `AgenticSubmissionInProgress`, then `AgenticSubmissionSuccess` or `AgenticSubmissionFailure`.
- `TestFixExpediterForm` resumes a job rather than creating one, so the bloc emits `TfeResumeSuccess` carrying a `TfeResumeResponse`.
- `AgenticRepository` posts eight submit methods to `/api/v2/submit` through one helper. Each request model has a spoken `submitCommand` and a `toSubmitArgs` map.
- Queue directives (`scheduledAt`, `monopolize`) go top-level in the `SubmitRequest`, never inside `args`.
- `AgenticSubmitResponse.fromAsk` counts only status `waiting` or `done` with a job id as success. `needs_input` throws `AgenticApiException` naming the missing arguments. The queue position is always 0.
- On success a form opens `JobDetailScreen` for the new id; see [[job-queue-client]]. `DeepResearchReport` holds a finished report's markdown for the viewer in [[artifact-viewers]].

## Don't
- Don't add a tenth form without a branch in `AgenticSubmissionBloc` and a case in `AgenticJobType`. The switch has no default.
- Don't read `queuePosition` as a real position. It is 0 for every v2 submit.
- Don't post to the old per-agent submit paths. They are retired.

## Invariants
- A form blocks an empty main field itself with a silent return. The bloc does not validate.
- The per-model `toJson` methods, other than `TfeResumeFromRequest.toJson`, have no caller under `lib/`.
- A single typed command goes through `SubmitJobSheet` or [[quick-ask]] instead.
