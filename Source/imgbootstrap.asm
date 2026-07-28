BITS 64 ; x64
org 0 ; so that the assembler gives us image-relative addresses for labels

%macro SYS_WRITE 2 ; buf, len
mov rax, 1
mov rdi, 1
mov rsi, %1
mov rdx, %2
syscall
%endmacro

%macro SYS_READ 3 ; fd, buf, len
xor rax, rax
mov rdi, %1
mov rsi, %2
mov rdx, %3
syscall
%endmacro

%macro SYS_OPENAT 4 ; dirfd, pathname, flags, mode
mov rax, 257
mov rdi, %1
mov rsi, %2
mov rdx, %3
mov r10, %4
syscall
%endmacro

%macro SYS_DUP2 2 ; oldfd, newfd
mov rax, 33
mov rdi, %1
mov rsi, %2
syscall
%endmacro

%macro SYS_CLOSE 1 ; fd
mov rax, 3
mov rdi, %1
syscall
%endmacro

; pop a value from the data stack
%macro dPOP 1
mov %1, [r14]
sub r14, 8
%endmacro

; push a value to the data stack
%macro dPUSH 1
add r14, 8
mov qword [r14], %1
%endmacro

; "resolve pointer"
%macro resPTR 1
add %1, r15
%endmacro

; "unresolve pointer", used to turn a pointer into an image relative address,
; note that if the pointer represents an address outside the image you'll have problems
%macro unresPTR 1
sub %1, r15
%endmacro

; dictionary entry offsets
%define DE_LINK 0
%define DE_CODE 4
%define DE_FLAGS 8
%define DE_NAME 9

; dictionary entry flags, note that NO_INTERPRET and NO_COMPILE are not recognized by the \
; bootstrap version of the outer interpreter.
%define NO_INTERPRET 0b00001000 ; error on interpretation attempt
%define NO_COMPILE 0b00000100 ; error on compilation attempt
%define HIDDEN 0b00000010 ; FIND should skip this
%define IMMEDIATE 0b00000001 ; outer interpreter should interpret this regardless of STATE

%define TIB_MAX_SIZE 255 ; 255 instead of 256 so that we can store the current size in one byte
%define TIB_MAX_IDX 254

%define O_RDONLY 0
%define O_WRONLY 1
%define O_RDWR 2
%define AT_FDCWD -100

db "FIF" ; magic

; entry point, image executes one word and then exits, for multiple words the user can type INTERPRET
call INTERPRET
ret

; test word that we use to verify image integrity,
; as well as later outer interpreter functionality
GREET:
lea rsi, [rel msg]
SYS_WRITE rsi, msg_size
ret
msg db "Hello from the image!", 0xA
msg_size equ $ - msg
GREET_entry:
dd 0
dd GREET
db 0
db "GREET", 0


; every fetch instruction takes only 1 arg,
; that being the image-relative address to fetch from

; fetch 8 bits
FETCHb:
mov rax, [r14]
movsx rax, byte [r15 + rax]
mov [r14], rax
ret
FETCHb_entry:
dd GREET_entry
dd FETCHb
db 0
db "@b", 0

; fetch 16 bits
FETCHw:
mov rax, [r14]
movsx rax, word [r15 + rax]
mov [r14], rax
ret
FETCHw_entry:
dd FETCHb_entry
dd FETCHw
db 0
db "@w", 0

; fetch 32 bits
FETCHd:
mov rax, [r14]
movsxd rax, dword [r15 + rax]
mov [r14], rax
ret
FETCHd_entry:
dd FETCHw_entry
dd FETCHd
db 0
db "@d", 0

; fetch 64 bits
FETCHq:
mov rax, [r14]
mov rax, [r15 + rax]
mov [r14], rax
ret
FETCHq_entry:
dd FETCHd_entry
dd FETCHq
db 0
db "@q", 0


; store instructions take the address first and then the value

; store 8 bits
STOREb:
dPOP rax
dPOP rdi
mov byte [r15 + rax], dil
ret
STOREb_entry:
dd FETCHq_entry
dd STOREb
db 0
db "!b", 0

; store 16 bits
STOREw:
dPOP rax
dPOP rdi
mov word [r15 + rax], di
ret
STOREw_entry:
dd STOREb_entry
dd STOREw
db 0
db "!w", 0

; store 32 bits
STOREd:
dPOP rax
dPOP rdi
mov dword [r15 + rax], edi
ret
STOREd_entry:
dd STOREw_entry
dd STOREd
db 0
db "!d", 0

; store 64 bits
STOREq:
dPOP rax
dPOP rdi
mov [r15 + rax], rdi
ret
STOREq_entry:
dd STOREd_entry
dd STOREq
db 0
db "!q", 0


; FIND takes the image-relative address of a string pointer,
; and returns the image-relative address of its entry, or -1 for failure
FIND:
dPOP rax ; strptr
resPTR rax
xor rdi, rdi ; index
mov esi, [rel latest_def]
jmp .start

.outer:
mov esi, [rsi] ; next linked list node
test rsi, rsi
jz .fail ; if last node
.start:
resPTR rsi
test byte [rsi + DE_FLAGS], HIDDEN
jnz .outer ; if HIDDEN, skip the word
xor rdi, rdi
.inner:
mov cl, byte [rsi + rdi + DE_NAME] ; cl = dict_word_name[idx]
cmp cl, byte [rax + rdi]
jne .outer

test cl, cl ; if bytes were same, check if null terminator
jz .success ; if yes, success

inc rdi
jmp .inner

.success:
unresPTR rsi ; make it image-relative so it doesn't break user-space
dPUSH rsi
ret
.fail:
dPUSH -1
ret
FIND_entry:
dd STOREq_entry
dd FIND
db 0
db "FIND", 0


; EXECUTE takes the image-relative address of a dictionary entry,
; resolves it, and calls its code field
EXECUTE:
dPOP rax
resPTR rax ; get runtime dict entry address
mov eax, [rax + DE_CODE]
resPTR rax ; get runtime code address
jmp rax ; tail-call
EXECUTE_entry:
dd FIND_entry
dd EXECUTE
db 0
db "EXECUTE", 0


; REFILL calls sys_read to fill the TIB.
; If sys_read fails we simply return without changing the TIB.
; If we reach EOF then we open /dev/tty and change its fd to stdin,
; this is to make startup scripts simpler as you can \
; invoke the loader like `./loader < init.f` and the outer interpreter \
; will consume that file before switching to the terminal.
REFILL:
lea rcx, [rel tib]
mov r8, TIB_MAX_SIZE
movzx r9, byte [rel tib_idx]
add rcx, r9
sub r8, r9
SYS_READ 0, rcx, r8
test rax, rax
jz .eof
jns .success
lea rsi, [rel refill_errmsg]
SYS_WRITE rsi, refill_errmsg_size
ret
.eof: ; if we hit EOF we assume we were reading a disk file and redirect stdin back to the terminal
lea rsi, [rel refill_path]
SYS_OPENAT AT_FDCWD, rsi, O_RDONLY, 0
mov rbx, rax
SYS_DUP2 rbx, 0
SYS_CLOSE rbx
ret
.success:
add al, byte [rel tib_idx] 
mov byte [rel tib_len], al ; tib_len = bytes_read + tib_idx
ret
refill_path db "/dev/tty", 0
refill_errmsg db "sys_read failure in REFILL, you may exit the program with ctrl+c.", 0xd
refill_errmsg_size equ $ - refill_errmsg
REFILL_entry:
dd EXECUTE_entry
dd REFILL
db 0
db "REFILL", 0


; WORD parses the next word in the TIB,
; and returns its image-relative address
WORD_:
; / setup
movzx eax, byte [rel tib_idx]
mov byte [rel scan_start], al ; so we can restore state later in case we need to request more input
; setup /

; / load args
.restart:
lea rsi, [rel tib]
mov dl, ' ' ; space
mov cl, 0xA ; newline
jmp .skip_whitespace_start
; load args /

; / leading whitespace handler
.skip_whitespace:
inc al
mov byte [rel tib_idx], al ; update tib_idx, we need this so we don't return a bad pointer later
mov byte [rel scan_start], al ; the start of the word is not actually the whitespace
.skip_whitespace_start:
cmp al, TIB_MAX_SIZE
je .clear
cmp al, byte [rel tib_len]
je .refill

cmp dl, [rsi + rax]
je .skip_whitespace ; if space, skip
cmp cl, [rsi + rax]
je .skip_whitespace ; if newline, skip
; leading whitespace handler /

; / main loop
.inner:
cmp al, TIB_MAX_SIZE
je .clear
cmp al, byte [rel tib_len]
je .refill

cmp dl, [rsi + rax]
je .end ; if space, end of word
cmp cl, [rsi + rax]
je .end ; if newline, end of word
inc al ; else, increment idx
jmp .inner
; main loop /

; / success path
.end: ; we get here if we found a space or newline
mov rdx, rsi
unresPTR rdx
movzx ecx, byte [rel tib_idx]
add edx, ecx ; do this instead of `add dl, byte [rel tib_idx]` to avoid overflow problems
dPUSH rdx
mov byte [rsi + rax], 0 ; make the address we pushed be a valid pointer
inc al ; so that the next call to WORD won't start at the null terminator
mov byte [rel tib_idx], al ; update tib_idx
ret
; success path /

; / run out of input
.refill:
mov byte [rel tib_idx], al
call REFILL
mov al, byte [rel scan_start]
mov [rel tib_idx], al
jmp .restart
; run out of input /

; / input exceeds TIB size
.clear:
mov al, byte [rel scan_start]
mov byte [rel tib_idx], al
call CLEAR
jmp WORD_
; input exceeds TIB size /
WORD__entry:
dd REFILL_entry
dd WORD_
db 0
db "WORD", 0


; CLEAR copies everything from the current tib_idx up until tib_len \
; to the start of TIB and sets tib_idx to 0
CLEAR:
movzx eax, byte [rel tib_idx]
movzx edi, byte [rel tib_len]
lea rsi, [rel tib]
xor rcx, rcx

.loop:
cmp rax, rdi
je .exit

mov bl, [rsi + rax]
mov byte [rsi + rcx], bl

inc rax
inc rcx
jmp .loop

.exit:
mov byte [rel tib_idx], 0
mov byte [rel tib_len], cl
ret
CLEAR_entry:
dd WORD__entry
dd CLEAR
db 0
db "CLEAR", 0


; EXIT returns to the Forth loader, assuming that it's called from the original INTERPRET call in the entry point.
; Otherwise if you're in a nested INTERPRET call it will exit that one, and if you just call it from somewhere else \
; then it will probably corrupt the return stack and segfault. Don't use outside of the REPL!
EXIT:
add rsp, 8 ; skip the address pushed by `call EXECUTE`
ret ; return to the entry point just after `jmp EXECUTE` which returns a final time to the loader
EXIT_entry:
dd CLEAR_entry
dd EXIT
db NO_COMPILE | IMMEDIATE
db "EXIT", 0


; NUMBER? takes in a string pointer (image-relative),
; and attempts to parse it as a decimal integer.
; It pushes two values to the data stack; whether it was successful (-1 or 0), and the parsed value (-1 if err).
NUMBERq:
dPOP rax
resPTR rax
xor rbx, rbx ; parsed val, initialize to 0
mov rcx, -1 ; sign, initialize to -1 for positive
xor rdx, rdx ; digit, clear upper bits so we can use 8-bit instructions later

; / check empty
cmp byte [rax], 0
je .fail
; check empty /

; / negative?
cmp byte [rax], '-'
jne .loop
mov rcx, 1
inc rax ; advance
; negative? /

; / check empty
cmp byte [rax], 0
je .fail
; check empty /

; / main loop
.loop:
cmp byte [rax], 0
je .success

cmp byte [rax], '0'
jl .fail
cmp byte [rax], '9'
jg .fail

mov dl, byte [rax]
sub dl, '0'

imul rbx, 10
sub rbx, rdx

inc rax
jmp .loop
; main loop /

.fail:
dPUSH -1
dPUSH -1
ret
.success:
imul rbx, rcx ; multiply by sign
dPUSH rbx
dPUSH 0
ret
NUMBERq_entry:
dd EXIT_entry
dd NUMBERq
db 0
db "NUMBER?", 0


; discard one value from the data stack
POP:
sub r14, 8
ret
POP_entry:
dd NUMBERq_entry
dd POP
db 0
db "POP", 0


; I64TS takes in an address pointing to the end of a 21-byte free block and a 64 bit integer,
; and converts the integer to a string which it ensures ends at addr.
; It then returns the address the string starts at.
I64TS:
dPOP rsi ; pointer
dPOP rax ; i64
mov rbx, 1 ; is rax negative?, initialized as true
mov rcx, 10 ; divisor

; add the delimiter first
xor rdi, rdi
mov byte [rsi], dl
dec rsi

test rax, rax
js .loop
xor rbx, rbx
neg rax
.loop: ; operate on negative numbers so we automatically handle INT64_MIN
cqo
idiv rcx

neg rdx
add dl, '0'
mov byte [rsi], dl
dec rsi

test rax, rax
jnz .loop

test rbx, rbx
jz .end
mov byte [rsi], '-'
dec rsi

.end:
inc rsi
dPUSH rsi
ret
I64TS_entry:
dd POP_entry
dd I64TS
db 0
db "I64TS", 0


; . (dot) takes in a 64-bit integer argument and prints it in decimal format
; Note that dot uses the data stack as temporary storage for \
; its string (this is to avoid having one syscall for each character),
; meaning that if the stack is already very close to the 32KB limit this might hit a guard page \
; and trigger SIGSEGV.
DOT:
lea rsi, [r14 + 48]
; ^^^ reserve space for I64TS,
; normally we'd need an extra 8 bytes but because of `dPOP rax` \
; r14 moves down by 8 letting us get away with this
dPOP rax ; pop val arg
dPUSH rsi ; save rsi for later
dPUSH rax ; push val arg
dPUSH rsi ; push addr arg

call I64TS ; convert to string

dPOP rsi ; start addr
dPOP rdx ; end addr

mov byte [rdx], 0xA ; replace null delimiter with newline
sub rdx, rsi ; rdx now has the length
inc rdx ; add 1 since we want to print up to end_addr, not to just before it

mov rax, 1
mov rdi, 1
syscall ; sys_write
ret
DOT_entry:
dd I64TS_entry
dd DOT
db 0
db ".", 0


; all arithmetic primitives pop 2 numbers from the stack, perform an operation, and push the result
; (note that the calling convention is `arg2 arg1 op` meaning that to perform 2 - 3 you would write `3 2 -`)

PLUS:
dPOP rax
dPOP rbx
add rax, rbx
dPUSH rax
ret
PLUS_entry:
dd DOT_entry
dd PLUS
db 0
db "+", 0


MINUS:
dPOP rax
dPOP rbx
sub rax, rbx
dPUSH rax
ret
MINUS_entry:
dd PLUS_entry
dd MINUS
db 0
db "-", 0


MUL_:
dPOP rax
dPOP rbx
imul rax, rbx
dPUSH rax
ret
MUL__entry:
dd MINUS_entry
dd MUL_
db 0
db "*", 0


; note that this performs integer division, our Forth doesn't natively support floats
DIV_:
dPOP rax
dPOP rbx
cqo
idiv rbx
dPUSH rax
ret
DIV__entry:
dd MUL__entry
dd DIV_
db 0
db "/", 0


NOT_:
dPOP rax
not rax
dPUSH rax
ret
NOT__entry:
dd DIV__entry
dd NOT_
db 0
db "~", 0


AND_:
dPOP rax
dPOP rbx
and rax, rbx
dPUSH rax
ret
AND__entry:
dd NOT__entry
dd AND_
db 0
db "&", 0


OR_:
dPOP rax
dPOP rbx
or rax, rbx
dPUSH rax
ret
OR__entry:
dd AND__entry
dd OR_
db 0
db "|", 0


XOR_:
dPOP rax
dPOP rbx
xor rax, rbx
dPUSH rax
ret
XOR__entry:
dd OR__entry
dd XOR_
db 0
db "^", 0


; aINTERPS pushes the image-relative address of the start of the outer interpreter var struct,
; which is the same address as that of the interpreter variable latest_def
aINTERPS:
lea rax, [rel latest_def]
unresPTR rax
dPUSH rax
ret
aINTERPS_entry:
dd XOR__entry
dd aINTERPS
db 0
db "aINTERPS", 0


LIT:
mov rax, [rsp] ; return address
mov rax, [rax] ; i64
dPUSH rax
add [rsp], 8 ; advance past it
ret ; return, skipping past the integer
LIT_entry:
dd aINTERPS_entry
dd LIT
db NO_INTERPRET
db "LIT", 0


_0BR:
dPOP rax
test rax, rax
jnz .not_zero
mov rax, [rsp]
mov eax, [rax] ; load rel32
add [rsp], eax
add [rsp], 4 ; so it's relative to where the offset is and not to the instruction itself
ret
.not_zero:
add [rsp], 4 ; skip rel32
ret
_0BR_entry:
dd LIT_entry
dd _0BR
db NO_INTERPRET
db "0BR", 0


DUP:
mov rax, [r14]
dPUSH rax
ret
DUP_entry:
dd _0BR_entry
dd DUP
db 0
db "DUP", 0


SWAP:
mov rax, [r14]
mov rbx, [r14 - 8]
mov [r14], rbx
mov [r14 - 8], rax
ret
SWAP_entry:
dd DUP_entry
dd SWAP
db 0
db "SWAP", 0


OVER:
mov rax, [r14 - 8]
dPUSH rax
ret
OVER_entry:
dd SWAP_entry
dd OVER
db 0
db "OVER", 0


; Basic syscall wrapper, takes 6 args and pushes the return value
SYSCALL_:
dPOP rax
dPOP rdi
dPOP rsi
dPOP rdx
dPOP r10
dPOP r8
dPOP r9
syscall
dPUSH rax
ret
SYSCALL__entry:
dd OVER_entry
dd SYSCALL_
db 0
db "SYSCALL", 0


BASE:
dPUSH r15
ret
BASE_entry:
dd SYSCALL__entry
dd BASE
db 0
db "BASE", 0


RSPTR:
dPUSH rsp
ret
RSPTR_entry:
dd BASE_entry
dd RSPTR
db 0
db "RSPTR", 0


DSPTR:
dPUSH r14
ret
DSPTR_entry:
dd RSPTR_entry
dd DSPTR
db 0
db "DSPTR", 0


; ECR32 emits a `call rel32` instruction at HERE, and moves HERE past it.
; Its argument is the image-relative address of the *dict entry* \
; of the word we're compiling a call to, such as produced by FIND.
ECR32:
dPOP rax
mov rax, [r15 + rax + DE_CODE] ; rax now has the code pointer

mov ebx, [rel here]
mov byte [r15 + rbx], 0xe8 ; put call opcode at HERE

; offset = ADDR - (HERE + 5)
sub rax, rbx
sub rax, 5

mov [r15 + rbx + 1], eax ; store the rel32 offset

add dword [rel here], 5
ret
ECR32_entry:
dd DSPTR_entry
dd ECR32
db 0
db "ECR32", 0


; LITERAL is an immediate word that pops a number from the data stack,
; and compiles it.
LITERAL:
dPUSH LIT_entry
call ECR32 ; compile call to LIT
dPOP rbx
mov eax, [rel here]
mov [r15 + rax], rbx
add dword [rel here], 8 ; i64
ret
LITERAL_entry:
dd ECR32_entry
dd LITERAL
db IMMEDIATE
db "LITERAL", 0


; ABORT prints an error message and empties the TIB,
; it takes the image-relative address of the string to print.
ABORT:
dPOP rsi
resPTR rsi
xor rdx, rdx

.loop:
mov al, [rsi + rdx]
test al, al
jz .end_loop
inc rdx
jmp .loop
.end_loop:

mov rax, 1
mov rdi, 1
syscall

mov byte [rel tib_len], 0
mov byte [rel tib_idx], 0
ret
ABORT_entry:
dd LITERAL_entry
dd ABORT
db 0
db "ABORT", 0

; helper macros to make INTERPRET easier to write

; var offsets
%define I_O_STATE 8
%define I_O_TIBIDX 14
%define I_O_TIBLEN 15

; push the address of the interpreter state struct + offset
%macro I_SOFFSET 1
call aINTERPS
call LIT
dq %1
call PLUS
%endmacro

; push the value of the interpreter's `state` variable
%macro I_STATE 0
I_SOFFSET I_O_STATE
call FETCHb
%endmacro

; push a constant
%macro I_CONST 1
call LIT
dq %1
%endmacro

; branch to a label if zero, makes writing calls to 0BR \
; closer to the syntax of `jz label`
%macro I_0BRANCH 1
call _0BR
dd %1 - ($ + 4)
%endmacro

; unconditional branch
%macro I_BRANCH 1
I_CONST 0
I_0BRANCH %1
%endmacro

; jump back to the start of INTERPRET
%macro I_AGAIN 0
I_BRANCH INTERPRET
%endmacro

; handle an error with a message and jump back to the start of INTERPRET
%macro I_ERR 1
I_CONST %1
call ABORT
I_AGAIN
%endmacro

; push the value of a dict entry's flag
; note that this does not shift, 
; so if the flag is on the third bit for example \
; and is set you get 4, not 1
%macro I_FLAG 1
I_CONST DE_FLAGS
call PLUS
call FETCHb
I_CONST %1
call AND_
%endmacro


; INTERPRET is the bootstrap outer interpreter.
INTERPRET:
call WORD_
call DUP
call NUMBERq
I_0BRANCH .number
call POP ; pop NUMBER?'s placeholder value
call FIND

; handle error in FIND
call DUP
I_CONST 1
call PLUS
I_0BRANCH .errnf ; if find returns -1 we error

I_STATE
I_0BRANCH .attempt_interp_word

; attempt_comp_word
call DUP ; - FIND
I_FLAG IMMEDIATE
I_0BRANCH .attempt_comp_word
I_BRANCH .attempt_interp_word ; interpret if IMMEDIATE

.attempt_comp_word:
call DUP ; - FIND
I_FLAG NO_COMPILE
I_0BRANCH .comp_word
I_BRANCH .errnc

.comp_word:
call ECR32
I_AGAIN
.attempt_interp_word:
call DUP ; - FIND
I_FLAG NO_INTERPRET
I_0BRANCH .interp_word
I_BRANCH .errni
.interp_word:
call EXECUTE
I_AGAIN
.number:
call SWAP
call POP ; WORD -
I_STATE
I_0BRANCH .interp_number
; comp_number
call LITERAL
.interp_number:
I_AGAIN
.errnf:
call POP ; FIND -
I_ERR i_errnf
.errni:
call POP ; FIND -
I_ERR i_errni
.errnc:
call POP ; FIND -
I_ERR i_errnc
ret
i_errnf db "error: FIND returned -1", 0xA, 0
i_errni db "error: encountered NO_INTERPRET with STATE 0", 0xA, 0
i_errnc db "error: encountered NO_COMPILE with STATE 1", 0xA, 0
INTERPRET_entry:
dd ABORT_entry
dd INTERPRET
db 0
db "INTERPRET", 0


; interpreter variables

latest_def dd INTERPRET_entry ; image-relative address, resPTR it before dereferencing!
here dd HERE_START ; also image-relative
state db 0 ; 0 = interpreting, 1 = compiling
scan_start db 0 ; used to restore WORD parse state, copy of tib_idx
compile_start dd 0 ; will be used later for colon definitions to patch code pointers, currently does nothing
tib_idx db 0 ; current point in tib we're at, if add tib to this and resPTR it you get a valid string pointer
tib_len db 0 ; current amount of bytes in tib
tib times TIB_MAX_SIZE db 0 ; no delimiter on this string, be very careful about bounds checks!

; HERE_START is at the end of the bootstrap image \
; so that new words start compiling past the \
; outer interpreter and primitive words rather than corrupting it.
HERE_START: