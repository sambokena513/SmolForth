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

( WHITESPACE and NEWLINE respectively are in-memory constants for the values of \
ASCII space and ASCII newline characters, the reason for making them with VARIABLE \
instead of just being immediate words that push 32 and 10 respectively to the stack \
is so that they can be used in sys_write for example to implement things like println and putln.
)
BYTE_T VARIABLE WHITESPACE 32 WHITESPACE !b
BYTE_T VARIABLE NEWLINE 10 NEWLINE !b