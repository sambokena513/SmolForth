( Dependencies: bootstrap.f, stdstring.f, stdassert.f, stdctx.f, stdexcept.f, stdio.f, stddict.f )

( <stdlocal.f> :: Define words with access to local variables that don't inhibit recursion, and arguments, which are locals that automatically bind. )

CLEAR WORD STDLOCAL_F FIND ~ POPBUFXT EXEC_IF CREATE STDLOCAL_F

WORD_T TMPVAR LOCAL_COUNT
DWORD_T TMPVAR LOCAL_START
255 TMPVAR FUNC_NAME_BUF

(
    Note, while none of these functions are impossible [ or even difficult ] to write in Forth,
    we use some machine code here for performance to eliminate a bit of overhead.
    This makes ENTER_FRAME and LEAVE_FRAME about 50% faster overall.
)

( r | n -D- :; Allocate space for n locals on the local stack. Reference: `QWORD_T * lSP @d + lSP !d` )
: ENTER_FRAME
    [
        65 ,b -64 ,b 102 ,b -8 ,b 3 ,b ( shl [r14 - 8], 3 )
        65 ,b -117 ,b -121 ,b lSP ,d ( mov eax, [r15 + lSP] )
        73 ,b 3 ,b 70 ,b -8 ,b ( add rax, [r14 - 8] )
        73 ,b -125 ,b -18 ,b 8 ,b ( sub r14, 8 )
        65 ,b -119 ,b -121 ,b lSP ,d ( mov [r15 + lSP], eax )
    ]
;

( r | n -D- :; Release space for n locals on the local stack. Reference: `QWORD_T * lSP @d - lSP !d` )
: LEAVE_FRAME
    [
        65 ,b -64 ,b 102 ,b -8 ,b 3 ,b ( shl [r14 - 8], 3 )
        65 ,b -117 ,b -121 ,b lSP ,d ( mov eax, [r15 + lSP] )
        73 ,b 43 ,b 70 ,b -8 ,b ( sub rax, [r14 - 8] )
        73 ,b -125 ,b -18 ,b 8 ,b ( sub r14, 8 )
        65 ,b -119 ,b -121 ,b lSP ,d ( mov [r15 + lSP], eax )
    ]
;

( Runtime functions for REF and VAL, we use this instead of directly compiling the
calls to keep generated code from being too big at the cost more call overhead. )

( reference: `lSP @d + !q` )
: __TO_RUNTIME
    [
        65 ,b -117 ,b -121 ,b lSP ,d ( mov eax, [r15 + lSP] )
        73 ,b 3 ,b 70 ,b -8 ,b ( add rax, [r14 - 8] )
        73 ,b -117 ,b 94 ,b -16 ,b ( mov rbx, [r14 - 16] )
        73 ,b -119 ,b 28 ,b 7 ,b ( mov [r15 + rax], rbx )
        73 ,b -125 ,b -18 ,b 16 ,b ( sub r14, 16 )
    ]
;

( reference `lSP @d + @q` )
: __LOCAL_RUNTIME
    [
        65 ,b -117 ,b -121 ,b lSP ,d ( mov eax, [r15 + lSP] )
        73 ,b 3 ,b 70 ,b -8 ,b ( add rax, [r14 - 8] )
        73 ,b -117 ,b 28 ,b 7 ,b ( mov rbx, [r15 + rax] )
        73 ,b -119 ,b 94 ,b -8 ,b ( mov [r14 - 8], rbx )
    ]
;

( Internal implementations of REF and VAL that take string pointers. )

( r | xt -D- )
: __TO
    4 + @d 2 + @q COMPILE LITERAL
    ['] __TO_RUNTIME LITERAL ECR32
;

( Parse the next word, which should be the name of a local, and arrange for a value to be popped from the stack
into that local at runtime. )
: TO
    ' DUP -1 == IF POP /' " No such word." 10 ,b '/ ABORT EXIT THEN __TO
; IMMEDIATE

DWORD_T TMPVAR LITa1
DWORD_T TMPVAR LITa2
DWORD_T TMPVAR CALa

( Start a function definition, locals and args may only be used within functions, not colon definitions. )
: FUNCTION
    ( start the word )
    LATEST LOCAL_START !d
    0 LOCAL_COUNT !w

    ( start compiling )
    :
    FUNC_NAME_BUF WNB STRCPY

    (
        We make the function get called through a trampoline
        that makes sure locals are properly allocated and freed.
    )

    HERE LITa1 !d 0 COMPILE LITERAL
    ['] ENTER_FRAME LITERAL ECR32
    HERE CALa !d -24 ,b 0 ,d ( compile a placeholder call )
    HERE LITa2 !d 0 COMPILE LITERAL
    ['] LEAVE_FRAME LITERAL ECR32

    -61 ,b ( compile a ret )

    ( patch the placeholder call )
    CALa @d 5 + HERE -
    CALa @d 1 + !d
;

( End a function definition. )
: ENDFUNC
    ( restore LATEST )
    LOCAL_START @d aINTERPS !d

    ( patch literals in start snippet to the actual local count )
    LOCAL_COUNT @w LITa1 @d 2 + !q
    LOCAL_COUNT @w LITa2 @d 2 + !q
    
    ( finish definition )
    WNB FUNC_NAME_BUF STRCPY
    COMPILE ;
; IMMEDIATE

FORGET LITa1 POP
FORGET LITa2 POP
FORGET CALa POP

( Parse and create a local. )
: local:
    ( save comp_start of the current word since it would get corrupted by the new definition )
    COMP_START

    MACROS

    ( define the local )
    :

    LOCAL_COUNT @w QWORD_T * -8 - COMPILE LITERAL
    ['] LITERAL LITERAL ECR32

    ['] __LOCAL_RUNTIME LITERAL COMPILE LITERAL
    ['] ECR32 LITERAL ECR32

    COMPILE ;
    UNIQUE IMMEDIATE

    ] ENDMACROS

    LOCAL_COUNT @w 1 + LOCAL_COUNT !w

    ( restore comp_start )
    aCOMP_START !d
; IMMEDIATE

( Parse and create an arg. )
: arg:
    COMPILE local:
    LATEST __TO
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
