: STRLEN 
    0 BEGIN
        OVER @b
    WHILE
        1 + SWAP 1 + SWAP
    REPEAT
    NIP
;
: STRCPY
    BEGIN
    DUP @b WHILE
        2DUP @b SWAP !b
        1 + SWAP 1 + SWAP
    REPEAT
    POP
    0 SWAP !b
;
: STRCMP
    BEGIN
    DUP @b WHILE
        2DUP @b SWAP @b <>
        IF 2POP 0 EXIT THEN
        1 + SWAP 1 + SWAP
    REPEAT
    @b SWAP @b ==
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

( Get one character from the terminal input buffer and advance the parsing cursor. )
: GETCHAR
    TIB_IDX TIB_LEN == IF
        TIB_LEN 255 & 255 == IF
            CLEAR
        THEN

        REFILL
        TSELF
    THEN

    TIB_IDX 255 & TIB + @b
    TIB_IDX 1 + aTIB_IDX !b
;

( Compile characters until " delimiter. )
: "
    GETCHAR BEGIN
    DUP 34 <> WHILE
        ,b GETCHAR
    REPEAT
    POP
; IMMEDIATE

( Mark the start of a string literal, used when you want to emit specific bytes
since our general string parser does not handle escapes. )
: /'
    0 COMPILE BRANCH HERE >C
    HERE
    COMPILE [ ( so that users can do stuff like emit bytes inside string literals )
; IMMEDIATE

( Mark the end of a string literal. )
: '/
    0 ,b
    COMPILE THEN
    COMPILE LITERAL
    ] ( back to compile mode after the string )
; IMMEDIATE

( Compiles a string constant into a definition,
does not handle escape sequences. )
: r"
    COMPILE /'
    COMPILE " ( " ( comment so that the editor doesn't think this is an unterminated string literal )
    COMPILE '/
; IMMEDIATE
