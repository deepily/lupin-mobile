---
capability: claude-code-sessions
pin_algorithm: py3.13.xebd695/dart-analyzer-parseString/7.7.1
pins:
  - lupin-mobile:lib.features.claude_code.data.claude_code_models.ClaudeCodeSubmitRequest@577e814888
  - lupin-mobile:lib.features.claude_code.data.claude_code_models.ClaudeCodeSubmitResponse@45f66ab6cf
  - lupin-mobile:lib.features.claude_code.data.claude_code_models.ClaudeCodeApiException@f2d5bebfdc
  - lupin-mobile:lib.features.claude_code.data.claude_code_repository.ClaudeCodeRepository@7829542f4f
  - lupin-mobile:lib.features.claude_code.domain.claude_code_bloc.ClaudeCodeBloc@fd688a4988
  - lupin-mobile:lib.features.claude_code.domain.claude_code_event.ClaudeCodeEvent@0aad601ab3
  - lupin-mobile:lib.features.claude_code.domain.claude_code_event.ClaudeCodeSubmit@88617e6571
  - lupin-mobile:lib.features.claude_code.domain.claude_code_state.ClaudeCodeState@dc50612211
  - lupin-mobile:lib.features.claude_code.domain.claude_code_state.ClaudeCodeInitial@e813596fa9
  - lupin-mobile:lib.features.claude_code.domain.claude_code_state.ClaudeCodeSubmitting@706bd1bfca
  - lupin-mobile:lib.features.claude_code.domain.claude_code_state.ClaudeCodeSubmitted@9d29c79b04
  - lupin-mobile:lib.features.claude_code.domain.claude_code_state.ClaudeCodeError@b0036d4d4b
  - lupin-mobile:lib.features.claude_code.presentation.dispatch_sheet.DispatchSheet@1e19b55328
  - lupin-mobile:lib.features.claude_code.presentation.session_list_screen.SessionListScreen@844b24bc18
---
# Claude Code sessions

Submits one bounded Claude Code job from the phone. The interactive session list is retired: the screen only points at the Queue Dashboard. The server job is lupin's `bounded-claude-code-jobs`; the queue side is [[job-queue-client]].

## What it does
- `ClaudeCodeRepository.submit` posts to `/api/v2/submit` through the shared Dio. The old `/api/claude-code/submit` route answers 410.
- `ClaudeCodeSubmitRequest.toSubmitRequest` sends the command `agent router go to claude code`. Defaults: project `lupin`, task type `BOUNDED`, 50 turns. `question` is the prompt cut to 4000 characters.
- `ClaudeCodeSubmitResponse.fromAsk` succeeds only with a job id and status `waiting` or `done`. `needs_input` lists the missing arguments. Anything else raises `ClaudeCodeApiException`.
- `ClaudeCodeBloc` handles one event, `ClaudeCodeSubmit`, through four states: initial, submitting, submitted, error.
- `DispatchSheet` takes a prompt and an optional project; an empty prompt does nothing. `SessionListScreen` shows a retired banner, a Queue Dashboard button and the sheet.

## Don't
- Don't add inject, interrupt or end-session controls. The server job has none.
- Don't look for the job here. It appears as a `cc-*` job in the Queue Dashboard.
- Don't use this for other agents; see [[agentic-job-forms]].

## Invariants
- A 200 reply with no job id is an error.
- `ClaudeCodeSubmit` compares by prompt only.
- A failure shows the server's `detail`, else the Dio message, else `submit failed`.
