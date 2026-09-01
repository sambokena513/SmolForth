( Dependencies: bootstrap.f, stdstring.f, stdassert.f, stdctx.f, stdexcept.f, stdio.f, stddict.f, stdmem.f )

( <stdinclude.f> :; This file implements the ability to include source files such as libraries in files or the REPL. )

MACROS

0 CONSTANT buf.tib
255 CONSTANT buf.idx
256 CONSTANT buf.len
257 CONSTANT buf.fd
261 CONSTANT buf.eof
262 CONSTANT buf.parent

ENDMACROS

( r | tib -D- :; Print an input buffer's fields. )
: PRINT_INPBUF
   r" TIB_IDX: " PRINT DUP buf.idx FIELD @b 255 & .
   r" TIB_LEN: " PRINT DUP buf.len FIELD @b 255 & .
   r" TIB_FD: " PRINT DUP buf.fd FIELD @d .
   r" TIB_EOF: " PRINT DUP buf.eof FIELD @b .
   r" TIB_PARENT: " PRINT buf.parent FIELD @d .
;

( r | filepath -D- err? :; Open a file, allocate and initialize an input buffer for it, and switch the active buffer to that one. )
: ENTER_FILE
    0 SWAP 2048 SWAP BASE + OPEN

    1 pALLOC DUP -1 == IF EXIT THEN

    TUCK buf.fd FIELD !d
    0 OVER buf.idx FIELD !b
    0 OVER buf.len FIELD !b
    0 OVER buf.eof FIELD !b
    TIB OVER buf.parent FIELD !d

    aTIB !d

    0
;

: LEAVE_FILE
    TIB
    DUP buf.fd FIELD @d CLOSE POP
    1 OVER pFREE
    buf.parent FIELD @d aTIB !d
;
( Register LEAVE_FILE as the function for closing an input buffer in the runtime. )
' LEAVE_FILE aPOPBUFXT !d

( r | -D- :; Get a filepath from the TIB and switch the current TIB to that file. )
: INCLUDE
    WORD ENTER_FILE -1 == IF EXC_NOMEM THROW THEN
;
