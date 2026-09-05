( Dependencies: <stdlib> )

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

MACROS

5 CONSTANT TASK_ENTRY_SIZE
65536 CONSTANT ENTRY_COUNT

0 CONSTANT entry.state
1 CONSTANT entry.fd

-1 CONSTANT RUNNABLE
0 CONSTANT INVALID
1 CONSTANT WAITING

ENDMACROS

DWORD_T TMPVAR ENTRY_ARR

: WAKER
    TODO" initialize some state, then enter an infinite loop of calling epoll_wait and yielding."
;

: ASYNC_SPAWN_TASK
    TODO" spawn a task using SPAWN_TASK, then set up its metadata"
;

: ASYNC_START
    0 ['] WAKER LITERAL SPAWN_TASK -1 == IF r" Couldn't start WAKER task." EXIT THEN
    ASYNC_SPAWN_TASK
;

: ASYNCIO_INIT
    TODO" allocate entry array"
;
