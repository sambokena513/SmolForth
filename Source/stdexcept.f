( Dependencies: bootstrap.f, stdstring.f, stdassert.f, stdctx.f )

( <stdexcept.f> :; Exceptions and exception handling. Uses the exception stack from <stdctx.f>. )


( A handler in the code below refers to a value on the exception stack consisting of stack depths, and an address to resume execution at. )
(
    C-style reference for the handler struct:

    typedef struct Handler {
        i32 ip; // instruction pointer
        i32 rSP;
        i32 lSP;
        i32 dSP;
    } Handler; // 16 bytes in total
)

( Push, pop, and read a 32-bit value respectively from the exception stack. )
: >E eSP @d !d eSP @d 4 + eSP !d ;
: E> eSP @d -4 + eSP !d eSP @d @d ;
: E@ eSP @d -4 + @d ;

( r | -E- handler | handler-addr -D- )
: PUSH_HANDLER
    >E
    rSP@ BASE SWAP - 8 + >E
    lSP @d >E
    dSP@ BASE SWAP - >E
;

( r | handler -E- )
: POP_HANDLER
    eSP @d -16 + eSP !d
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
    [ CLEAR WORD POP_HANDLER FIND ] LITERAL ECR32
    C>
    0 COMPILE BRANCH HERE >C
    HERE SWAP !q
; IMMEDIATE

( c | catch-sys -C- )
CREATE ENDTRY ALIAS THEN IMMEDIATE

( r | handler -E- | exception -D- )
: THROW
    ( if eSP_BASE + 16 is greater than eSP we know that a pop would underflow the stack. )
    eSP @d CTX @d ctx.eSP_BASE FIELD @d 16 + > IF
        r" Uncaught Exception: install an exception handler or exit the process,
           Continuing may cause memory corruption." PANIC
    THEN

    ( we juggle the exception value through the exception stack so it isn't lost when we set dSP )
    E> SWAP >E BASE + dSP! E>
    E> lSP !d
    E> DUP E>
    BASE + SWAP !q ( write handler into the return address )
    BASE + rSP! ( restore return stack, thus throwing us into the handler )
;
