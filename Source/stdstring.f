: STRLEN 
    0 BEGIN
        OVER @b
    WHILE
        1 + SWAP 1 + SWAP
    REPEAT
    SWAP POP
;
: STRCPY
    BEGIN
    DUP @b WHILE
        OVER OVER @b SWAP !b
        1 + SWAP 1 + SWAP
    REPEAT
    POP
    POP
;
: STRCMP
    BEGIN
    DUP @b WHILE
        OVER OVER @b SWAP @b <>
        IF POP POP 0 EXIT THEN
        1 + SWAP 1 + SWAP
    REPEAT
    POP
    POP
    -1
;
CREATE ) 
: (
    BEGIN
    WORD [ CLEAR WORD ) FIND 9 + ] LITERAL
    STRCMP
    UNTIL
; IMMEDIATE

( Dependencies: bootstrap.f )

( <stdstring.f> :; This file implements string handling functions as well as comments.
This description of it is later in the file than for other parts of the stdlib because once again,
this *is* the file that implements them, and we cannot use comments until they exist. )

( WHITESPACE and NEWLINE respectively are in-memory constants for the values of \
ASCII space and ASCII newline characters, the reason for making them with VARIABLE \
instead of just being immediate words that push 32 and 10 respectively to the stack \
is so that they can be used in sys_write for example to implement things like println and putln.
)
BYTE_T VARIABLE WHITESPACE 32 WHITESPACE !b
BYTE_T VARIABLE NEWLINE 10 NEWLINE !b

( Get one character from the terminal input buffer and advance the parsing cursor. )
: GETCHAR
    TIB_LEN 255 & 255 == IF
        CLEAR
        TSELF
    THEN

    TIB_IDX TIB_LEN == IF
        REFILL
        TSELF
    THEN

    TIB_IDX 255 & aTIB + @b
    TIB_IDX 1 + aTIB_IDX !b
;

( Compiles a string constant into a definition,
does not handle escape sequences. )
CREATE "
: r"
    GETCHAR BEGIN
    DUP 34 <> WHILE
        ,b GETCHAR
    REPEAT
    0 ,b
; IMMEDIATE