# fssh Terminal Cleanup Fix Design

Date: 2026-07-17

## Problem

When a remote `tmux` client exits abnormally after the laptop loses its
network connection, Ghostty can remain in the terminal's alternate screen.
In that state, scrolling at the local shell is translated into Up and Down
key input instead of moving through scrollback.

`terminal/ssh/fssh.sh` already installs an exit trap that disables mouse,
bracketed-paste, and extended-keyboard modes. However, commit `a1f4c82`
removed the trap's `tput rmcup` call while changing unrelated host-listing
code, so the trap no longer exits the alternate screen.

## Chosen Approach

Restore `tput rmcup 2>/dev/null || true` in `reset_terminal()` after `stty
sane`. `rmcup` is the terminfo capability for leaving the alternate screen,
so this keeps the cleanup portable across supported terminal types instead of
hard-coding a Ghostty-specific escape sequence.

The command remains best-effort. A missing `tput`, an unknown `TERM`, or an
unsupported `rmcup` capability must not replace the original SSH exit status
or prevent the rest of the exit trap from completing.

## Alternatives Considered

1. Emit `ESC[?1049l` directly. This is simple, but hard-codes one terminal
   protocol instead of using the active terminal's terminfo entry.
2. Run a full terminal reset. This would recover more state, but can clear the
   visible screen and reset unrelated user preferences, making it too
   disruptive for routine `fssh` cleanup.

## Control Flow

1. The remote `tmux` SSH client returns normally or with an error such as 255.
2. `fssh.sh` exits while preserving that status.
3. The existing `EXIT` trap invokes `reset_terminal()`.
4. Existing control sequences disable mouse, paste, and keyboard modes.
5. `stty sane` restores local TTY flags.
6. `tput rmcup` exits the alternate screen on a best-effort basis.
7. Cleanup returns without masking the original connection result.

## Testing

Add a shell regression test that runs the script through a non-connecting
exit path with a deterministic `TERM`, captures its terminal cleanup bytes,
and asserts that the terminfo `rmcup` sequence is present. The test must fail
against the current implementation and pass after restoring the cleanup call.

Then run syntax validation and the repository's relevant shell tests to ensure
the change does not affect argument handling or existing terminal cleanup.

## Scope

This fix changes only local terminal cleanup after `fssh` exits. It does not
change SSH multiplexing, reconnect behavior, remote `tmux` configuration, or
Ghostty configuration.
