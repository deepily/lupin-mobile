/// Describes [error] by type, plus offset for a [FormatException], without quoting its message.
///
/// A [FormatException] quotes the text it failed to parse, so logging its message would copy stored user
/// content into the log file. The type and offset are enough to find the fault.
///
/// Ensures:
///   - the result never contains text taken from the failing input
String describeFailure( Object error ) {
  if ( error is FormatException ) {
    final offset = error.offset;
    return offset == null ? "FormatException" : "FormatException at offset $offset";
  }
  return error.runtimeType.toString();
}
