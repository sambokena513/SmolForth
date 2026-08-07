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

( Check if there is a run of *at least* n zero bits starting at addr, takes an address and desired run length.
Returns true if there is such a run, and false if there is not. )
: n0RUN? OVER SWAP 0RUN == ;

( Attempt to allocate n pages, returns the address of the first page if succesful, or -1 for failure. )
: pALLOC ;

( Free n pages starting from addr, takes address and number of pages to free, returns nothing. )
: pFREE ;