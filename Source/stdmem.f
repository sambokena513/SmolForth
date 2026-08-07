( Dependencies: bootstrap.f, stdstring.f, stddict.f )

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