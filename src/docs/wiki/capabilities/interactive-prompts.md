---
capability: interactive-prompts
pin_algorithm: py3.13.xebd695/dart-analyzer-parseString/7.7.1
pins:
  - lupin-mobile:lib.shared.widgets.prompt_bodies.YesNoPromptBody@ae2eb73f1f
  - lupin-mobile:lib.shared.widgets.prompt_bodies.MultipleChoicePromptBody@e65b639d14
  - lupin-mobile:lib.shared.widgets.prompt_bodies.MultiQuestionPromptBody@8bfb41bdbc
  - lupin-mobile:lib.shared.widgets.prompt_bodies.OpenEndedPromptBody@772f30d59d
  - lupin-mobile:lib.features.notifications.presentation.interactive_prompt_sheet.InteractivePromptSheet@c721ec8904
  - lupin-mobile:lib.features.notifications.data.ask_resolution.AskResolution@0c773b28d4
  - lupin-mobile:lib.features.notifications.data.ask_resolution.classifyRespondFailure@f1c7b8055f
  - lupin-mobile:lib.features.notifications.data.ask_resolution.classifyResumeStatus@a3fcafd949
---
# Interactive prompts

When a notification asks the user a question, four shared widgets draw the answer controls and one sheet picks among them. The widgets know no endpoints; the host decides where the value goes. The server half is lupin's `notification-delivery` page.

## What it does
- `InteractivePromptSheet.show` opens a modal sheet that shares the caller's `NotificationBloc`. It picks a body from `responseType`, sends `NotificationsRespond` and closes.
- `yes_no` gets `YesNoPromptBody`, answering `yes`, `no` or `neither`, with ` [comment: ...]` appended when typed. Neither means the question needs re-framing.
- `multiple_choice` gets `MultipleChoicePromptBody`. It gets `MultiQuestionPromptBody` when the options carry a nested `questions` list, wrapped as `{"answers": {header: value}}`.
- `open_ended_batch` uses `MultiQuestionPromptBody` but submits the map unwrapped. `open_ended` and any unknown type get `OpenEndedPromptBody`.
- `AskResolution` has `expired`, `answeredElsewhere` and `failed`. The first two close the card instead of raising an error.
- `classifyRespondFailure` reads a 400 message by case-insensitive substring. `classifyResumeStatus` reads the resume route's `status`. Quick ask and the focus chat bloc use both.

## Don't
- Don't put an endpoint inside a body. The host passes an `onRespond` callback.
- Don't let a quick ask body dictate. It passes `dictate: false` because its bloc owns the recorder; see [[asr-dictation]] and [[quick-ask]].
- Don't treat `expired` or `answeredElsewhere` as errors.

## Invariants
- While a dictation chunk records or transcribes, `OpenEndedPromptBody` hides Submit.
