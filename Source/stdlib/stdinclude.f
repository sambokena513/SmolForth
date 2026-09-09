( Dependencies: bootstrap.f, stdstring.f, stdassert.f, stdctx.f, stdexcept.f, stdio.f, stddict.f, stdmem.f )

( <stdinclude.f> :; This file implements the ability to include source files such as libraries in files or the REPL. )

CLEAR WORD STDINCLUDE_M FIND ~ POPBUFXT EXEC_IF MACROS CREATE STDINCLUDE_M

0 CONSTANT buf.tib
255 CONSTANT buf.idx
256 CONSTANT buf.len
257 CONSTANT buf.fd
261 CONSTANT buf.eof
262 CONSTANT buf.parent

( r | tib -D- :; Print an input buffer's fields. )
: PRINT_INPBUF
   r" TIB_IDX: " PRINT DUP buf.idx FIELD @b 255 & .
   r" TIB_LEN: " PRINT DUP buf.len FIELD @b 255 & .
   r" TIB_FD: " PRINT DUP buf.fd FIELD @d .
   r" TIB_EOF: " PRINT DUP buf.eof FIELD @b .
   r" TIB_PARENT: " PRINT buf.parent FIELD @d .
;

( get the installation directory of our forth [ working dir at time of img build ],
and embed it into the image )
: GETCWD
    79 #SYSCALL2
;

4096 VARIABLE INSTALL_DIR_TMPBUF
: GENERATE_INSTALL_DIR
    4096 INSTALL_DIR_TMPBUF BASE + GETCWD POP

    INSTALL_DIR_TMPBUF STRLEN 1 + VARIABLE
    LATEST EXECUTE INSTALL_DIR_TMPBUF STRCPY
;

ENDMACROS

CLEAR WORD STDINCLUDE_F FIND ~ POPBUFXT EXEC_IF CREATE STDINCLUDE_F

GENERATE_INSTALL_DIR FORTHDIR

( r | filepath dirfd -D- err? :; See ENTER_FILE. )
: ENTER_FILE_AT
    >C >C 0 2048 C> BASE + C> OPENAT

    1 pALLOC DUP -1 == IF EXIT THEN

    TUCK buf.fd FIELD !d
    0 OVER buf.idx FIELD !b
    0 OVER buf.len FIELD !b
    0 OVER buf.eof FIELD !b
    TIB OVER buf.parent FIELD !d

    aTIB !d

    0
;

( r | filepath -D- err? :; Open a file, allocate and initialize an input buffer for it, and switch the active buffer to that one. )
: ENTER_FILE
    AT_FDCWD ENTER_FILE_AT
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

( r | -D- :; INCLUDE, but the filepath is relative to the installation directory instead of the working directory. )
: <INCLUDE>
    WORD 0 0 FORTHDIR BASE + OPEN ENTER_FILE_AT -1 == IF EXC_NOMEM THROW THEN
;

( IFDEF and IFNDEF are basic compositions of EXISTS? and EXEC_IF, they take an xt and execute it if something is defined or not.
Usually used for include guards in the phrase `POPBUFXT IFDEF MYFILE_F` or alternatively, `' LEAVE_FILE IFDEF MYFILE_F` )
: IFDEF
    EXISTS? SWAP EXEC_IF
;

: IFNDEF
    FIND -1 == SWAP EXEC_IF
;
