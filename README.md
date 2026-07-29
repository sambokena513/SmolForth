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

    - ./Source - contains the loader source and the imgbootstrap source


# Design:

    r15 holds the image base address, we could technically just make everything RIP-relative to not need it but the problem with that is that it ironically makes code less relocatable. If absolutely everything in the image is RIP-relative then the image can only move together, whereas keeping compiled calls RIP-relative but data r15-relative allows us to move the dictionary without moving the code, or move the code and only need to update the dictionary.

    r14 holds the next free slot in the data stack, which is 8KB. Every value on the stack is 8 bytes (1 cell), meaning that you can have at most 1024 temporaries on the stack. Note that the stack grows upward, this is so that we can have rsp and r14 grow towards each other which makes implementing coroutines safer.

    We use the regular hardware return stack (rsp) for return addresses, but we make this point into the image rather than using the OS-afforded one, our return stack is 8KB which allows a call depth of 1024. Note that because the rsp and r14 grow towards each other one may temporarily exceed 8KB at the cost of the other needing to be smaller, so you might not actually get stack corruption every time you go past the end.

    The image is 2GiB so that we can always compile word calls as `call rel32` (subroutine-threading), as for why it's not shorter with a possible later call to ftruncate that's because the image memory also serves as the heap for any programs inside it, meaning that dynamically allocating programs might choose to make their allocations in the image, and if they're storing for example pictures, files, or other data structures they may very well need the 2GiB.
    MAP_PRIVATE is used rather than MAP_SHARED so that users can verify their image does not contain illegal intermediate state, and save it purposefully with words like SAVE-IMG and BACKUP-IMG rather than writeback happening automatically.

    The ABI treats every register apart from r14 and r15 (which are reserved) as caller-saved, you are encouraged to not use registers for storing intermediate values, use the data stack or only use registers in primitives that call nothing else.
    Apart from that, clean up any intermediates on the stack when you're done with them, you shouldn't rely on the stack being emptied when the image is reloaded to make your code work.

    The TIB is 255 bytes, we only call sys_read with a length long enough to fill the TIB. If a word gets cut off we backtrack to the last whitespace, interpret that, and copy the cut-off word back to the start of TIB, then sys_read with the length being 255 - however many characters are already in TIB.

    Whitespaces (such as spaces or newlines) are changed to null bytes by parsing words like WORD.
    This allows words such as FIND that look for a null terminator in their string arguments to be given pointers into the TIB.
    Note that REFILL or other basic input words don't do this, this means you can define something like ." and have it do custom parsing without every whitespace in the string literal already being corrupted into \0.

    The dictionary entry format is equivalent to the following C struct:

        typedef struct Entry { // both pointers are img base-relative
            uint32 link_ptr;
            uint32 code_ptr;
            uint8 flags;
            char[] name;
        } Entry;

    or in assembly:

        dd link_ptr
        dd code_ptr
        db flags
        db "example_name", 0

    Logically it follows from this that our dictionary is a linked list, and words like FIND are O(N).