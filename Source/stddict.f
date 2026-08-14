( Dependencies: bootstrap.f, stdstring.f )

( <stddict.f> :; This file implements various dictionary introspection and modification
words for easier metaprogramming. )

( WORDCOUNT returns the number of entries in the current dictionary. )
: WORDCOUNT LATEST 0 BEGIN OVER WHILE 1 + SWAP @d SWAP REPEAT SWAP POP ;

( WORDS prints every dictionary entry's name. )
: WORDS 
    LATEST
    BEGIN 
    DUP WHILE 
        DUP 9 + DUP >C STRLEN >C

        0 DUP DUP C> C> BASE + 1 DUP SYSCALL POP
        0 DUP DUP 1 WHITESPACE BASE + 1 DUP SYSCALL POP
        
        @d
    REPEAT
    POP
    0 DUP DUP 1 NEWLINE BASE + 1 DUP SYSCALL POP
;

( __EXISTS? is a wrapper around FIND that returns whether a word matching a string
given to it is in the dictionary. )
: __EXISTS? FIND -1 == ~ ;

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

( REPL versions of __EXISTS? and __FORGET )
: EXISTS? WORD __EXISTS? ;
: FORGET WORD __FORGET ;

( ' is an alternative to the usual `CLEAR WORD word FIND` phrase that behaves atomically,
this makes it simpler to use without needing to worry about parser state and pointers getting
invalidated. )
: ' WORD FIND ;

( WORDLEN is a simple word that gets the length of a colon definition,
this is not valid to use on words that were created using the `CREATE word ALIAS target` phrase,
as those do not have their entries placed right after their bodies.
And neither does it work on fresh dict entries that are still using the placeholder code pointer. )
: WORDLEN ' DUP 4 + @d SWAP - ;