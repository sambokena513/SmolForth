( Dependencies: bootstrap.f, stdstring.f, stdio.f, stdassert.f )

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

            Search the extent list for the extent right before the address being
            freed, if its end address matches the start of the freed address,
            extend it, then if its end address suddenly matches the start of the
            next extent, merge repeatedly until it does not match, then if it 
            changed size class, search for it in its bucket, remove it, and insert
            it into its new bucket.
            If the addresses do not match, just create a new extent and insert it
            into the appropriate bucket.

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

: INDEXb * + @b ;
: INDEXw * + @w ;
: INDEXd * + @d ;
: INDEXq * + @q ;

( initialize allocator state. )
: HEAP_INIT
    TODO"
        HEAP_INIT should initialize the allocator by clearing the buckets,
        and making an extent with a length of 393216 pages, as well as setting
        the extent list to point to it.
        "
;

( walk the heap and dump metadata, printing out the extent list and every bucket )
: HEAP_MDUMP
    TODO" HEAP_MDUMP should print out the current allocator metadata."
;

( allocate n pages )
: pALLOC
    TODO" pALLOC should allocate n pages and return the address of the first."
;

( free n pages )
: pFREE 
    TODO" pFREE should take an address and count and free that many pages."
;