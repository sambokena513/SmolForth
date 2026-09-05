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

( since these are stdlib modules we already have their functions,
reincluding them just serves to give us their macros too )
INCLUDE ./stdlib/stdexcept.f
INCLUDE ./stdlib/stdslab.f
INCLUDE ./stdlib/stdco.f

( exit if macros are already defined [ you can do FORGET EXTASYNCIO_M POP to include them again ] )
POPBUFXT IFDEF EXTASYNCIO_M MACROS CREATE EXTASYNCIO_M

5 CONSTANT ENTRY_SIZE
65536 CONSTANT ENTRY_COUNT

0 CONSTANT entry.state ( byte_t )
1 CONSTANT entry.fd ( dword_t )

0 CONSTANT epoll_event.events
4 CONSTANT epoll_event.data

-1 CONSTANT RUNNABLE
0 CONSTANT INVALID
1 CONSTANT WAITING

1 CONSTANT EPOLL_CTL_ADD
2 CONSTANT EPOLL_CTL_DEL
3 CONSTANT EPOLL_CTL_MOD

1 CONSTANT EPOLLIN
2 CONSTANT EPOLLPRI
4 CONSTANT EPOLLOUT
8 CONSTANT EPOLLERR
16 CONSTANT EPOLLHUP
64 CONSTANT EPOLLRDNORM
128 CONSTANT EPOLLRDBAND
256 CONSTANT EPOLLWRNORM
512 CONSTANT EPOLLWRBAND
1024 CONSTANT EPOLLMSG
8192 CONSTANT EPOLLRDHUP

28 1 << CONSTANT EPOLLEXCLUSIVE
29 1 << CONSTANT EPOLLWAKEUP
30 1 << CONSTANT EPOLLONESHOT
31 1 << CONSTANT EPOLLET

1024 CONSTANT MAXEVENTS

ENDMACROS

( normal include guard )
POPBUFXT IFDEF EXTASYNCIO_F CREATE EXTASYNCIO_F

DWORD_T TMPVAR ENTRY_ARR
DWORD_T TMPVAR EPFD
DWORD_T QWORD_T + TMPVAR EPOLL_EVENT_CTL ( epoll_event struct for epoll_ctl )
DWORD_T TMPVAR EPOLL_EVENTS_WAIT ( epoll_event array for epoll_wait )

: EPOLL_CREATE
    ( size argument is ignored, but for compatibility with
    older linux versions we give the size hint anyway )
    1024 213 #SYSCALL1
;

( r | timeout -D- nfds :; Call epoll_wait with statically known args, except for timeout. Returns events into EPOLL_EVENTS_WAIT,
epfd arg is EPFD, and count is MAXEVENTS )
: ASYNCIO_EPOLL_WAIT
    MAXEVENTS
    EPOLL_EVENTS_WAIT @d BASE +
    EPFD @d
    232 #SYSCALL4
;

( r | fd op -D- :; Call epoll_ctl with statically known epfd and events. )
: ASYNCIO_EPOLL_CTL
    EPOLL_EVENT_CTL @d BASE +
    -ROT
    EPFD @d
    233 #SYSCALL4
    POP
;

( r | task -D- taskid :; Given a task pointer, return its ID [ index ]. Note that these are not *unique* IDs,
once a task is freed another can get its ID. )
: TASKID
    TASK_SLAB @d slab.mem_start FIELD @d SWAP -
    TASK_SIZE SWAP /
;

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
    0 ['] WAKER LITERAL SPAWN_TASK -1 == IF EXC_NOMEM THROW THEN
    ASYNC_SPAWN_TASK
;

: ASYNCIO_INIT
    ( make epfd that will be used by the waker )
    EPOLL_CREATE EPFD !d 

    ( allocate memory for returned events )
    [ 4096 12 1024 * / ] LITERAL pALLOC DUP -1 == IF
        POP EXC_NOMEM THROW
    THEN EPOLL_EVENTS_WAIT !d

    ( allocate memory for task entries )
    [ 4096 ENTRY_COUNT ENTRY_SIZE * / ] LITERAL
    pALLOC DUP -1 == IF
        POP EXC_NOMEM THROW
    THEN ENTRY_ARR !d

    ( initialize task entries )
    0 BEGIN
    DUP ENTRY_COUNT > WHILE
        INVALID OVER ENTRY_SIZE ENTRY_ARR @d INDEX !b
        1 +
    REPEAT POP
;
