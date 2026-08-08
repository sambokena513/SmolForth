( Dependencies: bootstrap.f, stdstring.f, stddict.f )

( <stdmem.f> :; This file implements a bitmap page allocator managing a 1.5GB heap.
This allows user code to use dynamic memory or to implement more sophisticated allocators. )

DWORD_T VARIABLE HEAP_BASE 512 1024 1024 * * HEAP_BASE !d
DWORD_T VARIABLE HEAP_MAP_BASE 8 4096 HEAP_BASE @d 3 * / / HEAP_BASE @d - HEAP_MAP_BASE !d

( @bit takes an image-relative bit address,
and fetches the corresponding bit,
returning either a 1 or a 0. )
: @bit 
    ( Since we don't have modulo we do it manually here. )
    DUP 8 SWAP / SWAP OVER 8 * SWAP - SWAP
    ( now the TOS is the byte address and NOS is the bit offset )
    @b >> 1 &
;

( !bit takes an image-relative bit address, and an integer which is 1 or 0,
and sets a bit to that value. )
: !bit 
    SWAP >C
    DUP 8 SWAP / SWAP OVER 8 * SWAP - SWAP
    SWAP OVER @b SWAP
    C> IF
       1 << |
    ELSE
        1 << ~ &
    THEN
    SWAP !b
;

( Search for a run of up to n zero bits starting at addr, takes an address and max run length.
Returns the length of the run, which can be anywhere from 0 to n. )
: 0RUN
    SWAP >C
    0 BEGIN
    OVER OVER C@ > SWAP @bit 0 == & WHILE
    1 + SWAP 1 + SWAP
    REPEAT
    SWAP C> POP POP 
;

: a_b->a_bit 8 * ;
: a_bit->a_b 8 SWAP / ;

( Set n bits to 1, takes a bit address and count. )
: setnb
    BEGIN
    OVER WHILE
        DUP 1 SWAP !bit
        1 + SWAP 1 SWAP - SWAP
    REPEAT
    POP POP
;

( Clear n bits, takes a bit address and count. )
: clnb
    BEGIN
    OVER WHILE
        DUP 0 SWAP !bit
        1 + SWAP 1 SWAP - SWAP
    REPEAT
    POP POP
;

: MIN
    OVER OVER < IF
        SWAP POP ( if a is smaller return a )
    ELSE
        POP ( if b is smaller or equal return b )
    THEN
;

( Attempt to allocate n pages, returns the address of the first page if succesful, or -1 for failure. )
: pALLOC
    >C
    [ HEAP_MAP_BASE @d a_b->a_bit ] LITERAL
    BEGIN
    DUP [ HEAP_BASE @d a_b->a_bit ] LITERAL > WHILE ( stop looping when we hit the end of the bitmap )
        DUP
        ( Clamp run length for 0RUN to stay in the bitmap. )
        DUP [ HEAP_BASE @d a_b->a_bit ] LITERAL - C@ MIN
        SWAP 0RUN DUP IF ( Try to find a run of n free pages. )
            DUP C@ == IF ( If the run is the right length we allocate it )
                C> POP

                OVER setnb ( mark bits as reserved )

                ( compute heap offset and return pointer )
                [ HEAP_MAP_BASE @d a_b->a_bit ] LITERAL SWAP -
                12 SWAP << [ HEAP_BASE @d ] LITERAL +
                EXIT
            ELSE
                + ( if run is shorter than requested we increment by it to avoid needlessly rescanning )
            THEN
        ELSE
            POP 1 + ( finally if there is no run we increment by 1 bit )
        THEN
    REPEAT
    C> POP POP -1
;

( Free n pages starting from addr, takes address and number of pages to free, returns nothing. )
: pFREE
    [ HEAP_BASE @d ] LITERAL SWAP - 12 SWAP >> ( compute index into bitmap )
    [ HEAP_MAP_BASE @d a_b->a_bit ] LITERAL + clnb ( index the bitmap and clear n bits in it )
;

( TODO: this allocator technically works but if we added 1 to 2 levels of summary bitmaps and a little 
more metadata it could be a lot faster for fragmented heaps or ones that have few free pages. Though that's for later. )