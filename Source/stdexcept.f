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

( Reference implementation: `: >E eSP @d !d eSP @d 4 + eSP !d ;`, while this is possible to
write in Forth, moving it into assembly made an exception overhead benchmark nearly twice as fast [from 5.7 to 3.7 seconds],
so it really is worth it to keep this native. )
: >E
    [
        65 ,b -117 ,b -121 ,b eSP ,d ( mov eax, [r15 + esP] )
        73 ,b -117 ,b 94 ,b -8 ,b ( mov rbx, [r14 - 8] )
        65 ,b -119 ,b 28 ,b 7 ,b ( mov [r15 + rax], ebx )
        65 ,b -125 ,b -121 ,b eSP ,d 4 ,b ( add dword [r15 + eSP], 4 )
        73 ,b -125 ,b -18 ,b 8 ,b ( sub r14, 8 )
    ]
;

: E> eSP @d -4 + eSP !d eSP @d @d ;
: E@ eSP @d -4 + @d ;


( r | -E- handler | handler-addr -D- )
( TODO: this could also be moved into assembly, we can keep the rest as-is since
the exceptional path isn't too common, but since PUSH_HANDLER gets called in the normal
path too, it's a large source of overhead. )
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

    ( we juggle the exception value through the control flow stack so it isn't lost when we set dSP )
    >C E> BASE + dSP! C>
    E> lSP !d
    E> DUP E>
    BASE + SWAP !q ( write handler into the return address )
    BASE + rSP! ( restore return stack, thus throwing us into the handler )
;

( r | xt -D- e_val :; ANS Forth-style catch taking an xt, returns the exception value if the word threw, or 0 if it didn't. )
: DYN_CATCH
    TRY
        EXECUTE 0
    CATCH
    ENDTRY
;

( Note that in our exceptions we consider 0 to be an invalid value, otherwise we wouldn't be able to implement DYN_CATCH properly. )

( Add new standard exception values here: )
MACROS

1 CONSTANT EXC_NOMEM

ENDMACROS
