( Dependencies: bootstrap.f, stdstring.f, stdassert.f, stdctx.f, stdexcept.f )

( <stdio.f> :; This file implements IO functions so users don't need to manually invoke syscalls. )

( Helpers for invoking syscalls with set argument counts. )
: SYSCALL0 >C 0 DUP DUP DUP DUP DUP C> SYSCALL ;
: SYSCALL1 >C >C 0 DUP DUP DUP DUP C> C> SYSCALL ;
: SYSCALL2 >C >C >C 0 DUP DUP DUP C> C> C> SYSCALL ;
: SYSCALL3 >C >C >C >C 0 DUP DUP C> C> C> C> SYSCALL ;
: SYSCALL4 >C >C >C >C >C 0 DUP C> C> C> C> C> SYSCALL ;
: SYSCALL5 >C >C >C >C >C >C 0 C> C> C> C> C> C> SYSCALL ;

( Helpers for invoking syscalls with set argument counts and throwing on errors. )
: #SYSCALL SYSCALL DUP -? IF THROW THEN ;
: #SYSCALL0 >C 0 DUP DUP DUP DUP DUP C> #SYSCALL ;
: #SYSCALL1 >C >C 0 DUP DUP DUP DUP C> C> #SYSCALL ;
: #SYSCALL2 >C >C >C 0 DUP DUP DUP C> C> C> #SYSCALL ;
: #SYSCALL3 >C >C >C >C 0 DUP DUP C> C> C> C> #SYSCALL ;
: #SYSCALL4 >C >C >C >C >C 0 DUP C> C> C> C> C> #SYSCALL ;
: #SYSCALL5 >C >C >C >C >C >C 0 C> C> C> C> C> C> #SYSCALL ;

( Note; all following functions throw on errors rather than returning error values,
if you want to invoke a non-throwing syscall manually use one of the SYSCALLn wrappers,
and if you want to extend the library with new IO functions use one of the #SYSCALLn wrappers. )

: READ 0 #SYSCALL3 ;
: WRITE 1 #SYSCALL3 ;
: OPENAT 257 #SYSCALL4 ;
( Instead of directly invoking sys_open since it's a bit old now
we just call sys_openat while specifying that the path is relative to the CWD. )
: OPEN -100 OPENAT ; 
: CLOSE 3 #SYSCALL1 ;

21 VARIABLE NUMBUF
BYTE_T VARIABLE CHARBUF

( TODO: add WRITE_FULL and READ_FULL and make PRINT and related functions use those instead. )
: PRINT DUP STRLEN SWAP BASE + 1 WRITE POP ;
: PUTCHAR CHARBUF !b 1 CHARBUF BASE + 1 WRITE POP ;
: PUTLN 10 PUTCHAR ;
: PRINTLN PRINT PUTLN ;
: PRINTNUM [ NUMBUF 20 + ] LITERAL I64TS PRINT ;
