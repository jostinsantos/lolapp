/// Installs the supplied video player backend only for Windows.
///
/// Keeping the platform gate here lets startup preserve native backends on
/// Android, iOS, and web while making the Windows choice testable.
void initializeVideoPlayerBackend({
  required bool isWindows,
  required void Function() initializeWindowsBackend,
}) {
  if (isWindows) {
    initializeWindowsBackend();
  }
}
