( Dependencies: bootstrap.f, stdstring.f )

( <stdctx.f> :; Execution contexts and the ability to switch between them, as
well as various related utilities. )

( Remember that because CTX is a VARIABLE it means to get the first field,
you'd do `CTX @d @d`, not `CTX @d`, or to get an offset into the third field,
`CTX @d ctx.eSP_BASE FIELD` )
HERE 32 ALLOT DWORD_T VARIABLE CTX CTX !d

( Note that these stack pointers and base pointers are image-relative, despite the fact that
the dSP@ and rSP@ words use absolute pointers. )
0 CONSTANT ctx.dSP_BASE CTX @d ctx.dSP_BASE FIELD 8 @d SWAP !d
4 CONSTANT ctx.rSP_BASE CTX @d ctx.rSP_BASE FIELD 12 @d SWAP !d
HERE 4096 ALLOT 8 CONSTANT ctx.eSP_BASE CTX @d ctx.eSP_BASE FIELD !d
HERE 4096 ALLOT 12 CONSTANT ctx.lSP_BASE CTX @d ctx.lSP_BASE FIELD !d

(
    While the base pointers of a context should always be up to date,
    these pointers are allowed to be out-of date in the interests of performance.

    If you need the current state of these call UPDATE_CTX first, which will set all
    all of them to their current values.
)

16 CONSTANT ctx.dSP CTX @d ctx.dSP FIELD CTX @d ctx.dSP_BASE FIELD @d SWAP !d
( a note on rSP specifically, since this is implemented with the hardware return stack rsp,
I can't really control how it works relating to stack discipline, so just remember here that while every
forth *software* stack will always have the stack pointer pointing to the next *empty slot*, rSP instead
points to the *top item*. )
20 CONSTANT ctx.rSP CTX @d ctx.rSP FIELD CTX @d ctx.rSP_BASE FIELD @d SWAP !d 
24 CONSTANT ctx.eSP CTX @d ctx.eSP FIELD CTX @d ctx.eSP_BASE FIELD @d SWAP !d
28 CONSTANT ctx.lSP CTX @d ctx.lSP FIELD CTX @d ctx.lSP_BASE FIELD @d SWAP !d

(
    Actual eSP and lSP variables for use in the implementation of locals and exceptions,
    these are the values copied into ctx.*SP by UPDATE_CTX
)

DWORD_T VARIABLE eSP CTX @d ctx.eSP FIELD @d eSP !d
DWORD_T VARIABLE lSP CTX @d ctx.lSP FIELD @d lSP !d

( UPDATE_CTX sets the current stack pointer fields in the current context to their values at the time of the call. )
: UPDATE_CTX
    eSP @d CTX @d ctx.eSP FIELD !d
    lSP @d CTX @d ctx.lSP FIELD !d
    dSP@ BASE SWAP - CTX @d ctx.dSP FIELD !d
    rSP@ BASE SWAP - 8 + ( 8 + to skip the return address pushed by UPDATE_CTX itself being called. ) CTX @d ctx.rSP FIELD !d
;

( RUN_CTX sets the current stack pointers based on the fields in the current context at the time of the call. )
: RUN_CTX
    CTX @d ctx.eSP FIELD @d eSP !d
    CTX @d ctx.lSP FIELD @d lSP !d
    CTX @d ctx.dSP FIELD @d BASE + dSP!
    CTX @d ctx.rSP FIELD @d BASE + rSP!
;
