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

        -2 = Runnable, no fd yet.
        -1 = Invalid
        0 = Runnable, fd registered
        1 = Waiting on fd

    And the 32-bit field is an fd the task is waiting on, its value is irrelevant if the first field is negative.

    To ensure these fields get properly updated, we provide a wrapper over SPAWN_TASK called ASYNC_SPAWN_TASK that sets the new task's onsuspend and onkill fields
    as well as initializing its entry to be -2 for RUNNABLENOFD.

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
1024 CONSTANT MAXEVENTS

0 CONSTANT entry.state ( byte_t )
1 CONSTANT entry.fd ( dword_t )

0 CONSTANT epoll_event.events
4 CONSTANT epoll_event.data

-2 CONSTANT RUNNABLENOFD ( initial state for an entry )
-1 CONSTANT INVALID ( no task )
0 CONSTANT RUNNABLE ( means that the fd field is valid but needs to be rearmed )
1 CONSTANT WAITING ( fd is active and task is waiting on it )

( epoll_ctl operations )
1 CONSTANT EPOLL_CTL_ADD
2 CONSTANT EPOLL_CTL_DEL
3 CONSTANT EPOLL_CTL_MOD

( events )
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

( control flags )
28 1 << CONSTANT EPOLLEXCLUSIVE
29 1 << CONSTANT EPOLLWAKEUP
30 1 << CONSTANT EPOLLONESHOT
31 1 << CONSTANT EPOLLET

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

( Clear a task entry, deregistering its fd if it has one. )
FUNCTION ASYNCIO_ONKILL { task_entry }
    CURR_TASK @d TASKID ENTRY_SIZE ENTRY_ARR @d INDEX
    TO task_entry

    ( if fd is registered, get rid of it so we don't make the kernel leak memory )
    task_entry entry.state FIELD @b +? IF
        task_entry entry.fd FIELD @d
        EPOLL_CTL_DEL
        ASYNCIO_EPOLL_CTL
    THEN

    ( since the task died the entry is no longer valid,
    note that we don't close the fd, that's the job of the task,
    and there are plenty of reason you'd want a task that died to
    keep the fd around, such as because *it doesn't need to own it* )
    INVALID task_entry !b
ENDFUNC

( r | fd events -C- :; Call epoll_ctl with EPOLL_CTL_MOD or EPOLL_CTL_ADD with given fd and events on the control
flow stack. )
: ASYNCIO_ONSUSPEND
    TODO" register or rearm an fd with epoll_ctl, if there is a *different* fd already registered, first get rid of that one"
;

( A task that should run for the whole lifetime of a program using the async system, WAKER attempts
to wake suspended tasks if their fds are ready everytime execution reaches it, and blocks the whole
thread if there are no other runnable tasks to make sure we don't max out the CPU core Forth is running
on if there's nothing to be done. )
: WAKER
    TODO" infinite loop of calling epoll_wait and yielding."
;

( Spawn a task that behaves asynchronously on IO, for stack effect see SPAWN_TASK in <stdco.f>. )
: ASYNC_SPAWN_TASK
    SPAWN_TASK DUP -1 == IF EXIT THEN ( spawn the task )
    RUNNABLENOFD OVER TASKID ENTRY_SIZE ENTRY_ARR @d INDEX !b ( task starts as runnable with no fd registered )

    ( set callbacks )
    ['] ASYNCIO_ONKILL LITERAL OVER task.onkill FIELD !d
    ['] ASYNCIO_ONSUSPEND LITERAL OVER task.onsuspend FIELD !d
;

( Start the async system with a first task and enter it. Intended to be used in an INIT function after CORE_INIT for programs that use asyncio. )
: ASYNC_START
    0 ['] WAKER LITERAL SPAWN_TASK -1 == IF EXC_NOMEM THROW THEN
    ASYNC_SPAWN_TASK DUP -1 == IF POP EXC_NOMEM THROW THEN
    SWITCH_TASK
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
