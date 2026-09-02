( Dependencies: bootstrap.f, stdstring.f, stdassert.f, stdctx.f, stdexcept.f, stdio.f, stddict.f, stdlocal.f, stdmem.f, stdinclude.f, stdslab.f, stdco.f )

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

: MACRO_INIT
    MACRO_HERE_START MACRO_HERE !d
;

: INIT
    CTX_INIT
    MACRO_INIT
    HEAP_INIT
    STDCO_INIT
    0 ['] INTERPRET LITERAL SPAWN_TASK
    DUP -1 == IF
        r" FATAL: Could not allocate memory for REPL task." PRINTLN EXIT
    THEN
    r" Welcome to SmolForth!" PRINTLN
    SWITCH_TASK
    r" All tasks finished. Shutting down..." PRINTLN
;
