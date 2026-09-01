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
sub r14, 8
mov %1, [r14]
%endmacro

; push a value to the data stack
%macro dPUSH 1
mov qword [r14], %1
add r14, 8
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

; dictionary entry flags
%define HIDDEN 0b00000010 ; FIND should skip this
%define IMMEDIATE 0b00000001 ; outer interpreter should interpret this regardless of STATE

%define TIB_MAX_SIZE 255 ; 255 instead of 256 so that we can store the current size in one byte
%define TIB_MAX_IDX 254
%define TIB_IDX_OFFSET TIB_MAX_SIZE
%define TIB_LEN_OFFSET TIB_IDX_OFFSET + 1
%define TIB_FD_OFFSET TIB_LEN_OFFSET + 1
%define TIB_EOF_OFFSET TIB_FD_OFFSET + 4
%define TIB_PARENT_OFFSET TIB_EOF_OFFSET + 1

%define O_RDONLY 0
%define O_WRONLY 1
%define O_RDWR 2
%define O_NONBLOCK 2048
%define AT_FDCWD -100
%define EAGAIN 11
%define POLLIN 1
%define STDIN 0

; header: 20 bytes
db "FIF", 0 ; magic
dd latest_def
dd dstck_start
dd rstck_start
dd HERE_START

; entry point
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
mov rax, [r14 - 8]
movsx rax, byte [r15 + rax]
mov [r14 - 8], rax
ret
FETCHb_entry:
dd GREET_entry
dd FETCHb
db 0
db "@b", 0

; fetch 16 bits
FETCHw:
mov rax, [r14 - 8]
movsx rax, word [r15 + rax]
mov [r14 - 8], rax
ret
FETCHw_entry:
dd FETCHb_entry
dd FETCHw
db 0
db "@w", 0

; fetch 32 bits
FETCHd:
mov rax, [r14 - 8]
movsxd rax, dword [r15 + rax]
mov [r14 - 8], rax
ret
FETCHd_entry:
dd FETCHw_entry
dd FETCHd
db 0
db "@d", 0

; fetch 64 bits
FETCHq:
mov rax, [r14 - 8]
mov rax, [r15 + rax]
mov [r14 - 8], rax
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


; GETTERM opens /dev/tty and performs bookkeeping to make words like REFILL seamlessly start reading from it.
; If it fails, it calls sys_exit (unrecoverable since this is fundamentally a repl-driven language.).
; Note that all input buffers are nonblocking, this is necessary in order to implement asynchronous INTERPRET in the standard library.
GETTERM:
mov r8d, dword [rel tib]
resPTR r8
mov byte [r8 + TIB_EOF_OFFSET], 0
mov edi, dword [r8 + TIB_FD_OFFSET]
mov rax, 3
syscall

lea rsi, [rel term_path]
SYS_OPENAT AT_FDCWD, rsi, O_RDONLY | O_NONBLOCK, 0
test rax, rax
jns .success
mov rdi, 74 ; EX_IOERR
mov rax, 60
syscall
.success:
mov rbx, rax
SYS_DUP2 rbx, 0
mov dword [r8 + TIB_FD_OFFSET], ebx
ret
term_path db "/dev/tty", 0
GETTERM_entry:
dd EXECUTE_entry
dd GETTERM
db 0
db "GETTERM", 0


; READTIB calls sys_read to fill the TIB and returns the number of bytes read.
; On EAGAIN it returns -EAGAIN, and on other errors it exits with EX_IOERR.
; On EOF it fills in one extra newline, and on a second EOF it attempts to either pop \
; the current buffer, or if this is the top buffer, replace it with a terminal using GETTERM.
READTIB:
mov esi, dword [rel tib]
resPTR rsi

; append TIB_MAX_SIZE - TIB_LEN bytes
movzx edx, byte [rsi + TIB_LEN_OFFSET]
neg rdx
add rdx, TIB_MAX_SIZE

; start appending after tib_len
movzx ecx, byte [rsi + TIB_LEN_OFFSET]
add rsi, rcx

mov rdi, 0
mov rax, 0
syscall
mov esi, dword [rel tib]
resPTR rsi

test rax, rax
jz .eof
jns .success
cmp rax, -EAGAIN
je .eagain
mov rdi, 74
mov rax, 60
syscall
.eagain:
dPUSH -EAGAIN
ret
.eof:
cmp byte [rsi + TIB_LEN_OFFSET], TIB_MAX_SIZE
je .full

cmp byte [rsi + TIB_EOF_OFFSET], 0
jne .second_eof
mov byte [rsi + TIB_EOF_OFFSET], 1
movzx ecx, byte [rsi + TIB_LEN_OFFSET]
mov byte [rsi + rcx], 10
inc byte [rsi + TIB_LEN_OFFSET]
dPUSH 1 ; 1 instead of 0 because we "read" (injected) a newline
ret
.second_eof:
cmp dword [rsi + TIB_PARENT_OFFSET], 0
jne .popbuf
call GETTERM
.full:
dPUSH 0
ret
.popbuf:
mov eax, dword [rel popbufxt]
dPUSH rax
call EXECUTE
dPUSH 0
ret
.success:
add byte [rsi + TIB_LEN_OFFSET], al
dPUSH rax
ret
READTIB_entry:
dd GETTERM_entry
dd READTIB
db 0
db "READTIB", 0


; REFILL is a wrapper around READTIB that makes it behave synchronously
REFILL:
call READTIB
dPOP rax
cmp rax, -EAGAIN
je .retry
ret
.retry:
mov rdx, -1 ; block until fd becomes ready
mov rsi, 1
lea rdi, [rel .poll_struct]
mov rax, 7
syscall
jmp REFILL
.poll_struct:
dd STDIN ; fd
dw POLLIN ; events
dw 0 ; revents
REFILL_entry:
dd READTIB_entry
dd REFILL
db 0
db "REFILL", 0


; WORD_START advances the parsing cursor until the first non-whitespace character,
; and then returns the index of that character. Note that like WORD, WORD_START may
; invalidate pointers into the current TIB if it ends up calling CLEAR.
WORD_START:
mov esi, [rel tib]
resPTR rsi

movzx edi, byte [rsi + TIB_IDX_OFFSET]
movzx edx, byte [rsi + TIB_LEN_OFFSET]

mov bl, 32
mov cl, 10

.loop:
cmp dil, dl
je .out_of_input

mov al, byte [rsi + rdi]
cmp al, bl
je .skip
cmp al, cl
jne .end
.skip:
inc dil
jmp .loop

.end:
mov byte [rsi + TIB_IDX_OFFSET], dil
dPUSH rdi
ret

.out_of_input:
mov byte [rsi + TIB_IDX_OFFSET], dil
cmp dl, TIB_MAX_SIZE
jne .refill
call CLEAR

.refill:
call REFILL
jmp WORD_START
WORD_START_entry:
dd REFILL_entry
dd WORD_START
db 0
db "WORD_START", 0

; WORD parses the next word in the TIB,
; and returns its image-relative address
; TODO: fix this, it misparses on some inputs
WORD_:
call WORD_START
.restart:

mov esi, [rel tib]
resPTR rsi

movzx edi, byte [rsi + TIB_IDX_OFFSET]
movzx edx, byte [rsi + TIB_LEN_OFFSET]

mov bl, 32
mov cl, 10

.loop:
cmp dil, dl
je .out_of_input

mov al, byte [rsi + rdi]
; increment here instead of after \
; the comparisons since otherwise \
; we'd need an extra inc in .end
inc dil
cmp al, bl
je .end
cmp al, cl
je .end
jmp .loop

.end:
mov byte [rsi + TIB_IDX_OFFSET], dil
; replace the whitespace with nul since we use C-style strings
mov byte [rsi + rdi - 1], 0 ; -1 because we increment before comparing in the loop
unresPTR rsi
add qword [r14 - 8], rsi ; add the start of the tib to the index before returning so we get a pointer
ret

.out_of_input:
; save idx to mem so refill can see it
mov byte [rsi + TIB_IDX_OFFSET], dil
cmp dl, TIB_MAX_SIZE
jne .refill

; .clear
mov rdi, qword [r14 - 8] ; make sure that clear starts copying from the word's start
mov qword [r14 - 8], 0 ; idx after this will be 0
mov byte [rsi + TIB_IDX_OFFSET], dil
call CLEAR

.refill:
call REFILL
jmp .restart
WORD__entry:
dd WORD_START_entry
dd WORD_
db 0
db "WORD", 0


; CLEAR copies everything from the current tib_idx up until tib_len \
; to the start of TIB and sets tib_idx to 0
CLEAR:
mov esi, dword [rel tib]
resPTR rsi
movzx eax, byte [rsi + TIB_IDX_OFFSET]
movzx edi, byte [rsi + TIB_LEN_OFFSET]
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
mov byte [rsi + TIB_IDX_OFFSET], 0
mov byte [rsi + TIB_LEN_OFFSET], cl
ret
CLEAR_entry:
dd WORD__entry
dd CLEAR
db 0
db "CLEAR", 0


; EXIT can be used to exit the REPL or to perform an early return in a word.
EXIT:
add rsp, 8 ; skip the address pushed by the call to EXIT itself
ret ; return
EXIT_entry:
dd CLEAR_entry
dd EXIT
db 0
db "EXIT", 0


; NUMBER? takes in a string pointer (image-relative),
; and attempts to parse it as a decimal integer.
; It pushes two values to the data stack; whether it errored (-1 or 0), and the parsed value (-1 if err).
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
resPTR rsi
dPOP rax ; i64
mov rbx, 1 ; is rax negative?, initialized as true
mov rcx, 10 ; divisor

; add the delimiter first
xor rdx, rdx
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
unresPTR rsi
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
unresPTR rsi
dPUSH rsi ; push addr arg

call I64TS ; convert to string

dPOP rsi ; start addr
resPTR rsi
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
mov rax, [r14 - 8]
mov rbx, [r14 - 16]
add rax, rbx
sub r14, 8
mov [r14 - 8], rax
ret
PLUS_entry:
dd DOT_entry
dd PLUS
db 0
db "+", 0


MINUS:
mov rax, [r14 - 8]
mov rbx, [r14 - 16]
sub rax, rbx
sub r14, 8
mov [r14 - 8], rax
ret
MINUS_entry:
dd PLUS_entry
dd MINUS
db 0
db "-", 0


MUL_:
mov rax, [r14 - 8]
mov rbx, [r14 - 16]
imul rax, rbx
sub r14, 8
mov [r14 - 8], rax
ret
MUL__entry:
dd MINUS_entry
dd MUL_
db 0
db "*", 0


; note that this performs integer division, our Forth doesn't natively support floats
DIV_:
mov rax, [r14 - 8]
mov rbx, [r14 - 16]
cqo
idiv rbx
sub r14, 8
mov [r14 - 8], rax
ret
DIV__entry:
dd MUL__entry
dd DIV_
db 0
db "/", 0


NOT_:
mov rax, [r14 - 8]
not rax
mov [r14 - 8], rax
ret
NOT__entry:
dd DIV__entry
dd NOT_
db 0
db "~", 0


AND_:
mov rax, [r14 - 8]
mov rbx, [r14 - 16]
and rax, rbx
sub r14, 8
mov [r14 - 8], rax
ret
AND__entry:
dd NOT__entry
dd AND_
db 0
db "&", 0


OR_:
mov rax, [r14 - 8]
mov rbx, [r14 - 16]
or rax, rbx
sub r14, 8
mov [r14 - 8], rax
ret
OR__entry:
dd AND__entry
dd OR_
db 0
db "|", 0


XOR_:
mov rax, [r14 - 8]
mov rbx, [r14 - 16]
xor rax, rbx
sub r14, 8
mov [r14 - 8], rax
ret
XOR__entry:
dd OR__entry
dd XOR_
db 0
db "^", 0


SHL_:
mov rax, [r14 - 8]
mov rcx, [r14 - 16]
shl rax, cl
sub r14, 8
mov [r14 - 8], rax
ret
SHL__entry:
dd XOR__entry
dd SHL_
db 0
db "<<", 0


SHR_:
mov rax, [r14 - 8]
mov rcx, [r14 - 16]
shr rax, cl
sub r14, 8
mov [r14 - 8], rax
ret
SHR__entry:
dd SHL__entry
dd SHR_
db 0
db ">>", 0


SMALLER:
mov rax, [r14 - 8]
mov rbx, [r14 - 16]
xor rcx, rcx
cmp rax, rbx
setl cl
neg rcx
sub r14, 8
mov [r14 - 8], rcx
ret
SMALLER_entry:
dd SHR__entry
dd SMALLER
db 0
db "<", 0


GREATER:
mov rax, [r14 - 8]
mov rbx, [r14 - 16]
xor rcx, rcx
cmp rax, rbx
setg cl
neg rcx
sub r14, 8
mov [r14 - 8], rcx
ret
GREATER_entry:
dd SMALLER_entry
dd GREATER
db 0
db ">", 0


EQUAL:
mov rax, [r14 - 8]
mov rbx, [r14 - 16]
xor rcx, rcx
cmp rax, rbx
sete cl
neg rcx
sub r14, 8
mov [r14 - 8], rcx
ret
EQUAL_entry:
dd GREATER_entry
dd EQUAL
db 0
db "==", 0


INEQUAL:
mov rax, [r14 - 8]
mov rbx, [r14 - 16]
xor rcx, rcx
cmp rax, rbx
setne cl
neg rcx
sub r14, 8
mov [r14 - 8], rcx
ret
INEQUAL_entry:
dd EQUAL_entry
dd INEQUAL
db 0
db "<>", 0


GREATEREQUAL:
mov rax, [r14 - 8]
mov rbx, [r14 - 16]
xor rcx, rcx
cmp rax, rbx
setge cl
neg rcx
sub r14, 8
mov [r14 - 8], rcx
ret
GREATEREQUAL_entry:
dd INEQUAL_entry
dd GREATEREQUAL
db 0
db ">=", 0


LOWEREQUAL:
mov rax, [r14 - 8]
mov rbx, [r14 - 16]
xor rcx, rcx
cmp rax, rbx
setle cl
neg rcx
sub r14, 8
mov [r14 - 8], rcx
ret
LOWEREQUAL_entry:
dd GREATEREQUAL_entry
dd LOWEREQUAL
db 0
db "<=", 0


SIGN:
xor rcx, rcx
cmp qword [r14 - 8], 0
sets cl
neg rcx
mov [r14 - 8], rcx
ret
SIGN_entry:
dd LOWEREQUAL_entry
dd SIGN
db 0
db "-?", 0


NOTSIGN:
xor rcx, rcx
cmp qword [r14 - 8], 0
setns cl
neg rcx
mov [r14 - 8], rcx
ret
NOTSIGN_entry:
dd SIGN_entry
dd NOTSIGN
db 0
db "+?", 0


; aINTERPS pushes the image-relative address of the start of the outer interpreter var struct,
; which is the same address as that of the interpreter variable latest_def
aINTERPS:
lea rax, [rel latest_def]
unresPTR rax
dPUSH rax
ret
aINTERPS_entry:
dd NOTSIGN_entry
dd aINTERPS
db 0
db "aINTERPS", 0


DUP:
mov rax, [r14 - 8]
dPUSH rax
ret
DUP_entry:
dd aINTERPS_entry
dd DUP
db 0
db "DUP", 0


SWAP:
mov rax, [r14 - 8]
mov rbx, [r14 - 16]
mov [r14 - 8], rbx
mov [r14 - 16], rax
ret
SWAP_entry:
dd DUP_entry
dd SWAP
db 0
db "SWAP", 0


OVER:
mov rax, [r14 - 16]
dPUSH rax
ret
OVER_entry:
dd SWAP_entry
dd OVER
db 0
db "OVER", 0


ROT:
; c b a
mov rax, [r14 - 8] ; a
mov rbx, [r14 - 16] ; b
mov rdx, [r14 - 24] ; c

; b a c
mov [r14 - 8], rdx ; a -> c
mov [r14 - 16], rax ; b -> a
mov [r14 - 24], rbx ; c -> b
ret
ROT_entry:
dd OVER_entry
dd ROT
db 0
db "ROT", 0


mROT:
; c b a
mov rax, [r14 - 8] ; a
mov rbx, [r14 - 16] ; b
mov rdx, [r14 - 24] ; c

; a c b
mov [r14 - 8], rbx ; a -> b
mov [r14 - 16], rdx ; b -> c
mov [r14 - 24], rax ; c -> a
ret
mROT_entry:
dd ROT_entry
dd mROT
db 0
db "-ROT", 0


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
dd mROT_entry
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


; The following words manipulate the data and return stack pointers,
; don't call these unless you know what you're doing, they're mainly intended for \
; implementing coroutines, as for those there needs to be a way to save and restore \
; the data and return stack pointers of each task.

; rSP@ pushes the current return stack pointer to the data stack
RSP_:
dPUSH rsp
ret
RSP__entry:
dd BASE_entry
dd RSP_
db 0
db "rSP@", 0


; dSP@ pushes the current data stack pointer to the data stack,
; (which paradoxically means its result is already outdated)
DSP_:
dPUSH r14
ret
DSP__entry:
dd RSP__entry
dd DSP_
db 0
db "dSP@", 0


; rSP! pops a value from the data stack, and makes that the return stack pointer
_RSP:
dPOP rsp
ret
_RSP_entry:
dd DSP__entry
dd _RSP
db 0
db "rSP!", 0


; dSP! pops a value from the data stack, and makes that the data stack pointer
_DSP:
dPOP r14
ret
_DSP_entry:
dd _RSP_entry
dd _DSP
db 0
db "dSP!", 0


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
dd _DSP_entry
dd ECR32
db 0
db "ECR32", 0


; LITERAL is an immediate word that pops a number from the data stack,
; and compiles it.
LITERAL:
dPOP rbx
mov eax, [rel here]

; mov rax, imm64
mov byte [r15 + rax], 0x48 ; REX.W (64 bit operand size)
mov byte [r15 + rax + 1], 0xb8 ; mov r64, imm64 opcode for rax
mov qword [r15 + rax + 2], rbx ; imm64

; mov [r14], rax
mov byte [r15 + rax + 10], 0x49 ; REX.W + REX.B
mov byte [r15 + rax + 11], 0x89 ; mov r/m64, r64
mov byte [r15 + rax + 12], 0x06 ; ModRM: source - rax, dest - r14, no displacement

; add r14, 8
mov byte [r15 + rax + 13], 0x49
mov byte [r15 + rax + 14], 0x83 ; add r/m64, r64
mov byte [r15 + rax + 15], 0xc6 ; ModRM: reg operand, add, r14
mov byte [r15 + rax + 16], 0x08 ; immediate value 8

add dword [rel here], 17 ; advance HERE past the literal
ret
LITERAL_entry:
dd ECR32_entry
dd LITERAL
db IMMEDIATE
db "LITERAL", 0

_0BRANCH:
dPOP rbx
mov eax, [rel here]

; sub r14, 8
mov byte [r15 + rax], 0x49
mov byte [r15 + rax + 1], 0x83
mov byte [r15 + rax + 2], 0xee
mov byte [r15 + rax + 3], 0x08

; cmp [r14], 0
mov byte [r15 + rax + 4], 0x49
mov byte [r15 + rax + 5], 0x83
mov byte [r15 + rax + 6], 0x3e
mov byte [r15 + rax + 7], 0x00

; je rel32
mov byte [r15 + rax + 8], 0x0f
mov byte [r15 + rax + 9], 0x84
mov dword [r15 + rax + 10], ebx

add dword [rel here], 14
ret
_0BRANCH_entry:
dd LITERAL_entry
dd _0BRANCH
db IMMEDIATE
db "0BRANCH", 0

BRANCH:
dPOP rbx
mov eax, [rel here]

; jmp rel32
mov byte [r15 + rax], 0xe9
mov dword [r15 + rax + 1], ebx

add dword [rel here], 5
ret
BRANCH_entry:
dd _0BRANCH_entry
dd BRANCH
db IMMEDIATE
db "BRANCH", 0

; ABORT prints an error message, and aborts the current outer interpreter \
; operation by clearing the TIB and setting stdin to /dev/tty to avoid continuing to read \
; commands from a file after an error.
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
cmp rax, rdx ; for parity with stdlib's PANIC we have the same behaviour of EX_IOERR on partial write or failure
je .success
mov rdi, 74
mov rax, 60
syscall
.success:

mov esi, [rel tib]
resPTR rsi
mov byte [rsi + TIB_IDX_OFFSET], 0
mov byte [rsi + TIB_LEN_OFFSET], 0

call GETTERM ; replace current buffer with terminal
ret
ABORT_entry:
dd BRANCH_entry
dd ABORT
db 0
db "ABORT", 0

; helper macros to make INTERPRET easier to write

; var offsets
%define I_O_STATE 8

; push a constant, don't change this, user code depends on it being 17 bytes
%macro I_CONST 1
db 0x48, 0xb8
dq %1
db 0x49, 0x89, 0x06
db 0x49, 0x83, 0xc6, 0x08
%endmacro

; push the address of the interpreter state struct + offset
%macro I_SOFFSET 1
call aINTERPS
I_CONST %1
call PLUS
%endmacro

; push the value of the interpreter's `state` variable
%macro I_STATE 0
I_SOFFSET I_O_STATE
call FETCHb
%endmacro

; branch to a label if zero
%macro I_0BRANCH 1
db 0x49, 0x83, 0xee, 0x08
db 0x49, 0x83, 0x3e, 0x00
db 0x0f, 0x84
dd %1 - ($ + 4)
%endmacro

; unconditional branch
%macro I_BRANCH 1
db 0xe9
dd %1 - ($ + 4)
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
I_0BRANCH .interp_word

; attempt_comp_word
call DUP ; - FIND
I_FLAG IMMEDIATE
I_0BRANCH .comp_word
.interp_word: ; interpret if IMMEDIATE
call EXECUTE
I_AGAIN
.comp_word:
call ECR32
I_AGAIN
.number:
call SWAP
call POP ; WORD -
I_STATE
I_0BRANCH INTERPRET
; comp_number
call LITERAL
I_AGAIN
.errnf:
call POP ; FIND -
I_ERR i_errnf
ret
i_errnf db "error: FIND returned -1", 0xA, 0
INTERPRET_entry:
dd ABORT_entry
dd INTERPRET
db 0
db "INTERPRET", 0


; interpreter variables

latest_def dd INTERPRET_entry ; image-relative address, resPTR it before dereferencing!
here dd HERE_START ; also image-relative
state db 0 ; 0 = interpreting, -1 = compiling
compile_start dd 0 ; used by colon and semicolon to patch code pointers
tib dd initial_tib ; address of current input buffer, historically named TIB despite it not necessarily being a terminal

; popbufxt is the xt of the stdlib-provided function for exiting an input buffer and cleaning up relevant resources
; it starts as -1000 to ensure that EXECUTE on it before being set by the stdlib will segfault
popbufxt dd -1000

; we statically allocate the first buffer here in the image, other ones are dynamically allocated by the stdlib
initial_tib times TIB_MAX_SIZE db 0

tib_idx db 0 ; what point the parser is at inside the buffer
tib_len db 0 ; how much has valid data
dd 0 ; fd, 0 for the initial tib since that one already started as stdin
db 0 ; eof? 0 normally, set to 1 after a read returns EOF
dd 0 ; parent buf, 0 for the initial buffer

dstck_start times 2048 dq 0 ; start point for data stack, reserve 16KB
rstck_start: ; start point for return stack, grows downward into the same 16KB

; HERE_START is at the end of the bootstrap image \
; so that new words start compiling past the \
; outer interpreter and primitive words rather than corrupting it.
HERE_START:
