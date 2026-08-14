( Dependencies: bootstrap.f, stdstring.f, stdio.f )

( <stdassert.f> :; Basic handling for fatal or near-fatal errors. )

( Print an error message, reset REPL state, and start a nested REPL.
Lets the user choose whether to kill the process or try to repair state
and continue. )
: PANIC r" [PANIC] " ABORT PRINTLN INTERPRET ;

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
    [ ' PANIC ] LITERAL ECR32
; IMMEDIATE

( Image-relative stack base pointers, we use these instead of directly referencing
the ones in the image header because later on coroutines will be able to change this,
so we don't want to rely on a specific execution context. )
DWORD_T VARIABLE dSP_BASE 8 @d dSP_BASE !d
DWORD_T VARIABLE rSP_BASE 12 @d rSP_BASE !d

( Print a backtrace with image relative addresses, note that this does not search
for a word matching the address, it just prints the address directly.
Also, unless you've done something really weird with rsp then it should
also print its own address each time. )
: BACKTRACE 
    rSP@ BASE SWAP -
    BEGIN DUP 
    rSP_BASE @d > WHILE
            DUP @q BASE SWAP - . 8 +
    REPEAT POP
;