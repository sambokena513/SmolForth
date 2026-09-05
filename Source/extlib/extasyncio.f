( <extasyncio.f> :; This module implements a basic WAKER task that whenever it gets a chance to execute, calls epoll_wait and attempts to wake suspended tasks waiting on IO. 
For tasks to properly work with the waker they need to be spawned using the library-provided ASYNC_SPAWN_TASK wrapper over SPAWN_TASK, and use the ASYNC_* IO functions with nonblocking
fds for any operation that normally could block. )

(
    Architecture:

    The core idea behind this library is that asynchronous IO operations register or rearm fds with epoll_ctl before performing the nonblocking operation, and if it returned EAGAIN,
    then they call SUSPEND. Then a privileged WAKER task that owns the epfd calls epoll_wait every time execution reaches it, with a timeout of 0 if there are other runnable tasks,
    and a timeout of -1 if there are not. If there are no other runnable tasks *and* no suspended tasks, it exits.

    We accomplish these things by giving each possible task an index in an array with 65536 elements.
    Each entry is 40 bits, the first 8 bits are the task's state:

        -1 = Runnable
        0 = Invalid/No task
        1 = Waiting on fd
        Other values are reserved for future extensions.

    And the 32-bit field is an fd the task is waiting on, its value is irrelevant if the first field is -1 or 0.

    To ensure these fields get properly updated, we provide a wrapper over SPAWN_TASK called ASYNC_SPAWN_TASK that sets the new task's onsuspend and onkill fields
    as well as initializing its entry to be -1 for runnable.

    The onsuspend field is set to a function that takes an fd and events as args through the control-flow stack, and registers or rearms it with epoll_ctl, as well
    as setting its entry to be marked as waiting on that fd.

    The onkill field is set to a nullary function that clears the task's metadata entry and calls epoll_ctl to remove the task's fd [ if there is one ] from the
    interest list.
)

( so we get the exception value macros )
INCLUDE ./stdlib/stdexcept.f

( exit if macros are already defined [ you can do FORGET EXTASYNCIO_M POP to include them again ] )
POPBUFXT IFDEF EXTASYNCIO_M MACROS CREATE EXTASYNCIO_M

5 CONSTANT ENTRY_SIZE
65536 CONSTANT ENTRY_COUNT

0 CONSTANT entry.state ( byte_t )
1 CONSTANT entry.fd ( dword_t )

-1 CONSTANT RUNNABLE
0 CONSTANT INVALID
1 CONSTANT WAITING

ENDMACROS

( normal include guard )
POPBUFXT IFDEF EXTASYNCIO_F CREATE EXTASYNCIO_F

DWORD_T VARIABLE ENTRY_ARR

( A task that should run for the whole lifetime of a program using the async system, WAKER attempts
to wake suspended tasks if their fds are ready everytime execution reaches it, and blocks the whole
thread if there are no other runnable tasks to make sure we don't max out the CPU core Forth is running
on if there's nothing to be done. )
: WAKER
    TODO" initialize some state, then enter an infinite loop of calling epoll_wait and yielding."
;

( Spawn a task that behaves asynchronously on IO. )
: ASYNC_SPAWN_TASK
    TODO" spawn a task using SPAWN_TASK, then set up its metadata"
;

( Start the async system. Intended to be used in an INIT function after CORE_INIT for programs that use asyncio. )
: ASYNC_START
    0 ['] WAKER LITERAL SPAWN_TASK -1 == IF r" Couldn't start WAKER task." EXIT THEN
    ASYNC_SPAWN_TASK
;

: ASYNCIO_INIT
    [ 4096 ENTRY_COUNT ENTRY_SIZE * / ] LITERAL
    pALLOC DUP -1 == IF
        POP EXC_NOMEM THROW
    THEN
;
