( Dependencies: bootstrap.f, stdstring.f, stdassert.f, stdctx.f, stdexcept.f, stdio.f, stddict.f )

( <stdlocal.f> :: Define words with access to local variables that don't inhibit recursion, and arguments, which are locals that automatically bind. )

WORD_T TMPVAR LOCAL_COUNT
DWORD_T TMPVAR LOCAL_START

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

( r | name -D- )
: __REF
    FIND DUP -1 == IF POP /' " No such word." 10 ,b '/ ABORT EXIT THEN

    EXECUTE COMPILE LITERAL
    ['] __REF_RUNTIME LITERAL ECR32
;

( r | name -D- )
: __VAL
    FIND DUP -1 == IF POP /' " No such word." 10 ,b '/ ABORT EXIT THEN

    EXECUTE COMPILE LITERAL
    ['] __VAL_RUNTIME LITERAL ECR32
;

( Parse the next word; which should be the name of a local, and compile `<offset> __REF_RUNTIME` )
: REF
    WORD __REF
; IMMEDIATE

( Parse the next word; which should be the name of a local, and compile `<offset> __VAL_RUNTIME`. )
: VAL
    WORD __VAL
; IMMEDIATE

( Start a function definition, locals and args may only be used within functions, not colon definitions. )
: FUNCTION
    ( start the word )
    LATEST LOCAL_START !d
    0 LOCAL_COUNT !w
    :

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
    COMPILE ;
; IMMEDIATE

( Parse and create a local. )
: local:
    TODO" Make a CONSTANT as a macro"
; IMMEDIATE

( Parse and create an arg. )
: arg:
    TODO" Make a CONSTANT as a macro, and also compile __REF !q for it."
; IMMEDIATE

( Parse and create locals until '}', effectively the same as calling local: separately for each word.
Note that this must be called *after* FUNCTION, it is invalid outside of a function definition, including inside
colon definitions. )
: {
    TODO" Call local: until '}'"
; IMMEDIATE

( Parse and create args until '\', same as calling arg: separately for each word.
Note that this should be called only *immediately after* FUNCTION because it depends on the code body of the word 
being empty. )
: #
    TODO" Call arg: until '\'"
; IMMEDIATE

FORGET LOCAL_COUNT POP
