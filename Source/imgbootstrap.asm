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

%define DE_LINK 0
%define DE_CODE 4
%define DE_FLAGS 8
%define DE_NAME 9
%define NO_INTERPRET 0b00001000 ; outer interpreter should error when it attempts to interpret this
%define NO_INTERPRET_S 3
%define NO_COMPILE 0b00000100 ; outer interpreter should error when it attempts to compile this
%define NO_COMPILE_S 2
%define HIDDEN 0b00000010 ; FIND should skip this
%define HIDDEN_S 1
%define IMMEDIATE 0b00000001 ; outer interpreter should attempt to interpret this instead of
%define IMMEDIATE_S 0

%define TIB_MAX_SIZE 255 ; 255 instead of 256 so that we can store the current size in one byte
%define TIB_MAX_IDX 254

; entry point, image executes one word and then exits, for multiple words the user can type INTERPRET
call WORD_
call FIND
jmp EXECUTE
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
movzx eax, byte [r15 + rax]
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
movzx eax, word [r15 + rax]
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
mov eax, [r15 + rax]
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


; REFILL calls sys_write to fill the TIB
REFILL:
lea rcx, [rel tib]
mov r8, TIB_MAX_SIZE
movzx r9, byte [rel tib_idx]
add rcx, r9
sub r8, r9
SYS_READ 0, rcx, r8
test rax, rax
jns .success
ret ; if sys_read failed then tib_len does not change
.success:
add al, byte [rel tib_idx] 
mov byte [rel tib_len], al ; tib_len = bytes_read + tib_idx
ret
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


; aINTERPS pushes the image-relative address of the start of the outer interpreter var struct,
; which is the same address as that of the interpreter variable latest_def
aINTERPS:
lea rax, [rel here]
unresPTR rax
dPUSH rax
ret
aINTERPS_entry:
dd DIV__entry
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
dPOP rax
dPUSH rax
dPUSH rax
ret
DUP_entry:
dd _0BR_entry
dd DUP
db 0
db "DUP", 0


SWAP:
dPOP rax
dPOP rbx
dPUSH rax
dPUSH rbx
ret
SWAP_entry:
dd DUP_entry
dd SWAP
db 0
db "SWAP", 0


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
dd SWAP_entry
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


; INTERPRET is the main outer interpreter loop
; note that this is the only word in the bootstrap image that follows the format compiled words will take
INTERPRET:
call WORD_
call DUP
call NUMBERq
call _0BR
dd .number - ($ + 4)
call POP
call FIND
call EXECUTE
call LIT
dq 0
call _0BR
dd INTERPRET - ($ + 4)
.number:
call SWAP
call POP
call LIT
dq 0
call _0BR
dd INTERPRET - ($ + 4)
ret
INTERPRET_entry:
dd BASE_entry
dd INTERPRET
db 0
db "INTERPRET", 0


; interpreter variables

latest_def dd INTERPRET_entry ; image-relative address, resPTR it before dereferencing!
here dd HERE_START ; also image-relative
state db 0 ; 0 = interpreting, 1 = compiling
scan_start db 0 ; used to restore WORD parse state, copy of tib_idx
tib_idx db 0 ; current point in tib we're at, if add tib to this and resPTR it you get a valid string pointer
tib_len db 0 ; current amount of bytes in tib
tib times TIB_MAX_SIZE db 0 ; no delimiter on this string, be very careful about bounds checks!

; HERE_START is at the end of the bootstrap image \
; so that new words start compiling past the \
; outer interpreter and primitive words rather than corrupting it.
HERE_START: