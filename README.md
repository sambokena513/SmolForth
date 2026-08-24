# Core Components:

- forthloader.bin - ELF binary, contains code to set up r15, r14, load the image (2GB), and jump to the start of it.

- imgbootstrap.asm - NASM syntax x64, contains source for outer interpreter, and primitives, can be assembled to create an image loadable by forthloader.bin.

- img.bin - 2GiB forth image, loaded by forthloader.bin, if it doesn't exist then assemble imgbootstrap.asm and rename it to img.bin, you might need to do this if you brick it.

- bootstrap.fc - Forth source file with comments and basic macros provided by a preprocessor that can be executed by the outer interpreter after being stripped of comments and having macros expanded.

- bootstrap.f - Executable Forth code file that defines the core language as the bootstrap image only has the outer interpreter and some primitives that are absolutely necessary.

- fctof.py - Python script that functions as a very basic preprocessor.
    

# Project Dir Structure:

- ./Backups - directory to store old images in, naming scheme is img_b[idx].bin

- ./Artefacts - contains the current image, as well as loader

- ./Source - contains all source files


# Design:

## ABI:

- r15 holds the image base address, we could technically just make everything RIP-relative to not need it but the problem with that is that it ironically makes code less relocatable. If absolutely everything in the image is RIP-relative then the image can only move together, whereas keeping compiled calls RIP-relative but data r15-relative allows us to move the dictionary without moving the code, or move the code and only need to update the dictionary.

- r14 holds the next free slot in the data stack, which is 8KB. Every value on the stack is 8 bytes (1 cell), meaning that you can have at most 1024 temporaries on the stack. Note that the stack grows upward, this is so that we can have rsp and r14 grow towards each other which makes implementing coroutines safer.

- We use the regular hardware return stack (rsp) for return addresses, but we make this point into the image rather than using the OS-afforded one, our return stack is 8KB which allows a call depth of 1024. Note that because the rsp and r14 grow towards each other one may temporarily exceed 8KB at the cost of the other needing to be smaller, so you might not actually get stack corruption every time you go past the end.

- The image is 2GiB so that we can always compile word calls as `call rel32` (subroutine-threading), as for why it's not shorter with a possible later call to mmap that's because the image memory also serves as the heap for any programs inside it, meaning that dynamically allocating programs might choose to make their allocations in the image, and if they're storing for example pictures, files, or other data structures they may very well need the 2GiB.
- The image is read into a MAP_PRIVATE | MAP_ANONYMOUS mapping by the loader rather than directly being mmaped with MAP_SHARED so that we get the semantics of the image being a runtime snapshot of the disk image rather than actually being the image on disk, this lets users explicitly save the image when they can verify it does not contain illegal intermediate state, rather than writeback happening automatically and possibly corrupting the disk image on crashes. This also means that the loader can run images even when it only has read permissions, since otherwise it would need to open the file with O_RDWR.

- The ABI treats every register apart from r14 and r15 (which are reserved) as caller-saved, you are encouraged to not use registers for storing intermediate values, use the data stack or only use registers in primitives that call nothing else.
Apart from that, clean up any intermediates on the stack when you're done with them, you shouldn't rely on the stack being emptied when the image is reloaded to make your code work.

- The TIB is 255 bytes, we only call sys_read with a length long enough to fill the TIB. If a word gets cut off we backtrack to the last whitespace, interpret that, and copy the cut-off word back to the start of TIB, then sys_read with the length being 255 - however many characters are already in TIB.

- Whitespaces (such as spaces or newlines) are changed to null bytes by parsing words like WORD.
This allows words such as FIND that look for a null terminator in their string arguments to be given pointers into the TIB.
Note that REFILL or other basic input words don't do this, this means you can define something like ." and have it do custom parsing without every whitespace in the string literal already being corrupted into \0.

- The dictionary entry format is equivalent to the following C struct:

    ```c
        typedef struct Entry { // both pointers are img base-relative
            uint32 link_ptr;
            uint32 code_ptr;
            uint8 flags;
            char[] name;
        } Entry;
    ```
    or in assembly:

    ```
        dd link_ptr
        dd code_ptr
        db flags
        db "example_name", 0
    ```

    Logically it follows from this that our dictionary is a linked list, and words like FIND are O(N).

### Calling Convention

Arguments are passed on the data stack, and return values are pushed to the data stack. Note that we do not use RPN, but instead sequentially pop the top of the stack to get args, this means that the phrase `2 3 - .` will not print `-1`, but rather `1`.
More generally, this means an n-ary word is called like so: `argn ... arg3 arg2 arg1 MY_WORD`.

## Stdlib

The standard library tries to be unopinionated in low level functionality, though the higher-level modules are not held to the same standard. We assume users will freely modify and/or replace the stdlib or its modules with their own, and to that end no part of it is incredibly optimized, it serves mostly to have a usable language, where said users can choose how exactly they want it to work.

### Modules:

- <bootstrap.f> :; This file implements the most basic features of Forth; compilation, variables, control flow, and the ability to load other library modules as well as save the image.

- <stdstring.f> :; String-related utilities, is a dependency of every other standard library module. The reason for this is because it also contains the implementation of comments, which are needed by all non-trivial code.

- <stdassert.f> :; Basic handling for fatal or near-fatal errors. Note that to avoid a dependency on stdio, as IO can fail and stdassert is meant for handling failures, stdassert defines its own minimal PRINTLN that calls sys_exit on failure.

- <stdctx.f> :; Execution contexts and the ability to switch between them, as well as various related utilities.

- <stdexcept.f> :; Exceptions and exception handling. Uses the exception stack from <stdctx.f>.

- <stdio.f> :; Input-output words and syscall wrappers, note that the syscall wrappers take absolute addresses and not image-relative ones, and that the named IO functions throw on errors.

- <stddict.f> :; Dictionary manipulation and listing words, required for code that wants to remove dictionary entries after compilation (to avoid polluting the global scope), but other than that it's mostly useful in the REPL.

- <stdmem.f> :; Dynamic memory allocation in the form of a page allocator API:
    - <n> pALLOC - Allocates n contiguous pages and returns the address of the first one.
    - <n> <addr> pFREE - Frees n pages starting at addr.

## Primitive Word List:

- `GREET` - Prints "Hello from the image!" to the console.
- `@b @w @d @q` - Fetch an 8-, 16-, 32-, or 64-bit value from memory with sign extension, argument is the address in the image to fetch from.
- `!b !w !d !q` - Store a value into memory, arguments are the address and value.
- `FIND` - Takes a string name as an argument and attempts to find a matching dictionary entry, if successful it returns the dictionary entry address, otherwise -1.
- `EXECUTE` - Takes a dictionary entry, resolves its code pointer, and jumps to it.
- `REFILL` - Attempts to fill the terminal input buffer (TIB) by reading from stdin, if it succeeds TIB_LEN is increased by the number of bytes read, and if it gets EOF if redirects stdin to /dev/tty, does not handle errors.
- `WORD` - Returns the address of the next word in the TIB while making it a valid string by delimiting it, note that this address is invalidated upon calls to CLEAR, calls REFILL if it runs out of input, and calls CLEAR if REFILL runs out of space.
- `CLEAR` - Shifts all unparsed data in the TIB back to the start while setting the parser cursor to index 0.
- `EXIT` - Removes one return address from the return stack before returning, effectively skipping its own normal return address, can be used to perform an early return in a compiled word, or in the REPL to exit the interpreter.
- `NUMBER?` - Takes a string and attempts to parse it as a 64-bit signed integer, it returns whether it failed (-1 for failure), and the value of the integer (if it failed then this is set to a placeholder value of -1).
- `POP` - Moves the data stack pointer down by 8 bytes, effectively removing whatever was on the top of it.
- `I64TS` - Takes a pointer to the end of a 21-byte free block and an integer, and converts the integer to a string which it writes into this block, and then returns the string start address.
- `.` - Prints one number to stdout, internally calls I64TS and uses the data stack as the free block.
- `+ - * / ~ & | ^ << >>` - Arithmetic and bitwise operators.
- `< > == <> >= <=` - Numeric comparisons operators.
- `-? +?` - Sign bit checking operators, `-?` returns true if the number is negative while `+?` returns true when it is nonnegative.
- `aINTERPS` - Pushes the address of the interpreter state struct.
- `DUP SWAP OVER` - Stack operators.
- `SYSCALL` - Pops seven values, the first is the syscall number and the remaining 6 are the arguments to the syscall, then performs a Linux syscall and pushes whatever *it* returned in rax to the data stack.
- `BASE` - Pushes the *absolute* 64-bit address of the start of the image, mostly used together with SYSCALL since providing an image-relative address to it would return EFAULT.
- `rSP@ dSP@ rSP! dSP!` - get and set rsp (return stack pointer; rSP) and r14 (data stack pointer; dSP) respectively, misuse can cause stack corruption, but these are necessary to switch execution contexts such as in a coroutine scheduler.
- `ECR32` - Takes a dictionary entry and compiles a call to it at HERE.
- `LITERAL` - Immediate word, Takes a number and compiles the snippet:
    ```
    mov rax, imm64 ; the number
    mov [r14], rax
    add r14, 8
    ```
    at HERE, which will push the number to the stack at runtime.
- `0BRANCH` - Takes a number and compiles a conditional branch using it as the offset:
    ```
    sub r14, 8
    cmp [r14], 0
    je rel32 ; argument
    ```
- `BRANCH` - Takes a number and compiles an unconditional branch using is as the offset:
    ```
    jmp rel32 ; number
    ```
- `ABORT` - Takes a string and prints it to stdout before calling CLEAR, used for REPL errors.
- `INTERPRET` - Calls WORD, NUMBER?, FIND, EXECUTE, ECR32, LITERAL, and ABORT based on the current state and dictionary entry flags; the outer interpreter.
