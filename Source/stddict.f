( Dependencies: bootstrap.f, stdstring.f )

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

( EXISTS? is a wrapper around FIND that returns whether a word matching a string \
given to it is in the dictionary.
)
: EXISTS? FIND -1 == IF 0 ELSE -1 THEN ;