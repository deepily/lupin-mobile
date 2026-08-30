/// The "expected to act on" predicate — AC-S3.6, AC-S3.6b.
///
/// Pure, so both of its enforcement points (verbatim speech in the
/// orchestrator; the stop-list drop exemption in `FocusChatBloc`) are
/// testable without a bloc, and neither can drift from the other.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lupin_mobile/services/tts/speech_intent.dart';

void main() {
  group( 'isActionableQuestion', () {
    test( 'AC-S3.6 — arm 1: response_requested is a question (Door B / Door C)', () {
      expect( isActionableQuestion(
        responseRequested : true,
        senderId          : 'anything@lupin.deepily.ai',
      ), isTrue );
    } );

    test( 'AC-S3.6b — arm 2: the Door A shape is ask.flow sender AND no job_id', () {
      expect( isActionableQuestion(
        responseRequested : false,
        senderId          : askFlowSenderId,
        jobId             : null,
      ), isTrue, reason: '_speak dispatches an AsyncNotificationRequest, which '
                         'carries no response_requested — arm 1 cannot see it' );
    } );

    test( 'AC-S3.6b — the job_id half is what keeps arm 2 tight: an ANSWER '
          'from the same sender is NOT a question', () {
      expect( isActionableQuestion(
        responseRequested : false,
        senderId          : askFlowSenderId,
        jobId             : 'job-42',
      ), isFalse, reason: 'every flow QUESTION passes job_id=None; the ANSWER '
                          'path passes a real one' );
      // Empty string is the same case as absent — a wire that sends "" must
      // not read as "a real job".
      expect( isActionableQuestion(
        responseRequested : false,
        senderId          : askFlowSenderId,
        jobId             : '',
      ), isTrue );
    } );

    test( 'ordinary chatter from any other sender is not actionable', () {
      expect( isActionableQuestion(
        responseRequested : false,
        senderId          : 'queue.done@lupin.deepily.ai',
      ), isFalse );
      expect( isActionableQuestion( responseRequested: false ), isFalse );
    } );
  } );

  group( 'shouldSpeakVerbatim', () {
    test( 'both question arms speak verbatim with no ask surface present', () {
      expect( shouldSpeakVerbatim( responseRequested: true ), isTrue );
      expect( shouldSpeakVerbatim(
        responseRequested : false,
        senderId          : askFlowSenderId,
      ), isTrue );
    } );

    test( 'ruling 4 — an answer to a LIVE Quick Ask job speaks verbatim', () {
      expect( shouldSpeakVerbatim(
        responseRequested : false,
        senderId          : 'queue.done@lupin.deepily.ai',
        jobId             : 'job-42',
        isLiveAskAnswer   : ( id ) => id == 'job-42',
      ), isTrue );
    } );

    test( 'an answer to somebody ELSE\'s job does not', () {
      expect( shouldSpeakVerbatim(
        responseRequested : false,
        senderId          : 'queue.done@lupin.deepily.ai',
        jobId             : 'job-99',
        isLiveAskAnswer   : ( id ) => id == 'job-42',
      ), isFalse, reason: 'ruling 4 covers the answer the user asked FOR, '
                          'not every completion on the wire' );
    } );

    test( 'no ask surface registered ⇒ the answer arm is simply inert', () {
      expect( shouldSpeakVerbatim(
        responseRequested : false,
        senderId          : 'queue.done@lupin.deepily.ai',
        jobId             : 'job-42',
      ), isFalse );
    } );
  } );
}
