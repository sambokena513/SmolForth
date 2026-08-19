( Dependencies: bootstrap.f, stdstring.f, stdio.f )

( <stddict.f> :; This file implements various dictionary introspection and modification
words for easier metaprogramming. )

( WORDCOUNT returns the number of entries in the current dictionary. )
: WORDCOUNT LATEST 0 BEGIN OVER WHILE 1 + SWAP @d SWAP REPEAT NIP ;

( WORDS prints every dictionary entry's name. )
: WORDS 
    LATEST
    BEGIN 
    DUP WHILE 
        DUP 9 +
        PRINT 32 PUTCHAR
        @d
    REPEAT
    POP 10 PUTCHAR
;

( __EXISTS? is a wrapper around FIND that returns whether a word matching a string
given to it is in the dictionary. )
: __EXISTS? FIND -1 == ~ ;

( __UNIQUE? takes a dictionary entry address, returns whether it is an alias of something else, or has a unique code body. )
: __UNIQUE? 8 + @b DUP 16 | == ~ ;

( __FORGET takes a string pointer representing a word name
and modifies the dictionary such that the word preceding it links
to the word after the target instead.
Note that __FORGET does not free memory, it only removes a word from the search space. )
: __FORGET
    DUP FIND -1 == IF
        POP -1 ( Return -1 for error. )
    ELSE
        >C
        aINTERPS BEGIN
        DUP @d 9 + C@ STRCMP ~ WHILE
            @d
        REPEAT ( after the loop TOS is the dictionary entry preceding the target )
        C> POP

        ( Patch link pointer to point to target's link rather than target itself. )
        DUP @d DUP >C @d SWAP !d
        C> ( Return address of removed entry for success. )

    THEN
;

( addr entr -- true | false :; Predicate, checks if a given address is part of
the given entry's code, note that this will not work properly on aliases. )
: INENTR 2DUP > IF 4 + @d <= ELSE 0 THEN ;

( addr -- entr | -1 :; Look up what word an address is part of,
returns -1 if the address is part of no word, otherwise returns the entry. )
: WHATIS
    LATEST BEGIN
    DUP WHILE
        2DUP INENTR OVER __UNIQUE? & IF
            NIP EXIT
        THEN
    @d REPEAT
    2POP -1
;

( Helper words for DIS, each takes an instruction address and returns a boolean. )
: __LIT? @b 72 == ;
: __0BR? @b 73 == ;
: __RET? @b -61 == ;
: __BRH? @b -23 == ;
: __CAL? @b -24 == ;

( Helper words for DIS, each takes an instruction address and returns the address of the dynamic part of the instruction. )
: __LITva 2 + ;
: __0BRva 10 + ;
: __RETva 0 + ;
: __BRHva 1 + ;
CREATE __CALva ALIAS __BRHva ( both instructions have the same offset )

( Helper words for DIS, each takes an instruction address and returns the address just after the instruction. )
: __LIT+ 17 + ;
: __0BR+ 14 + ;
: __RET+ 1 + ;
: __BRH+ 5 + ;
CREATE __CAL+ ALIAS __BRH+ ( both instructions are the same length )

( addr1 -- addr2 :; Dissassemble one instruction, helper used by DIS though you can call it directly. )
: __DIS_INSTR
    DUP DUP

    DUP __LIT? IF
        PRINTNUM r"   <LIT>  " PRINT __LITva @q .
        __LIT+ EXIT
    THEN

    DUP __0BR? IF
        PRINTNUM r"   <0BR>  " PRINT __0BRva @d .
        __0BR+ EXIT
    THEN

    DUP __BRH? IF
        PRINTNUM r"   <BRH>  " PRINT __BRHva @d .
        __BRH+ EXIT
    THEN

    DUP __RET? IF
        PRINTNUM r"   <RET>  " PRINT __RETva @b .
        __RET+ EXIT
    THEN

    DUP __CAL? IF
        PRINTNUM r"   <CAL>  " PRINT
        DUP __CAL+ SWAP __CALva @d +

        WHATIS DUP -1 <> IF
            9 + PRINTLN
        ELSE
            POP r" <N/A>" PRINTLN
        THEN

        __CAL+ EXIT
    THEN

    PRINTNUM r"  <N/A>  " PRINT @b . 1 + 
;

( end start -- :; Disassemble instructions from <start> to <end>, note that DIS is a Forth disassembler, not a general x64 one.
It recognizes only word calls, literals, 0BRANCH, and BRANCH, and it recognizes them by a simple heuristic of checking the first byte.
As such, it may behave strangely on embedded string literals depending on the values, as well as if run on a word that is not a regular colon definition. )
: DIS
    BEGIN
    2DUP < WHILE
        __DIS_INSTR
    REPEAT 2POP
;

( -- :; SEE parses a word from the input source and calls DIS with the start address as the start of that word,
and the end address as the end of said word. )
: SEE
    WORD FIND DUP -1 == IF
        POP r" No such word." PRINTLN EXIT
    THEN

    DUP 4 + @d DIS
;

( REPL versions of the respective underscore words. )
: EXISTS? WORD __EXISTS? ;
: FORGET WORD __FORGET ;
: UNIQUE? WORD FIND __UNIQUE? ;

( ' is an alternative to the usual `CLEAR WORD word FIND` phrase that behaves atomically,
this makes it simpler to use without needing to worry about parser state and pointers getting
invalidated. )
: ' WORD FIND ;
CREATE ['] ALIAS ' IMMEDIATE

( WORDLEN is a simple word that gets the length of a colon definition,
this is not valid to use on words that were created using the `CREATE word ALIAS target` phrase,
as those do not have their entries placed right after their bodies.
And neither does it work on fresh dict entries that are still using the placeholder code pointer. )
: WORDLEN ' DUP 4 + @d SWAP - ;
