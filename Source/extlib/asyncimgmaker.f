INCLUDE extlib/extasyncio.f

: MAIN
    CORE_INIT 
    ASYNCIO_INIT
    r" Welcome to SmolForth!" PRINTLN
    FALSE ['] INTERPRET LITERAL
    ASYNC_START
    r" Shutting down..." PRINTLN
;

SET_INIT MAIN
SNAPSHOT asyncforth.fif EXIT
