( Dependencies: bootstrap.f, stdstring.f, stdassert.f, stdctx.f, stdexcept.f, stdio.f, stddict.f )

( <stdlocal.f> :: Define words with access to local variables that don't inhibit recursion, and arguments, which are locals that automatically bind. )

WORD_T TMPVAR LOCAL_COUNT
DWORD_T TMPVAR LOCAL_START
255 TMPVAR FUNC_NAME_BUF

( r | n -D- :; Allocate space for n locals on the local stack. )
: ENTER_FRAME
    QWORD_T * lSP @d + lSP !d
;

( r | n -D- :; Release space for n locals on the local stack. )
: LEAVE_FRAME
    QWORD_T * lSP @d - lSP !d
;

( Runtime functions for REF and VAL, we use this instead of directly compiling the
calls to keep generated code from being too big at the cost more call overhead. )
: __REF_RUNTIME
    lSP @d +
;

: __VAL_RUNTIME
    lSP @d + @q
;

( Internal implementations of REF and VAL that take string pointers. )

( r | xt -D- )
: __REF
    EXECUTE ['] __REF_RUNTIME LITERAL ECR32
;

( r | xt -D- )
: __VAL
    EXECUTE ['] __VAL_RUNTIME LITERAL ECR32
;

( Parse the next word; which should be the name of a local, and compile `<offset> __REF_RUNTIME` )
: REF
    ' DUP -1 == IF POP /' " No such word." 10 ,b '/ ABORT EXIT THEN __REF
; IMMEDIATE

( Parse the next word; which should be the name of a local, and compile `<offset> __VAL_RUNTIME`. )
: VAL
    ' DUP -1 == IF POP /' " No such word." 10 ,b '/ ABORT EXIT THEN __VAL
; IMMEDIATE

( Start a function definition, locals and args may only be used within functions, not colon definitions. )
: FUNCTION
    ( start the word )
    LATEST LOCAL_START !d
    0 LOCAL_COUNT !w

    ( start compiling )
    :
    FUNC_NAME_BUF WNB STRCPY

    0 COMPILE LITERAL ( placeholder literal, patched by ENDFUNC to the actual local count )
    ['] ENTER_FRAME LITERAL ECR32
    -24 ,b 23 ,d ( compile a call to just after the snippet )
    0 COMPILE LITERAL ( second placeholder literal )
    ['] LEAVE_FRAME LITERAL ECR32
    -61 ,b ( compile a ret )
;

( End a function definition. )
: ENDFUNC
    ( restore LATEST )
    LOCAL_START @d aINTERPS !d

    ( patch literals in start snippet to the actual local count )
    LOCAL_COUNT @w DUP
    COMP_START __LITva !d
    COMP_START 29 + !d
    
    ( finish definition )
    WNB FUNC_NAME_BUF STRCPY
    COMPILE ;
; IMMEDIATE

( Parse and create a local. )
: local:
    ( save comp_start of the current word since it would get corrupted by CONSTANT )
    COMP_START

    LOCAL_COUNT @w QWORD_T * -8 -
    MACROS CONSTANT ] ENDMACROS
    LOCAL_COUNT @w 1 + LOCAL_COUNT !w

    ( restore comp_start )
    aCOMP_START !d
; IMMEDIATE

( Parse and create an arg. )
: arg:
    COMPILE local:
    LATEST __REF
    ['] !q LITERAL ECR32
    ( TODO" Make a CONSTANT as a macro, and also compile __REF !q for it." )
; IMMEDIATE

( r | last-word -D- :; Un-parse the last word by setting TIB_IDX to its start and replacing its delimiter with a whitespace. )
: UN_WORD
    TIB OVER - aTIB_IDX !b
    DUP STRLEN + 32 SWAP !b
;

( Parse and create locals until '}', effectively the same as calling local: separately for each word.
Note that this must be called *after* FUNCTION, it is invalid outside of a function definition, including inside
colon definitions. )
: {
    WORD DUP r" }" STRCMP IF
        POP
    ELSE
        UN_WORD COMPILE local: TSELF
    THEN
; IMMEDIATE

( Parse and create args until '\', same as calling arg: separately for each word.
Note that this should be called only *immediately after* FUNCTION because it depends on the code body of the word 
being empty. )
: \
    WORD DUP r" \" STRCMP IF
        POP
    ELSE
        UN_WORD COMPILE arg: TSELF
    THEN
; IMMEDIATE

FORGET LOCAL_COUNT POP
FORGET LOCAL_START POP
FORGET FUNC_NAME_BUF POP
