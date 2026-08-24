( Dependencies: bootstrap.f, stdstring.f, stdassert.f, stdctx.f, stdexcept.f, stdio.f, stddict.f )

( <stdinit.f> :; INIT function that can be used with SET_INIT to make interactive images that
first reset all important stdlib state before calling INTERPRET. )

: CTX_INIT
    ( make sure that upon starting we are in the main context )
    MAIN_CTX CTX !d
    MAIN_eSP_BASE eSP !d
    MAIN_lSP_BASE lSP !d

    ( make sure that the main context has expected values )
    8 @d MAIN_CTX ctx.dSP_BASE FIELD !d
    8 @d MAIN_CTX ctx.dSP FIELD !d

    12 @d MAIN_CTX ctx.rSP_BASE FIELD !d
    ( we offset rSP here so that its value becomes what 0 0 SAVE_CTX would write when called in INTERPRET, not here. )
    12 @d -32 + MAIN_CTX ctx.rSP FIELD !d

    MAIN_eSP_BASE MAIN_CTX ctx.eSP_BASE FIELD !d
    MAIN_eSP_BASE MAIN_CTX ctx.eSP FIELD !d

    MAIN_lSP_BASE MAIN_CTX ctx.lSP_BASE FIELD !d
    MAIN_lSP_BASE MAIN_CTX ctx.lSP FIELD !d
;

: INIT
    CTX_INIT
    HEAP_INIT
    r" Welcome to SmolForth!" PRINTLN
    INTERPRET
;
