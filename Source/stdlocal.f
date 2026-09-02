( Dependencies: bootstrap.f, stdstring.f, stdassert.f, stdctx.f, stdexcept.f, stdio.f, stddict.f )

( <stdlocal.f> :: Define words with access to local variables that don't inhibit recursion, and arguments, which are locals that automatically bind. )


( Allocate space for n locals on the local stack. )
: ENTER_FRAME
    TODO" allocate n locals"
;

( Release space for n locals on the local stack. )
: LEAVE_FRAME
    TODO" free n locals"
;

( Internal implementations of REF and VAL that take string pointers. )
: __REF
    TODO" compile `lSP <offset> +`"
;

: __VAL
    TODO" compile `lSP <offset> + @q`"
;

( Parse the next word; which should be the name of a local, and compile `lSP <offset> +` )
: REF
    WORD __REF
; IMMEDIATE

( Parse the next word; which should be the name of a local, and compile `lSP <offset> + @q`. )
: VAL
    WORD __VAL
; IMMEDIATE

( Start a function definition, locals and args may only be used within functions, not colon definitions. )
: FUNCTION
    TODO" like colon but we first compile a snippet to perform ENTER_FRAME and LEAVE_FRAME"
;

( End a function definition. )
CREATE ENDFUNC ALIAS ; IMMEDIATE

( Parse and create a local. )
: local:
    TODO" Make a CONSTANT as a macro"
; IMMEDIATE

( Parse and create an arg. )
: arg:
    TODO" Make a CONSTANT as a macro, and also compile __REF !q for it."
; IMMEDIATE

( Parse and create locals until '}', effectively the same as calling local: separately for each word.
Note that this must be called *after* FUNCTION, it is invalid outside of a function definition, including inside
colon definitions. )
: {
    TODO" Call local: until '}'"
; IMMEDIATE

( Parse and create args until '\', same as calling arg: separately for each word.
Note that this should be called only *immediately after* FUNCTION because it depends on the code body of the word 
being empty. )
: #
    TODO" Call arg: until '\'"
; IMMEDIATE
