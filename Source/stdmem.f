( Dependencies: bootstrap.f, stdstring.f, stdio.f, stddict.f, stdassert.f )

( <stdmem.f> :; This file implements an extent-based page allocator managing a 1.5GB heap.
This allows user code to use dynamic memory or to implement more sophisticated allocators. )

(
    Allocator Design:

        Metadata:

            - extent list
            - buckets
            - extents

            extent := Struct with the shape:

                struct extent {
                    i32 page_count;

                    struct extent *prev;
                    struct extent *next;

                    struct extent *prev_bucket;
                    struct extent *next_bucket;
                };

                Each extent represents N free pages.

            extent list := doubly-linked list of extents ordered
            by place in the heap, note that this list is *intrusive*,
            meaning each extent node is placed inside the actual free
            page/pages, this causes some extra copying when splitting or resizing
            extents but it also fixes a large issue when we would otherwise have the problem of
            how to reuse extent node memory when the actual backing memory of
            the linked list only lets us move forward, not reuse nodes.

            buckets := A bucket is a list of extents meeting a minimum size,
                with these thresholds:

                - extent_size == 1
                - extent_size >= 2
                - extent_size >= 4
                - extent_size >= 8
                - extent_size >= 16
                - extent_size >= 32
                - extent_size >= 64
                - extent_size >= 128
                - extent_size >= 256
                - extent_size >= 512
                - extent_size >= 1024

                Note; an extent always belongs exactly to one bucket,
                that being the largest it meets the minimum size for.

        Allocation:

            Select the smallest size class that is guaranteed to satisfy the allocation,
            and pop one extent from the corresponding bucket (if empty just use a bigger bucket),
            then if allocation is equal to extent size just remove the extent
            and return the page address, else split off a chunk of the extent
            and return the address of the removed part, while moving it to a
            different bucket if it changed size classes.

        Freeing:

            Make new extent and insert it into the extent_list while preserving order.
            (this is why free is O(n)) Merge with adjacent extents if addresses match,
            then insert into the appropriate bucket.

        Failure Mode:

            Assuming user code calls the allocator with valid arguments only
            allocation can fail, which happens when we either exhaust all available memory,
            or when we hit the final bucket and do not find any extent suitable for the
            allocation.

        Invariants:

            - No two extents may describe overlapping memory regions.
            - Different buckets may not reference the same extents.
            - Extents may not exist in user-owned memory, they must instead be
            - at the start of the free area they describe.
            - An extent's page_count may not be under 1.
            - An extent must always exist in both the address-ordered extent list
                and in exactly one bucket.
            - There is a finite, statically known number of buckets.
            - A bucket may not reference extents smaller than its size class.
            - Neither the extent list nor buckets may link back to themselves,
                there must be a definite start and end to each linked list.

        Userspace API:

            <n> pALLOC - allocate n pages,
                Returns the address of the first page allocated,
                or -1 if it couldn't find enough memory.

            <n> <addr> pFREE - free n pages at addr
                Does not have a return value, note that n must
                equal the n passed to pALLOC on the call that
                returned addr.

        Asymptotics:

            Allocate - O(1) if the allocation fits into a specialized size class,
                O(n) where n = extent_count if the allocation hits the final bucket.

            Free - O(n) where n = extent_count

        Rationale:

            Many programs, including higher-level allocators, work by making many allocations
            over the course of their runtime and releasing memory either only when
            exiting, or after finishing a major procedure.

            Thus the important performance characteristic of a page allocator is its
            ability to allocate memory, not release it, programs may make many
            allocations in hot loops yet wait until a safe point to free memory.

            Alongside that performance concern it's important to remember that this
            is a basic low level page allocator, when a user is free to call a malloc()
            implementation that handles freeing more efficiently, or simply use a slab allocator,
            it becomes less important to deal with fine-grained allocations or quick freeing because
            fundamentally the use case becomes reserving memory for other systems, not allocating
            individual structs or variables.

            To that end we make the smallest allocation unit be the page, which is defined as 4KB here,
            and use size classes as an index over the free list to make allocations from 1 to 1024 pages
            be O(1).
)

( 1.5GB heap )
512 1024 1024 * * CONSTANT HEAP_BASE

( Some helpers to make the syntax for the extent struct a bit nicer. )
0 CONSTANT extent.page_count
4 CONSTANT extent.prev
8 CONSTANT extent.next
12 CONSTANT extent.prev_bucket
16 CONSTANT extent.next_bucket
CREATE FIELD ALIAS +

( 12 i32 slots so that's 48 bytes of external metadata for the allocator. )
DWORD_T VARIABLE EXTENT_LIST
DWORD_T 11 * VARIABLE BUCKETS

( Index an array with the syntax `idx val_size arr INDEX`
Note that this just computes the address, like lea would in x64, it does not dereference. )
QWORD_T VARIABLE ARR
: INDEX ARR !q * ARR @q + ;
FORGET ARR POP

( Get the smaller of two values, used to clamp values. )
: MIN
    OVER OVER < IF
        SWAP POP ( if a is smaller return a )
    ELSE
        POP ( if b is smaller or equal return b )
    THEN
;

( Get the larger of two values. )
: MAX
    OVER OVER > IF
        SWAP POP
    ELSE
        POP
    THEN
;

( Count leading zeros. )
: LZCNT
    [
        -13 ,b 73 ,b 15 ,b -67 ,b 70 ,b -8 ,b ( lzcnt rax, [r14 - 8] )
        73 ,b -119 ,b 70 ,b -8 ,b ( mov [r14 - 8], rax )
    ]
;

( initialize allocator state. )
: HEAP_INIT

    ( page_count = size of heap in pages )
    393216 HEAP_BASE extent.page_count FIELD !d

    ( Because this is currently the only extent we just zero the link pointers. )
    0 HEAP_BASE extent.prev FIELD !d
    0 HEAP_BASE extent.next FIELD !d
    0 HEAP_BASE extent.prev_bucket FIELD !d
    0 HEAP_BASE extent.next_bucket FIELD !d

    ( Make the extent list point to our first extent. )
    HEAP_BASE EXTENT_LIST !d

    ( Set every bucket pointer but the last one to 0 )
    0 BEGIN
        0 OVER DWORD_T BUCKETS INDEX !d
        1 +
    DUP 10 == UNTIL
    ( And then set the 1024+ bucket to point to our one extent. )
    HEAP_BASE SWAP DWORD_T BUCKETS INDEX !d
;

( Pretty-print an extent. )
: PRINT_EXTENT

    r" -----" DUP PRINT OVER PRINTNUM PRINTLN
    DUP extent.page_count FIELD @d r" page_count " PRINT .
    DUP extent.prev FIELD @d r" prev " PRINT .
    DUP extent.next FIELD @d r" next " PRINT .
    DUP extent.prev_bucket FIELD @d r" prev_bucket " PRINT .
    extent.next_bucket FIELD @d r" next_bucket " PRINT .
    r" ------EXTENT------" PRINTLN
;

( walk the heap and dump metadata, printing out the extent list and every bucket )
: HEAP_MDUMP

    ( Print every extent in address order. )
    EXTENT_LIST @d BEGIN
    DUP WHILE
        DUP PRINT_EXTENT 8 + @d
    REPEAT POP

    ( Print bucket names. )
    0 BEGIN
        r" bucket " PRINT
        DUP PRINTNUM
        r" :" PRINTLN

        DUP DWORD_T BUCKETS INDEX @d
        ( Print bucket contents. )
        BEGIN
        DUP WHILE
            r"     " PRINT
            DUP PRINTNUM
            extent.next_bucket FIELD @d 
        REPEAT POP
        PUTLN

        1 +
    DUP 11 == UNTIL POP
;

( Find the appropriate size class and return its bucket, given an allocation size. )
: GET_BUCKET
    -1 + LZCNT 64 - 10 MIN
;

( Given an extent, find which bucket it is in. Different from GET_BUCKET as this
deals with size classes while GET_BUCKET deals with lower bounds.
Ie. this should return 9 for a 1000-page extent, while GET_BUCKET would return 10. )
: FIND_BUCKET
    LZCNT 63 - 10 MIN
;

( Given a bucket, check if it is empty and if so loop over the buckets until a nonempty one is found.
Returns -1 if it cannot find any nonempty buckets. )
: GET_NONEMPTY_BUCKET
    BEGIN
        DUP DWORD_T BUCKETS INDEX @d IF
            EXIT
        THEN
        1 +
    DUP 11 == UNTIL
    POP -1
;

( Remove extent from its current bucket. )
: BUCKET_UNLINK
    DUP
    DUP extent.prev_bucket FIELD @d IF
        ( extent.prev_bucket.next_bucket = extent.next_bucket )
        DUP extent.prev_bucket FIELD @d extent.next_bucket FIELD
        SWAP extent.next_bucket FIELD @d SWAP !d
    ELSE
        ( bucket = extent.next_bucket )
        DUP FIND_BUCKET DWORD_T BUCKETS INDEX SWAP
        extent.next_bucket FIELD @d SWAP !d
    THEN

    DUP
    DUP extent.next_bucket FIELD @d ~ IF
        ( extent.next_bucket.prev_bucket = extent.prev_bucket )
        DUP extent.next_bucket FIELD @d extent.prev_bucket FIELD
        SWAP extent.prev_bucket FIELD @d SWAP !d
    THEN
    POP
;

( Remove extent from the address-ordered extent list. )
: ELIST_UNLINK
    DUP
    DUP extent.prev FIELD @d IF
        ( extent.prev.next = extent.next )
        DUP extent.prev FIELD @d extent.next FIELD
        SWAP extent.next FIELD @d SWAP !d
    ELSE
        ( extent_list = extent.next )
        extent.next FIELD @d EXTENT_LIST !d
    THEN

    DUP
    DUP extent.next FIELD @d ~ IF
        ( extent.next.prev = extent.prev )
        DUP extent.next FIELD @d extent.prev FIELD
        SWAP extent.prev FIELD @d SWAP !d
    THEN
    POP
;

( Given an extent *which is part of no bucket*, and a bucket, make it part of said bucket. )
: SET_BUCKET
    OVER DWORD_T BUCKETS INDEX @d

    DUP IF
        OVER OVER SWAP 
        extent.next_bucket FIELD !d
        OVER SWAP extent.prev_bucket FIELD !d
    ELSE
        POP
    THEN

    SWAP DWORD_T BUCKETS INDEX !d
;

( Given an extent and bucket, make the extent part of said bucket.
Note that this should be called before actually modifying an extent's page_count,
because it determines what bucket it is currently in based on that. )
: CHANGE_BUCKET
    DUP BUCKET_UNLINK SET_BUCKET
;

( Remove an extent from the address-ordered list as well as its bucket. )
: UNLINK_EXTENT
    DUP BUCKET_UNLINK
    ELIST_UNLINK
;

( Make an extent N pages smaller, removes the extent if N equals page_count.
Returns the extent's new address. Also  )
: SPLIT_EXTENT
    TODO" SPLIT_EXTENT should make an extent smaller, while changing its bucket if necessary.
        And removing it alltogether if the page_count is the same as the number to split from it.
        Finally, it should return the address of the split-off chunk."
;

( Merge an extent with adjacent ones if able, possibly changing start_page and page_count.
Returns the extent's new address. )
: COALESCE_AT_EXTENT
    TODO" COALESCE_AT_EXTENT should merge a freshly-made extent (such as from pFREE) with adjacent
          ones if necessary, and return the new start address of the extent."
;

( Create a new extent and insert into extent list preserving sorted order.
Takes the desired address and page_count, returns nothing. O(n). )
: NEW_EXTENT
    TODO" NEW_EXTENT should make and insert a new extent into the address-ordered extent list,
          note that it does not coalesce. This is our allocator's O(n) operation because it needs
          to maintain sorted order during insertion. It's technically possible to make this O(log n)
          by changing the extent list used by the allocator to be a skip list, but that's out of the
          scope of this implementation."
;

( Allocate n pages from a given bucket by walking it and checking if each extent is large enough.
O(n) where n = the number of extents in the bucket. )
: __SLOW_ALLOC
    TODO" Allocate n pages from a bucket without a guarantee of it working
          or finishing quickly."
;

( Allocate n pages from a given nonempty bucket in constant time. )
: __FAST_ALLOC
    TODO" Allocate n pages from a given nonempty bucket, O(1) and cannot error."
;

( allocate n pages )
: pALLOC
    ( If allocation is large then we try a slow alloc, if it is small we try to find an appropriate bucket. )
    DUP 1024 >= IF
        DUP GET_BUCKET GET_NONEMPTY_BUCKET ( Try to find an appropriate bucket. )
        
        DUP -1 == IF
            ( If no appropriate larger buckets, try 1 below. )
            POP
            DUP GET_BUCKET -1 + __SLOW_ALLOC
        ELSE
            ( If appropriate bucket found, we can guarantee a fast allocation. )
            __FAST_ALLOC
        THEN
    ELSE
        10 __SLOW_ALLOC
    THEN
;

( free n pages )
: pFREE
    TUCK NEW_EXTENT COALESCE_AT_EXTENT POP
;