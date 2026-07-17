BITS 64 ; x64
org 0 ; so that the assembler gives us image-relative addresses for labels

%macro SYS_WRITE 2 ; buf, len
mov rax, 1
mov rdi, 1
lea rsi, %1
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
%define TIB_MAX_SIZE 255
%define TIB_MAX_IDX 254

; user input test, we prompt for input once and try to execute the word
; if the user types "GREET", they should see the greeting message,
; otherwise it'll probably segfault or smth
call WORD_
call FIND
jmp EXECUTE
ret

; test word that we use to verify image integrity,
; as well as later outer interpreter functionality
GREET:
SYS_WRITE [rel msg], msg_size
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
resPTR rsi ; rsi now points to the latest entry
jmp .inner

.outer:
mov esi, [rsi] ; next linked list node
test rsi, rsi ; check if last node
jz .fail ; if last, fail
resPTR rsi ; else, resolve pointer
xor rdi, rdi ; reset index
.inner:
mov cl, byte [rsi + rdi + DE_NAME] ; cl = dict_word_name[idx]
cmp cl, byte [rax + rdi]
jne .outer ; if a byte was different

test cl, cl ; if bytes were same, check if null terminator
jz .success ; if yes, success

inc rdi ; else, increment and go to next iteration
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


; HERE pushes the value of the interpreter variable HERE
HERE:
mov eax, [rel here]
dPUSH rax
ret
HERE_entry:
dd EXECUTE_entry
dd HERE
db 0
db "HERE", 0

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
dd HERE_entry
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


; INTERPRET is the main outer interpreter loop
INTERPRET:
.loop:
call WORD_
call FIND
call EXECUTE
jmp .loop
INTERPRET_entry:
dd CLEAR_entry
dd INTERPRET
db 0
db "INTERPRET", 0

; interpreter variables

latest_def dd INTERPRET_entry ; image-relative address, resPTR it before dereferencing!
here dd HERE_START ; also image-relative
state db 0 ; 0 = interpreting, 1 = compiling
scan_start db 0 ; used to restore WORD parse state, copy of tib_idx
tib_idx db 0 ; current point in tib we're at, if add tib to this and resPTR it you get a valid string pointer
tib_len db 0 ; current amount of bytes in tib, REFILL puts the return value sys_read
tib times TIB_MAX_SIZE db 0 ; no delimiter on this string, be very careful about bounds checks!

; HERE_START is at the end of the bootstrap image \
; so that new words start compiling past the \
; outer interpreter and primitive words rather than corrupting it.
HERE_START: