( Dependencies: bootstrap.f, stdstring.f )

( <stdassert.f> :; Basic handling for fatal or near-fatal errors. 
Note that to avoid a dependency on stdio, as IO can fail and stdassert is meant for handling failures, 
stdassert defines its own minimal PRINTLN that calls sys_exit on failure. )

: STDASSERTF_PRINT
    ( call sys_write with the string pointer and length )
    DUP STRLEN DUP ROT BASE +
    >C >C 0 DUP DUP C> C> 1 DUP SYSCALL

    ( if sys_write gives an error or performs a partial write, sys_exit with code 1 )
    < IF
        0 DUP DUP DUP DUP 1 60 SYSCALL
    THEN
;

2 VARIABLE STDASSERTF_NEWLINE
10 STDASSERTF_NEWLINE !b
0 STDASSERTF_NEWLINE 1 + !b

: STDASSERTF_PRINTLN
    STDASSERTF_PRINT STDASSERTF_NEWLINE STDASSERTF_PRINT
;

( Print an error message, reset REPL state, and start a nested REPL.
Lets the user choose whether to kill the process or try to repair state
and continue. )
: PANIC r" [PANIC] " ABORT STDASSERTF_PRINTLN INTERPRET ;

( Panic if a boolean is false with the message "ASSERT FAILURE".
Used for enforcing invariants, ideally only use this when debugging so that
the condition isn't always checked at runtime in prod. )
: ASSERT ~ IF r" ASSERT FAILURE" PANIC THEN ;

( Panic with a custom error message, used for when you have a function
fully or partially not implemented, but you still want it to be callable,
essentially this lets you act out the function's role manually,
and then EXIT back to the caller without them noticing anything amiss. )
: TODO"
    COMPILE r"
    [ CLEAR WORD PANIC FIND ] LITERAL ECR32
; IMMEDIATE
