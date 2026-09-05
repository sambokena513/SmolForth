section .text
global _start

%macro SYS_WRITE 2 ; buf, len
  mov rax, 1
  mov rdi, 1
  lea rsi, %1
  mov rdx, %2
  syscall
%endmacro

%macro SYS_MMAP 5 ; size, prot, flags, fd, offset
  mov rax, 9
  xor rdi, rdi ; no address hint since we operate in user-space and can't guarantee it
  mov rsi, %1
  mov rdx, %2
  mov r10, %3
  mov r8, %4
  mov r9, %5
  syscall
%endmacro

%macro SYS_MUNMAP 2 ; addr, len
  mov rax, 11
  mov rdi, %1
  mov rsi, %2
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

%macro SYS_CLOSE 1 ; fd
  mov rax, 3
  mov rdi, %1
  syscall
%endmacro

%macro SYS_FSTAT 2 ; fd, statbuf
  mov rax, 5
  mov rdi, %1
  lea rsi, %2
  syscall
%endmacro

%define PROT_NONE 0x0
%define PROT_READ 0x1
%define PROT_WRITE 0x2
%define PROT_EXEC 0x4

%define MAP_SHARED 0x1
%define MAP_PRIVATE 0x2
%define MAP_FIXED 0x10
%define MAP_ANONYMOUS 0x20

%define KB 1024
%define MB KB * 1024
%define GB MB * 1024

%define O_RDONLY 0
%define O_WRONLY 1
%define O_RDWR 2
%define O_NONBLOCK 2048
%define STDIN 0
%define F_GETFL 3
%define F_SETFL 4

%define AT_FDCWD -100

_start:
  ; This is the forth image loader. It's purpose is to map and read an fif executable into memory, and call its entry point.

  ; before we do anything else, make stdin nonblocking since forth images depend on that

  mov rsi, F_GETFL
  mov rdi, STDIN
  mov rax, 72
  syscall
  test rax, rax
  jns .success_fcntl_read

  SYS_WRITE errfcntlmsg, errfcntlmsg_size
  jmp .exit

  .success_fcntl_read:
  or rax, O_NONBLOCK
  mov rdx, rax
  mov rsi, F_SETFL
  mov rax, 72
  syscall
  test rax, rax
  jns .success_fcntl

  SYS_WRITE errfcntlmsg, errfcntlmsg_size
  jmp .exit

  .success_fcntl:
  ; get image path from command line args
  mov rax, [rsp] ; argc
  cmp rax, 2 ; need at least one arg
  jl .no_arg
  mov rax, [rsp + 16]
  mov [rel filepath_ptr], rax
  jmp .begin
  .no_arg:
  lea rax, [rel filename_fallback]
  mov [rel filepath_ptr], rax
  .begin:

  SYS_OPENAT AT_FDCWD, [rel filepath_ptr], O_RDONLY, 0

  test rax, rax
  jns .success_img_openat

  SYS_WRITE erropenatmsg, erropenatmsg_size ; print err message
  jmp .exit

  .success_img_openat:
  mov [rel img_fd], rax

  SYS_MMAP 2 * GB, PROT_READ | PROT_WRITE | PROT_EXEC, MAP_PRIVATE | MAP_ANONYMOUS, 0, 0

  test rax, rax
  jns .success_img_mmap

  SYS_WRITE errmmapmsg, errmmapmsg_size ; mmap error
  jmp .close_img ; clean up fd

  .success_img_mmap:
  mov r15, rax

  SYS_FSTAT [rel img_fd], [rel statbuf]
  test rax, rax
  jns .success_img_fstat

  SYS_WRITE errfstatmsg, errfstatmsg_size
  jmp .close_img

  .success_img_fstat:
  call .img_read
  test rax, rax
  jns .success_img_read

  SYS_WRITE errreadmsg, errreadmsg_size
  jmp .close_img

  .success_img_read:

  mov r14d, [r15 + 8] ; dstck_start
  add r14, r15

  mov esp, [r15 + 12] ; rstck_start
  add rsp, r15

  mov rax, r15
  add rax, 20 ; skip header
  call rax ; run Forth

  SYS_MUNMAP r15, 2 * GB

  .close_img:
  SYS_CLOSE [rel img_fd]

  .exit:
  ; sys_exit
  mov rax, 60
  xor rdi, rdi
  syscall

  .img_read:
  mov r13, r15
  mov r12, [rel statbuf + 48]

  .img_single_read:
  mov rdx, r12
  mov rsi, r13
  mov rdi, [rel img_fd]
  xor rax, rax
  syscall
  test rax, rax
  jz .img_read_end
  jns .success_single_read
  ret
  .success_single_read:
  add r13, rax
  sub r12, rax
  jmp .img_single_read
  .img_read_end:
  ret

section .data
errmmapmsg db "exiting due to mmap failing", 0xA
errmmapmsg_size equ $ - errmmapmsg
filename_fallback db "img.bin", 0
erropenatmsg db "exiting due to openat failing", 0xA
erropenatmsg_size equ $ - erropenatmsg
errfstatmsg db "exiting due to fstat failing", 0xA
errfstatmsg_size equ $ - errfstatmsg
errreadmsg db "exiting due to read failing", 0xA
errreadmsg_size equ $ - errreadmsg
errfcntlmsg db "exiting due to fcntl failing", 0xA
errfcntlmsg_size equ $ - errfcntlmsg
section .bss
filepath_ptr resq 1 ; filepath of the image
img_fd resq 1 ; to hold the file descriptor of img
statbuf resb 144 ; note, offset 48 here is the file size
