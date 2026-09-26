import 'package:flutter/material.dart';

import '../../../core/testing/test_keys.dart';
import '../../../services/asr/voice_capture_session.dart';
import '../data/new_ticket.dart';

/// Open the New Ticket card over the Task List (row b31a9ed9, walk-through item M4).
///
/// Ensures:
///   - completes with the `created` outcome when a ticket was created and the card
///     closed itself; with null when the operator dismissed it
///   - every other outcome — petition, refusal, no answer — keeps the card OPEN with the
///     sentence showing, as on the web, so nothing typed is lost
Future<NewTicketOutcome?> showNewTicketSheet(
  BuildContext context, {
  required Future<NewTicketOutcome> Function( Map<String, String> payload ) createTicket,
  required List<String> assignees,
  VoiceCaptureSession? voice,
} ) {
  return showModalBottomSheet<NewTicketOutcome>(
    context            : context,
    isScrollControlled : true,
    useSafeArea        : true,
    builder            : ( _ ) => NewTicketSheet(
      createTicket : createTicket,
      assignees    : assignees,
      voice        : voice,
    ),
  );
}

enum _Mic { idle, listening, transcribing }

/// The card. Its fields are the web's `NEW_TICKET_FIELDS`, in the web's order:
/// title, details, assigned to, accountable manager, priority, approval, type, epic key,
/// project. A field on one client and not the other is the defect the web's shared
/// module exists to prevent, so this list is pinned by a test.
class NewTicketSheet extends StatefulWidget {
  final Future<NewTicketOutcome> Function( Map<String, String> payload ) createTicket;
  final List<String> assignees;
  final VoiceCaptureSession? voice;

  const NewTicketSheet( {
    super.key,
    required this.createTicket,
    required this.assignees,
    this.voice,
  } );

  @override
  State<NewTicketSheet> createState() => _NewTicketSheetState();
}

class _NewTicketSheetState extends State<NewTicketSheet> {
  final _title   = TextEditingController();
  final _details = TextEditingController();
  final _owner   = TextEditingController();
  final _manager = TextEditingController();
  final _epic    = TextEditingController( text: newTicketDefaultCorrelationKey );
  final _project = TextEditingController( text: newTicketDefaultProject );
  final _ownerFocus   = FocusNode();
  final _managerFocus = FocusNode();
  final _titleFocus   = FocusNode();

  String _priority  = newTicketDefaultPriority;
  bool   _approved  = newTicketDefaultApproved;
  String _itemClass = newTicketDefaultType;

  String? _result;
  bool _inFlight = false;

  /// Which field's mic is live, if any. One at a time: two recordings cannot share the
  /// one recorder.
  String? _micField;
  _Mic _mic = _Mic.idle;

  /// Where the caret was when recording began, so the words land where the operator was
  /// typing rather than at the end (the web splices at the same point).
  int _micCaret = -1;

  @override
  void dispose() {
    if ( _mic == _Mic.listening ) widget.voice?.cancel();
    for ( final c in [ _title, _details, _owner, _manager, _epic, _project ] ) {
      c.dispose();
    }
    _ownerFocus.dispose();
    _managerFocus.dispose();
    _titleFocus.dispose();
    super.dispose();
  }

  NewTicketFields _read() => NewTicketFields(
    title              : _title.text,
    details            : _details.text,
    ownerPersona       : _owner.text,
    accountableManager : _manager.text,
    priority           : _priority,
    approved           : _approved,
    itemClass          : _itemClass,
    correlationKey     : _epic.text,
    project            : _project.text,
  );

  Future<void> _submit() async {
    if ( _inFlight ) return;
    final built = buildNewTicketPayload( _read() );
    if ( !built.ok ) {
      setState( () => _result = built.error );
      _titleFocus.requestFocus();
      return;
    }
    setState( () { _inFlight = true; _result = 'Creating…'; } );

    NewTicketOutcome outcome;
    try {
      outcome = await widget.createTicket( built.payload! );
    } catch ( _ ) {
      outcome = describeNewTicketResult( 0, null );
    }
    if ( !mounted ) return;

    if ( outcome.state == NewTicketState.created ) {
      Navigator.of( context ).pop( outcome );
      return;
    }
    // 🔴 A PETITION KEEPS THE CARD OPEN, AND SO DOES "NO ANSWER". Both may mean the row
    // already exists, and the sentence says so; closing would hide the one warning that
    // stops an honest retry from filing it twice.
    setState( () { _inFlight = false; _result = outcome.text; } );
  }

  Future<void> _toggleMic( String field, TextEditingController box ) async {
    final voice = widget.voice;
    if ( voice == null || _mic == _Mic.transcribing ) return;
    if ( _mic == _Mic.listening && _micField != field ) return;

    if ( _mic == _Mic.listening ) {
      setState( () => _mic = _Mic.transcribing );
      final capture = await voice.stopAndTranscribe();
      if ( !mounted || capture.isStale ) return;
      if ( capture.transcript != null ) _splice( box, capture.transcript!.trim() );
      setState( () {
        _mic      = _Mic.idle;
        _micField = null;
        if ( capture.transcript == null ) _result = capture.errorMessage;
      } );
      return;
    }

    final sel = box.selection;
    _micCaret = sel.isValid ? sel.baseOffset : box.text.length;
    setState( () { _micField = field; _mic = _Mic.listening; } );
    final start = await voice.start();
    if ( !mounted || start.isStale ) return;
    if ( !start.started ) {
      setState( () { _mic = _Mic.idle; _micField = null; _result = start.errorMessage; } );
    }
  }

  /// Insert [heard] at the caret the box held when recording began. APPEND, NEVER
  /// REPLACE: the operator may have typed half a sentence before reaching for the mic.
  void _splice( TextEditingController box, String heard ) {
    if ( heard.isEmpty ) return;
    final text  = box.text;
    final at    = ( _micCaret < 0 || _micCaret > text.length ) ? text.length : _micCaret;
    final left  = text.substring( 0, at );
    final right = text.substring( at );
    final pad   = left.isEmpty || left.endsWith( ' ' ) || left.endsWith( '\n' ) ? '' : ' ';
    final next  = '$left$pad$heard$right';
    box.value = TextEditingValue(
      text      : next,
      selection : TextSelection.collapsed( offset: ( left + pad + heard ).length ),
    );
  }

  Widget? _micButton( String field, String label, TextEditingController box, String key ) {
    if ( widget.voice == null ) return null;
    final live = _micField == field;
    return IconButton(
      key       : Key( key ),
      tooltip   : live && _mic == _Mic.listening ? 'Stop and transcribe' : 'Dictate $label',
      onPressed : ( _mic == _Mic.idle || live ) && _mic != _Mic.transcribing
          ? () => _toggleMic( field, box )
          : null,
      icon      : live && _mic == _Mic.transcribing
          ? const SizedBox( width: 18, height: 18, child: CircularProgressIndicator( strokeWidth: 2 ) )
          : Icon( live && _mic == _Mic.listening ? Icons.stop_circle_outlined : Icons.mic_none ),
    );
  }

  /// A free-text box with the roster as suggestions — the web's `<input list=…>`. The
  /// operator can type a name the roster does not know yet; the suggestions are a
  /// courtesy, not a constraint.
  Widget _person( String label, String hint, TextEditingController c, FocusNode f, String key ) {
    return RawAutocomplete<String>(
      textEditingController : c,
      focusNode             : f,
      optionsBuilder        : ( value ) {
        final q = value.text.trim().toLowerCase();
        return widget.assignees.where( ( n ) => q.isEmpty || n.toLowerCase().contains( q ) );
      },
      fieldViewBuilder : ( context, controller, focus, onSubmit ) => TextField(
        key         : Key( key ),
        controller  : controller,
        focusNode   : focus,
        autocorrect : false,
        decoration  : InputDecoration( labelText: label, hintText: hint, border: const OutlineInputBorder() ),
      ),
      optionsViewBuilder : ( context, onSelected, options ) => Align(
        alignment : Alignment.topLeft,
        child     : Material(
          elevation : 4,
          child     : ConstrainedBox(
            constraints : const BoxConstraints( maxHeight: 200, maxWidth: 320 ),
            child       : ListView(
              padding    : EdgeInsets.zero,
              shrinkWrap : true,
              children   : [
                for ( final name in options )
                  ListTile( dense: true, title: Text( name ), onTap: () => onSelected( name ) ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _select<T>( String label, T value, List<T> values, String key,
      ValueChanged<T> onChanged, { String Function( T )? labelOf } ) {
    return DropdownButtonFormField<T>(
      key          : Key( key ),
      value        : value,
      decoration   : InputDecoration( labelText: label, border: const OutlineInputBorder() ),
      // ⚠️ EXPANDED, OR "Not approved — holding area" OVERFLOWS AT 360 dp. Measured: 156
      // px over on the first widget run. A phone's portrait width is the width.
      isExpanded   : true,
      items        : [
        for ( final v in values )
          DropdownMenuItem<T>(
            value : v,
            child : Text( labelOf?.call( v ) ?? '$v', overflow: TextOverflow.ellipsis ),
          ),
      ],
      onChanged : ( v ) { if ( v != null ) setState( () => onChanged( v ) ); },
    );
  }

  @override
  Widget build( BuildContext context ) {
    const gap = SizedBox( height: 12 );
    // 🔴 THE KEYBOARD'S HEIGHT IS PADDING, AND THE FORM SCROLLS. A voice-strip keyboard
    // is 420 dp and more; the Focus DM editor's Send and X went dead behind one (P0,
    // 09-23), because the fix was tested against a 320 dp keyboard.
    final keyboard = MediaQuery.of( context ).viewInsets.bottom;

    return Padding(
      key     : const Key( TestKeys.newTicketSheet ),
      padding : EdgeInsets.only( bottom: keyboard ),
      child   : Column(
        mainAxisSize : MainAxisSize.min,
        children     : [
          Flexible(
            child : SingleChildScrollView(
              padding : const EdgeInsets.fromLTRB( 16, 16, 16, 8 ),
              child   : Column(
                crossAxisAlignment : CrossAxisAlignment.stretch,
                children : [
                  Semantics(
                    header : true,
                    child  : Text( 'New ticket', style: Theme.of( context ).textTheme.titleLarge ),
                  ),
                  gap,
                  TextField(
                    key         : const Key( TestKeys.newTicketTitle ),
                    controller  : _title,
                    focusNode   : _titleFocus,
                    autofocus   : true,
                    decoration  : InputDecoration(
                      labelText  : 'Title',
                      hintText   : 'What needs doing',
                      border     : const OutlineInputBorder(),
                      suffixIcon : _micButton( 'title', 'Title', _title, TestKeys.newTicketTitleMic ),
                    ),
                  ),
                  gap,
                  TextField(
                    key        : const Key( TestKeys.newTicketDetails ),
                    controller : _details,
                    minLines   : 4,
                    maxLines   : 8,
                    decoration : InputDecoration(
                      labelText  : 'Details',
                      hintText   : 'Background material — context, links, what you already know. '
                                   'Whoever picks this up starts here.',
                      border     : const OutlineInputBorder(),
                      suffixIcon : _micButton( 'details', 'Details', _details, TestKeys.newTicketDetailsMic ),
                    ),
                  ),
                  gap,
                  _person( 'Assigned to', 'Unassigned', _owner, _ownerFocus, TestKeys.newTicketOwner ),
                  gap,
                  _person( 'Accountable manager', 'Optional', _manager, _managerFocus, TestKeys.newTicketManager ),
                  gap,
                  _select<String>( 'Priority', _priority, newTicketPriorities, TestKeys.newTicketPriority,
                      ( v ) => _priority = v ),
                  gap,
                  _select<bool>( 'Approval', _approved, const [ true, false ], TestKeys.newTicketApproved,
                      ( v ) => _approved = v,
                      labelOf : ( v ) => v ? 'Approved — live board' : 'Not approved — holding area' ),
                  gap,
                  _select<String>( 'Type', _itemClass, newTicketTypes, TestKeys.newTicketType,
                      ( v ) => _itemClass = v ),
                  gap,
                  TextField(
                    key         : const Key( TestKeys.newTicketEpic ),
                    controller  : _epic,
                    autocorrect : false,
                    decoration  : const InputDecoration(
                      labelText : 'Epic key', hintText: 'epic:…', border: OutlineInputBorder() ),
                  ),
                  gap,
                  TextField(
                    key         : const Key( TestKeys.newTicketProject ),
                    controller  : _project,
                    autocorrect : false,
                    decoration  : const InputDecoration(
                      labelText : 'Project', hintText: newTicketDefaultProject, border: OutlineInputBorder() ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding : const EdgeInsets.fromLTRB( 16, 0, 16, 16 ),
            child   : Row(
              children : [
                Expanded(
                  child : Semantics(
                    liveRegion : true,
                    child      : Text( _result ?? '', key: const Key( TestKeys.newTicketResult ) ),
                  ),
                ),
                TextButton(
                  key       : const Key( TestKeys.newTicketCancel ),
                  onPressed : () => Navigator.of( context ).pop(),
                  child     : const Text( 'Cancel' ),
                ),
                const SizedBox( width: 8 ),
                FilledButton(
                  key       : const Key( TestKeys.newTicketCreate ),
                  onPressed : _inFlight ? null : _submit,
                  child     : const Text( 'Create' ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
