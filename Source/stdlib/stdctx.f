( Dependencies: bootstrap.f, stdstring.f )

( <stdctx.f> :; Execution contexts and the ability to switch between them, as
well as various related utilities. )

CLEAR WORD STDCTX_F FIND ~ POPBUFXT EXEC_IF CREATE STDCTX_F

( Remember that because CTX is a VARIABLE it means to get the first field,
you'd do `CTX @d @d`, not `CTX @d`, or to get an offset into the third field,
`CTX @d ctx.eSP_BASE FIELD` )
HERE 32 ALLOT DWORD_T VARIABLE CTX CTX !d
CTX @d CONSTANT MAIN_CTX

( Note that these stack pointers and base pointers are image-relative, despite the fact that
the dSP@ and rSP@ words use absolute pointers. )
MACROS

0 CONSTANT ctx.dSP_BASE CTX @d ctx.dSP_BASE FIELD 8 @d SWAP !d
4 CONSTANT ctx.rSP_BASE CTX @d ctx.rSP_BASE FIELD 12 @d SWAP !d
ENDMACROS HERE 4096 ALLOT MACROS 8 CONSTANT ctx.eSP_BASE CTX @d ctx.eSP_BASE FIELD !d
ENDMACROS HERE 4096 ALLOT MACROS 12 CONSTANT ctx.lSP_BASE CTX @d ctx.lSP_BASE FIELD !d

ENDMACROS

(
    While the base pointers of a context should always be up to date,
    these pointers are allowed to be out-of date in the interests of performance.

    If you need the current state of these call SAVE_CTX first, which will set all
    all of them to their current values.
)

MACROS

16 CONSTANT ctx.dSP dSP@ BASE SWAP - MAIN_CTX ctx.dSP FIELD !d
( a note on rSP specifically, since this is implemented with the hardware return stack rsp,
I can't really control how it works relating to stack discipline, so just remember here that while every
forth *software* stack will always have the stack pointer pointing to the next *empty slot*, rSP instead
points to the *top item*. )
20 CONSTANT ctx.rSP rSP@ BASE SWAP - MAIN_CTX ctx.rSP FIELD !d
24 CONSTANT ctx.eSP MAIN_CTX ctx.eSP_BASE FIELD @d MAIN_CTX ctx.eSP FIELD !d
28 CONSTANT ctx.lSP MAIN_CTX ctx.lSP_BASE FIELD @d MAIN_CTX ctx.lSP FIELD !d

ENDMACROS

(
    Actual eSP and lSP variables for use in the implementation of locals and exceptions,
    these are the values copied into ctx.*SP by SAVE_CTX
)

MAIN_CTX ctx.eSP_BASE FIELD @d CONSTANT MAIN_eSP_BASE
MAIN_CTX ctx.lSP_BASE FIELD @d CONSTANT MAIN_lSP_BASE
DWORD_T VARIABLE eSP MAIN_eSP_BASE eSP !d
DWORD_T VARIABLE lSP MAIN_lSP_BASE lSP !d

( SAVE_CTX sets the current stack pointer fields in the current context to their values at the time of the call.
While applying an offset to the saved data stack and return stack pointers. )
: SAVE_CTX ( dSP_offset rSP_offset -- )
    rSP@ BASE SWAP - 8 + + CTX @d ctx.rSP FIELD !d
    dSP@ BASE SWAP - -8 + - CTX @d ctx.dSP FIELD !d
    eSP @d CTX @d ctx.eSP FIELD !d
    lSP @d CTX @d ctx.lSP FIELD !d
;

( RUN_CTX sets the current stack pointers based on the fields in the current context at the time of the call. )
: RUN_CTX
    CTX @d ctx.eSP FIELD @d eSP !d
    CTX @d ctx.lSP FIELD @d lSP !d
    CTX @d ctx.dSP FIELD @d BASE + dSP!
    CTX @d ctx.rSP FIELD @d BASE + rSP!
;

( SWITCH_CTX is essentially the atomic task-swapping primitive.
It takes in a context, saves the current context such that execution resumes right after the call to SWITCH_CTX,
which is where you should put your cleanup code, and then switches to that context. )
: SWITCH_CTX ( ctx -- )
   8 8 SAVE_CTX ( one slot offset for rSP because of the SWITCH_CTX call frame, and one for dSP because of the ctx argument. )
   CTX !d RUN_CTX ( make the context switch )
;

: dDEPTH dSP@ BASE SWAP - CTX @d ctx.dSP_BASE FIELD @d SWAP - 3 SWAP >> ;
: rDEPTH rSP@ 8 + BASE SWAP - CTX @d ctx.rSP_BASE FIELD @d - 3 SWAP >> ;

( r | val ctx -D- :; "Remote push", push a value to a context's data stack. )
: >rD
    ctx.dSP FIELD TUCK @d !q DUP @d 8 + SWAP !d
;

( r | val ctx -D- :; Like >rD but for the return stack. )
: >rR
    ctx.rSP FIELD TUCK @d -8 + !q DUP @d -8 + SWAP !d
;
