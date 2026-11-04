import 'package:flutter/material.dart';

import '../../../core/testing/test_keys.dart';
import '../../../shared/widgets/dictation_text_field.dart';
import '../data/new_ticket.dart';

/// Opens the New Ticket card over the Task List.
///
/// Ensures:
///   - completes with the `created` outcome when a ticket was created and the card closed
///     itself, and with null when the operator dismissed it
///   - every other outcome, petition, refusal or no answer, keeps the card open with the
///     sentence showing, as on the web, so nothing typed is lost
Future<NewTicketOutcome?> showNewTicketSheet(
  BuildContext context, {
  required Future<NewTicketOutcome> Function( Map<String, String> payload ) createTicket,
  required List<String> assignees,
} ) {
  return showModalBottomSheet<NewTicketOutcome>(
    context            : context,
    isScrollControlled : true,
    useSafeArea        : true,
    builder            : ( _ ) => NewTicketSheet(
      createTicket : createTicket,
      assignees    : assignees,
    ),
  );
}

/// The New Ticket card.
///
/// Its fields are the web's `NEW_TICKET_FIELDS`, in the web's order: title, details,
/// assigned to, accountable manager, priority, approval, type, epic key, project. A test
/// pins the list, because a field on one client and not the other is the defect the web's
/// shared module exists to prevent.
class NewTicketSheet extends StatefulWidget {
  /// Files the ticket and returns the worded outcome.
  final Future<NewTicketOutcome> Function( Map<String, String> payload ) createTicket;

  /// The names offered as suggestions under the two people fields.
  final List<String> assignees;

  /// Creates the card.
  const NewTicketSheet( {
    super.key,
    required this.createTicket,
    required this.assignees,
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

  @override
  void dispose() {
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
    // A petition keeps the card open, and so does "no answer". Both may mean the row
    // already exists, and the sentence says so; closing would hide the one warning that
    // stops an honest retry from filing it twice.
    setState( () { _inFlight = false; _result = outcome.text; } );
  }

  // A free-text box with the roster as suggestions, like the web's `<input list=...>`.
  // The operator can type a name the roster does not know yet; the suggestions are a
  // courtesy, not a constraint.
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
      // Expanded, or "Not approved — holding area" overflows by 156 px at 360 dp.
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
    // The keyboard's height is padding, and the form scrolls. A voice-strip keyboard is
    // 420 dp and more, so a control can go dead behind it if the fix assumes a smaller one.
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
                  DictationTextField(
                    fieldKey    : const Key( TestKeys.newTicketTitle ),
                    micKey      : const Key( TestKeys.newTicketTitleMic ),
                    controller  : _title,
                    focusNode   : _titleFocus,
                    autofocus   : true,
                    decoration  : const InputDecoration(
                      labelText  : 'Title',
                      hintText   : 'What needs doing',
                      border     : OutlineInputBorder(),
                    ),
                  ),
                  gap,
                  DictationTextField(
                    fieldKey   : const Key( TestKeys.newTicketDetails ),
                    micKey     : const Key( TestKeys.newTicketDetailsMic ),
                    controller : _details,
                    minLines   : 4,
                    maxLines   : 8,
                    decoration : const InputDecoration(
                      labelText  : 'Details',
                      hintText   : 'Background material — context, links, what you already know. '
                                   'Whoever picks this up starts here.',
                      border     : OutlineInputBorder(),
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
