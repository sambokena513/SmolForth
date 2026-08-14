( Dependencies: bootstrap.f, stdstring.f, stdio.f, stdassert.f, stddict.f )

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
                    i32 start_page;
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
            - An extent's page_count may not be under 1, and its start_page may not be under 0.
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

( 12 i32 slots so that's 48 bytes of external metadata for the allocator. )
DWORD_T VARIABLE EXTENT_LIST
DWORD_T 11 * VARIABLE BUCKETS

QWORD_T VARIABLE ARR
: INDEX
    [ ARR ] LITERAL !q
    * [ ARR ] LITERAL @q +
;
FORGET ARR POP

( initialize allocator state. )
: HEAP_INIT

    ( start_page = 0, page_count = size of heap in pages )
    0 0 DWORD_T HEAP_BASE INDEX !d
    393216 1 DWORD_T HEAP_BASE INDEX !d

    ( Because this is currently the only extent we just zero the link pointers. )
    0 2 DWORD_T HEAP_BASE INDEX !d
    0 3 DWORD_T HEAP_BASE INDEX !d
    0 4 DWORD_T HEAP_BASE INDEX !d
    0 5 DWORD_T HEAP_BASE INDEX !d

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

    r" -----" DUP PRINT OVER [ WNB 21 + ] LITERAL I64TS PRINT PRINTLN
    DUP @d r" start_page " PRINT .
    DUP 4 + @d r" page_count " PRINT .
    DUP 8 + @d r" prev " PRINT .
    DUP 12 + @d r" next " PRINT .
    DUP 16 + @d r" prev_bucket " PRINT .
    12 + @d r" next_bucket " PRINT .
    r" -----EXTENT-----" PRINTLN
;

( walk the heap and dump metadata, printing out the extent list and every bucket )
: HEAP_MDUMP

    ( Print every extent in address order. )
    EXTENT_LIST @d BEGIN
        DUP PRINT_EXTENT 12 + @d
    DUP 0 == UNTIL POP

    TODO" print out the buckets"
;

( allocate n pages )
: pALLOC
    TODO" pALLOC should allocate n pages and return the address of the first."
;

( free n pages )
: pFREE 
    TODO" pFREE should take an address and count and free that many pages."
;