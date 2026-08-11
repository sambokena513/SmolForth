( Dependencies: bootstrap.f, stdstring.f, stddict.f )

( <stdmem.f> :; This file implements a bitmap page allocator managing a 1.5GB heap.
This allows user code to use dynamic memory or to implement more sophisticated allocators. )

DWORD_T VARIABLE HEAP_BASE 512 1024 1024 * * HEAP_BASE !d
DWORD_T VARIABLE HEAP_MAP_BASE 8 4096 HEAP_BASE @d 3 * / / HEAP_BASE @d - HEAP_MAP_BASE !d

: a_b->a_bit 3 SWAP << ;
: a_bit->a_b 3 SWAP >> ;

( @bit takes an image-relative bit address,
and fetches the corresponding bit,
returning either a 1 or a 0. )
: @bit 
    ( Since we don't have modulo we do it manually here. )
    DUP a_bit->a_b SWAP OVER a_b->a_bit SWAP - SWAP
    ( now the TOS is the byte address and NOS is the bit offset )
    @b >> 1 &
;

( !bit takes an image-relative bit address, and an integer which is 1 or 0,
and sets a bit to that value. )
: !bit 
    SWAP >C
    DUP a_bit->a_b SWAP OVER a_b->a_bit SWAP - SWAP
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

(
    Design for the improved allocator:

        Metadata:

            - extent list
            - buckets
            - extents

            extent := Struct with the shape:

                dd start_page
                dd page_count
                dd prev
                dd next

                represents N free pages.

            extent list := doubly-linked list of extents ordered
            by place in the heap, note that this list is *intrusive*,
            meaning each extent node is placed inside the actual free
            page/pages, this causes some extra copying when splitting or resizing
            extents but it also fixes a large issue we would otherwise have of
            how to reuse extent node memory when the actual backing memory of
            the linked list only lets us move forward, not reuse nodes.

            buckets := A bucket is a stack of extent pointers
                in a size class, where we have 5 size classes:

                - 1-8
                - 8-16
                - 17-32
                - 32-64
                - over 64

        Allocation:

            Select the size class of the allocation, and pop one extent
            from the corresponding bucket (if empty just use a bigger bucket),
            then if allocation is equal to extent size just remove the extent
            and return the page address, else split off a chunk of the extent
            and return the address of the removed part, while moving it to a
            different bucket if it changed size classes.

        Freeing:

            Search the extent list for the extent right before the address being
            freed, if its end address matches the start of the freed address,
            extend it, then if its end address suddenly matches the start of the
            next extent, merge repeatedly until it does not match, then if it 
            changed size class, search for it in its bucket, remove it, and insert
            it into its new bucket.
            If the addresses do not match, just create a new extent and insert it
            into the appropriate bucket.
)