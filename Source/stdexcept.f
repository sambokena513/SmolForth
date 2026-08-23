( Dependencies: bootstrap.f, stdstring.f, stdctx.f )

( <stdexcept.f> :; Exceptions and exception handling. Uses the exception stack from <stdctx.f>. )

( c | -C- try-sys )
( r | -E- handler )
: TRY

; IMMEDIATE

( c | try-sys -C- catch-sys )
( r | -D- exception )
: CATCH

( c | catch-sys -C- )
; IMMEDIATE

: ENDTRY

; IMMEDIATE

( r | handler -E- )
( r | exception -D- )
( Note: apart from these stack effects THROW also restores data- and return-stack depth to what it was at the time of calling TRY. )
: THROW

;
