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

1 CONSTANT STDOUT
0 CONSTANT STDIN

: READ 0 #SYSCALL3 ;
: WRITE 1 #SYSCALL3 ;
: OPENAT 257 #SYSCALL4 ;
( Instead of directly invoking sys_open since it's a bit old now
we just call sys_openat while specifying that the path is relative to the CWD. )
: OPEN -100 OPENAT ; 
: CLOSE 3 #SYSCALL1 ;

DWORD_T VARIABLE FDBUF ( for use in WRITE_FULL and READ_FULL, DWORD_T since on Linux file descriptors are 32 bits. )

( WRITE_FULL and READ_FULL respectively are wrappers around WRITE and READ that guarantee that all bytes requested where read/written on success.
They return nothing on success, and throw on failure. Note that a failure does not mean no IO was performed, it could also mean a partial read or write happened. )
: WRITE_FULL
    FDBUF !d BEGIN
    OVER WHILE
        2DUP FDBUF @d WRITE TUCK ( copy the val so our stack looks like [ count, written, buf, written ] )
        + -ROT SWAP - SWAP ( add the return value to the buffer and subtract it from the count to write )
    REPEAT
    2POP
;

: READ_FULL
    FDBUF !d BEGIN
    OVER WHILE
        2DUP FDBUF @d READ
        DUP IF ( if not EOF )
            TUCK + -ROT SWAP - SWAP
        ELSE
            ( throw EINVAL on a read that got EOF, as our function's contract makes a
            valid length argument be only one that never causes us to go past EOF )
            -22 THROW 
        THEN
    REPEAT
    2POP
;

21 VARIABLE NUMBUF
BYTE_T VARIABLE CHARBUF

: PRINT DUP STRLEN SWAP BASE + STDOUT WRITE_FULL ;
: PUTCHAR CHARBUF !b 1 CHARBUF BASE + STDOUT WRITE_FULL ;
: PUTLN 10 PUTCHAR ;
: PRINTLN PRINT PUTLN ;
: PRINTNUM [ NUMBUF 20 + ] LITERAL I64TS PRINT ;

( . is a primitive and we want existing calls to still work so we patch its code body here instead of making a new entry for it )
HERE CLEAR WORD . FIND 4 + @d aHERE !d ] PRINTNUM PUTLN [ -61 ,b aHERE !d
