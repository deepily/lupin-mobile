---
capability: agentic-requests-and-forms
pin_algorithm: py3.13.xebd695/dart-analyzer-parseString/7.7.1
pins:
  - lupin-mobile:lib.features.agentic.data.agentic_common_models.TfeResumeResponse@cedafa7501
  - lupin-mobile:lib.features.agentic.data.podcast_models.PodcastGeneratorRequest@8a546dd526
  - lupin-mobile:lib.features.agentic.data.presentation_models.PresentationGeneratorRequest@5a6b9c2680
  - lupin-mobile:lib.features.agentic.data.swe_team_models.SweTeamRequest@055477ba66
  - lupin-mobile:lib.features.agentic.data.test_fix_expediter_models.TfeResumeFromRequest@044f0862d8
  - lupin-mobile:lib.features.agentic.data.test_suite_models.TestSuiteRequest@04fcfe8c82
  - lupin-mobile:lib.features.agentic.domain.agentic_submission_event.AgenticSubmissionEvent@915af66946
  - lupin-mobile:lib.features.agentic.domain.agentic_submission_event.AgenticSubmitRequested@91cf630c2f
  - lupin-mobile:lib.features.agentic.domain.agentic_submission_event.AgenticFormReset@ef52a246bf
  - lupin-mobile:lib.features.agentic.domain.agentic_submission_state.AgenticSubmissionState@ade7b77daf
  - lupin-mobile:lib.features.agentic.domain.agentic_submission_state.AgenticSubmissionInitial@b4ad59d31c
  - lupin-mobile:lib.features.agentic.domain.agentic_submission_state.AgenticSubmissionInProgress@47f167693c
  - lupin-mobile:lib.features.agentic.domain.agentic_submission_state.AgenticSubmissionSuccess@a78e1ada26
  - lupin-mobile:lib.features.agentic.domain.agentic_submission_state.TfeResumeSuccess@920eabbfdd
  - lupin-mobile:lib.features.agentic.domain.agentic_submission_state.AgenticSubmissionFailure@a5e6003e2e
  - lupin-mobile:lib.features.agentic.presentation.bug_fix_expediter_form.BugFixExpediterForm@378d822e9b
  - lupin-mobile:lib.features.agentic.presentation.deep_research_form.DeepResearchForm@1c3a42f9f2
  - lupin-mobile:lib.features.agentic.presentation.podcast_generator_form.PodcastGeneratorForm@2455de4a7c
  - lupin-mobile:lib.features.agentic.presentation.presentation_generator_form.PresentationGeneratorForm@ab51fa4ff4
  - lupin-mobile:lib.features.agentic.presentation.research_to_podcast_form.ResearchToPodcastForm@19c9dcb565
  - lupin-mobile:lib.features.agentic.presentation.research_to_presentation_form.ResearchToPresentationForm@ff1fd0c862
  - lupin-mobile:lib.features.agentic.presentation.swe_team_form.SweTeamForm@49dc0890a8
  - lupin-mobile:lib.features.agentic.presentation.test_suite_form.TestSuiteForm@25e81a0f62
---
# Agentic requests and forms

The remaining request models, the eight forms that build them and the bloc's events and states. The bloc, hub and repository are on [[agentic-job-forms]].

## What it does
- `PodcastGeneratorRequest`, `PresentationGeneratorRequest`, `SweTeamRequest` and `TestSuiteRequest` each have a spoken `submitCommand` and a `toSubmitArgs` map. Podcast sends `research` and `languages`; presentation sends `source`. `TestSuiteRequest` defaults to `integration,e2e` tests.
- `TfeResumeFromRequest` holds one `resumeFrom` string. `TfeResumeResponse` names the new and original job ids, and its status defaults to `resumed`.
- `BugFixExpediterForm`, `DeepResearchForm`, `PodcastGeneratorForm`, `PresentationGeneratorForm`, `ResearchToPodcastForm`, `ResearchToPresentationForm`, `SweTeamForm` and `TestSuiteForm` each return silently when their main field is empty. The test suite form checks its selected types instead. A budget or duration that does not parse becomes null.
- `AgenticSubmitRequested` carries a type and an untyped request. `AgenticFormReset` returns the bloc to `AgenticSubmissionInitial`.
- `AgenticSubmissionSuccess` holds type, job id and a queue position of 0 when none is reported. `TfeResumeSuccess` holds a `TfeResumeResponse`. `AgenticSubmissionFailure` holds one message.
- The `AgenticSubmitRequested` request is untyped, so pairing a type with the wrong request class is not caught at compile time.
