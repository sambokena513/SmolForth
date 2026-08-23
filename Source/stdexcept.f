( Dependencies: bootstrap.f, stdstring.f, stdassert.f, stdctx.f )

( <stdexcept.f> :; Exceptions and exception handling. Uses the exception stack from <stdctx.f>. )


( A handler in the code below refers to a value on the exception stack consisting of an execution context, and an address to resume execution at. )

( r | -E- handler | handler-addr -D- )
: PUSH_HANDLER
    TODO" PUSH_HANDLER should push an exception handler to the exception stack."
;

( c | -C- try-sys )
( r | -E- handler )
: TRY
    HERE 2 + >C
    0 COMPILE LITERAL
    [ CLEAR WORD PUSH_HANDLER FIND ] LITERAL ECR32
; IMMEDIATE

( c | try-sys -C- catch-sys )
( r | -D- exception )
: CATCH
    C>
    0 COMPILE BRANCH HERE >C
    HERE SWAP !q
; IMMEDIATE

( c | catch-sys -C- )
CREATE ENDTRY ALIAS THEN IMMEDIATE

( r | handler -E- | exception -D- )
: THROW
    TODO" THROW should pop an exception handler from the exception stack, pop a value from the data stack,
          and transfer control to the nearest handler while calling it with that exception value as an arg.
          Additionally, if the exception stack would underflow, it should call PANIC."
;
