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

%macro SYS_FTRUNCATE 2 ; fd, length
  mov rax, 77
  mov rdi, %1
  mov rsi, %2
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

%define AT_FDCWD -100

_start:
  ; this file should map a 32KiB stack into memory, map a 2GiB image into memory,
  ; put the image base address in r15, set up the TOS pointer in r14,
  ; and then call the image base address

  SYS_MMAP 32 * KB, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0

  test rax, rax
  jns .success_stack_mmap

  SYS_WRITE errmmapmsg, errmmapmsg_size

  jmp .exit

  .success_stack_mmap:
  mov r14, rax ; put the TOS pointer into the reserved register
  mov [stck_ptr], rax ; so we can unmap it later

  SYS_OPENAT AT_FDCWD, filepath, O_RDWR, 0

  test rax, rax
  jns .success_img_openat

  SYS_WRITE erropenatmsg, erropenatmsg_size ; print err message
  jmp .stack_munmap ; clean up

  .success_img_openat:
  mov [img_fd], rax

  SYS_FTRUNCATE [img_fd], 2 * GB

  test rax, rax
  jns .success_img_ftruncate

  SYS_WRITE warnftruncatemsg, warnftruncatemsg_size

  .success_img_ftruncate:
  SYS_MMAP 2 * GB, PROT_READ | PROT_WRITE | PROT_EXEC, MAP_PRIVATE, [img_fd], 0

  test rax, rax
  jns .success_img_mmap

  SYS_WRITE errmmapmsg, errmmapmsg_size ; mmap error
  jmp .close_img ; clean up fd

  .success_img_mmap:
  mov r15, rax

  call r15 ; run Forth

  SYS_MUNMAP r15, 2 * GB

  .close_img:
  SYS_CLOSE [img_fd]

  .stack_munmap:
  SYS_MUNMAP [stck_ptr], 32 * KB

  .exit:
  ; sys_exit
  mov rax, 60
  xor rdi, rdi
  syscall

section .data
errmmapmsg db "exiting due to mmap failing", 0xA
errmmapmsg_size equ $ - errmmapmsg
filepath db "img.bin", 0
erropenatmsg db "exiting due to openat failing", 0xA
erropenatmsg_size equ $ - erropenatmsg
warnftruncatemsg db "warning: could not extend image to 2 GiB", 0xA
warnftruncatemsg_size equ $ - warnftruncatemsg
section .bss
img_fd resq 1 ; to hold the file descriptor of img
stck_ptr resq 1 ; holds the data stack pointer so we can unmap it later