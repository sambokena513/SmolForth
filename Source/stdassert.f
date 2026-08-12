( Dependencies: bootstrap.f, stdstring.f, stdio.f )

( <stderror.f> :; Basic handling for fatal or near-fatal errors. )

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