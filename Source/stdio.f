( Dependencies: bootstrap.f, stdstring.f )

( <stdio.f> :; This file implements IO functions so users don't need to manually invoke syscalls. )

( Helpers for invoking syscalls with set argument counts. )
: SYSCALL1 >C >C 0 DUP DUP DUP DUP C> C> SYSCALL ;
: SYSCALL2 >C >C >C 0 DUP DUP DUP C> C> C> SYSCALL ;
: SYSCALL3 >C >C >C >C 0 DUP DUP C> C> C> C> SYSCALL ;
: SYSCALL4 >C >C >C >C >C 0 DUP C> C> C> C> C> SYSCALL ;
: SYSCALL5 >C >C >C >C >C >C 0 C> C> C> C> C> C> SYSCALL ;

: READ 0 SYSCALL3 ;
: WRITE 1 SYSCALL3 ;
: OPENAT 257 SYSCALL4 ;
( Instead of directly invoking sys_open since it's a bit old now
we just call sys_openat while specifying that the path is relative to the CWD. )
: OPEN -100 OPENAT ; 
: CLOSE 3 SYSCALL1 ;

21 VARIABLE NUMBUF

( For now this just contains basic string printing wrappers that assume full writes and ignore errors. )
: PUTLN 1 NEWLINE BASE + 1 WRITE POP ;
: PRINT DUP STRLEN SWAP BASE + 1 WRITE POP ;
: PRINTLN PRINT PUTLN ;
: PRINTNUM [ NUMBUF 20 + ] LITERAL I64TS PRINT ;