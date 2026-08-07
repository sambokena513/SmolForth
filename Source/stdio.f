( Dependencies: bootstrap.f, stdstring.f )

( <stdio.f> :; This file implements IO functions so users don't need to manually invoke syscalls. )

( For now this just contains basic string printing wrappers that assume full writes and ignore errors. )
: PUTLN 0 DUP DUP 1 NEWLINE BASE + 1 DUP SYSCALL POP ;
: PRINTLN DUP STRLEN SWAP >C >C 0 DUP DUP C> C> BASE + 1 DUP SYSCALL POP PUTLN ;