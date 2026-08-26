( Dependencies: bootstrap.f, stdstring.f, stdassert.f, stdctx.f, stdexcept.f, stdio.f, stddict.f, stdmem.f )

( <stdslab.f> :; Basic slab allocator, gets backing memory from the pALLOC/pFREE API, configurable size and object size. )

(
    C-style reference for the slab allocator struct layout:

        typedef struct Slab {
            // i32 for this and obj_size since our whole heap is only 1.5GB,
            // so it's impossible to have an object size or count unrepresentable by a 32-bit integer.
            i32 max_obj_count
            i32 obj_size // bytes
            i32 mem_size // pages
            i32 mem_start // ptr
            i32 free_stack_size // pages
            i32 free_stack_base // ptr
            i32 free_stack // ptr
        } Slab;
)

MACROS

0 CONSTANT slab.max_obj_count
4 CONSTANT slab.obj_size
8 CONSTANT slab.mem_size
12 CONSTANT slab.mem_start
16 CONSTANT slab.free_stack_size
20 CONSTANT slab.free_stack_base
24 CONSTANT slab.free_stack

ENDMACROS

( temporary variable to make the code a bit cleaner )
DWORD_T TMPVAR SLAB ( TODO: debug WORD, removing a whitespace here seems to freeze the compiler??? )

( Print a slab's fields. )
: PRINT_SLAB
    r" max_obj_count: " PRINT DUP slab.max_obj_count FIELD @d .
    r" obj_size: " PRINT DUP slab.obj_size FIELD @d .
    r" mem_size: " PRINT DUP slab.mem_size FIELD @d .
    r" mem_start: " PRINT DUP slab.mem_start FIELD @d .
    r" free_stack_size: " PRINT DUP slab.free_stack_size FIELD @d .
    r" free_stack_base: " PRINT DUP slab.free_stack_base FIELD @d .
    r" free_stack: " PRINT slab.free_stack FIELD @d .
;

( r | slab -D- addr :; Allocate one block of memory from a given slab. )
: SLAB_ALLOC
    SLAB !d

    ( return -1 if there is no free memory )
    SLAB @d slab.free_stack_base FIELD @d
    SLAB @d slab.free_stack FIELD @d
    <= IF
        -1 EXIT
    THEN

    DWORD_T SLAB @d slab.free_stack FIELD @d -
    SLAB @d slab.free_stack FIELD !d

    SLAB @d slab.free_stack FIELD @d @d
;

( r | addr slab -D- :; Free one block of memory from a given slab. )
: SLAB_FREE
    SLAB !d

    SLAB @d slab.free_stack FIELD @d !d

    DWORD_T SLAB @d slab.free_stack FIELD @d +
    SLAB @d slab.free_stack FIELD !d
;

( r | obj_size obj_count -D- slab | -1 :; Allocate memory for and initialize a slab given the size of objects in it in bytes,
and the count of how many objects it should store as a maximum. Note that if you only need a few objects, and they're small enough,
it might be better to manually initialize a slab, as the smallest amount of memory MAKE_SLAB will reserve is 3 pages;
1 for the slab struct itself [really quite overkill but that's the smallest one pALLOC can give], at least 1 for the free stack,
and at least 1 for the backing memory. )
: MAKE_SLAB
    ( allocate slab struct )
    1 pALLOC

    DUP -1 == IF
        EXIT ( return -1 on failure )
    THEN

    SLAB !d
    SLAB @d slab.max_obj_count FIELD !d
    SLAB @d slab.obj_size FIELD !d

    ( allocate backing memory )
    SLAB @d slab.max_obj_count FIELD @d
    SLAB @d slab.obj_size FIELD @d
    * 12 SWAP >> 1 MAX
    DUP SLAB @d slab.mem_size FIELD !d

    pALLOC DUP -1 == IF
        1 SLAB @d pFREE EXIT
    THEN

    SLAB @d slab.mem_start FIELD !d

    ( allocate free stack )
    SLAB @d slab.max_obj_count FIELD @d
    DWORD_T * 12 SWAP >> 1 MAX
    DUP SLAB @d slab.free_stack_size FIELD !d

    pALLOC DUP -1 == IF
        SLAB @d slab.mem_size FIELD @d
        SLAB @d slab.mem_start FIELD @d
        pFREE

        1 SLAB @d pFREE
        EXIT
    THEN

    DUP SLAB @d slab.free_stack_base FIELD !d
    SLAB @d slab.free_stack FIELD !d

    ( initialize free stack )
    SLAB @d slab.mem_start FIELD @d DUP
    SLAB @d slab.max_obj_count FIELD @d
    SLAB @d slab.obj_size FIELD @d
    * +
    BEGIN
    2DUP > WHILE
        OVER SLAB @d SLAB_FREE SWAP
        SLAB @d slab.obj_size FIELD @d + SWAP
    REPEAT 2POP

    SLAB @d
;

( r | slab -D- :; Free all memory associated with a slab allocator, this invalidates all pointers into it. )
: DESTROY_SLAB
    SLAB !d

    SLAB @d slab.mem_size FIELD @d
    SLAB @d slab.mem_start FIELD @d 
    pFREE

    SLAB @d slab.free_stack_size FIELD @d
    SLAB @d slab.free_stack_base FIELD @d
    pFREE

    1 SLAB @d pFREE
;

( get rid of tmp var )
FORGET SLAB POP
