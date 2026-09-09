( <extasyncio.f> :; This module implements a basic WAKER task that whenever it gets a chance to execute, calls epoll_wait and attempts to wake suspended tasks waiting on IO. 
For tasks to properly work with the waker they need to be spawned using the library-provided ASYNC_SPAWN_TASK wrapper over SPAWN_TASK, and use the ASYNC_* IO functions with nonblocking
fds for any operation that normally could block. )

(
    Architecture:

    The core idea behind this library is that asynchronous IO operations register fds with epoll_ctl before performing the nonblocking operation, and if it returned EAGAIN,
    then they call SUSPEND. Then a privileged WAKER task that owns the epfd calls epoll_wait every time execution reaches it, with a timeout of 0 if there are other runnable tasks,
    and a timeout of -1 if there are not. If there are no other runnable tasks *and* no suspended tasks, it exits.

    This library does not aim for perfect performance, especially as it is not a resource manager, merely a task waker,
    and as such we always register an fd on SUSPEND, and remove on END_TASK or WAKE_TASK. This gives us the useful
    invariant that an fd is only in the interest list [ and therefore owned by the async library ] when a task is not
    runnable, letting running tasks arbitrary call synchronous IO, close and re-open fds, and change state without causing
    the interest list to become out of sync with the program state.

    Note that while all state should be dealt with normally by the library in most cases, in the case of remotely messing with the fds
    of a suspended task from a different one, you'll need to manually preserve our invariants, namely that if an fd is no longer in the
    interest list, it should also be removed from the fd field of the task, and the task should be either woken or killed.

    We accomplish these things by giving each possible task an index in an array with 65536 elements.
    Each entry is 40 bits, the first 8 bits are the task's state:

        -1 = Runnable
        0 = Waiting on fd

        Other values reserved for future extensions.

    And the 32-bit field is an fd the task is waiting on, its value is irrelevant if the first field is negative.

    To ensure these fields get properly updated, we provide a wrapper over SPAWN_TASK called ASYNC_SPAWN_TASK that sets the new task's onsuspend and onkill fields
    as well as initializing its entry to be 0 for RUNNABLE.

    The onsuspend field is set to a function that takes an fd and events as args through the control-flow stack, and registers or rearms it with epoll_ctl, as well
    as setting its entry to be marked as waiting on that fd.

    The onkill field is set to a function that takes a task pointer and clears the task's metadata entry and calls epoll_ctl to remove the task's fd [ if there is one ] from the
    interest list.
)

( since these are stdlib modules we already have their functions,
reincluding them just serves to give us their macros too )
<INCLUDE> Source/stdlib/stdexcept.f
<INCLUDE> Source/stdlib/stdco.f
<INCLUDE> Source/stdlib/stdio.f

( exit if macros are already defined [ you can do FORGET EXTASYNCIO_M POP to include them again ] )
POPBUFXT IFDEF EXTASYNCIO_M MACROS CREATE EXTASYNCIO_M

5 CONSTANT ENTRY_SIZE
12 CONSTANT EPOLL_EVENT_SIZE
65536 CONSTANT ENTRY_COUNT
1024 CONSTANT MAXEVENTS

0 CONSTANT entry.state ( byte_t )
1 CONSTANT entry.fd ( dword_t )

0 CONSTANT epoll_event.events
4 CONSTANT epoll_event.data

-1 CONSTANT RUNNABLE ( means that the fd field is valid but needs to be rearmed )
0 CONSTANT WAITING ( fd is active and task is waiting on it )

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

DWORD_T VARIABLE ENTRY_ARR
DWORD_T VARIABLE EPFD
DWORD_T QWORD_T + VARIABLE EPOLL_EVENT_CTL ( epoll_event struct for epoll_ctl )
DWORD_T VARIABLE EPOLL_EVENTS_WAIT ( epoll_event array for epoll_wait )

: EPOLL_CREATE
    ( size argument is ignored, but for compatibility with
    older linux versions we give the correct size hint anyway
    rather than just putting any nonzero value )
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

( r | task -D- :;  Clear a task entry, deregistering its fd if it has one. )
FUNCTION ASYNCIO_ONKILL { task_entry }
    TASKID ENTRY_SIZE ENTRY_ARR @d INDEX
    TO task_entry

    ( if fd is registered, get rid of it so we don't make the kernel leak memory )
    task_entry entry.state FIELD @b +? IF
        task_entry entry.fd FIELD @d
        EPOLL_CTL_DEL ASYNCIO_EPOLL_CTL
    THEN
ENDFUNC

( r | fd events -C- :; Mark a task as waiting on a set of events from a particular fd. )
FUNCTION ASYNCIO_ONSUSPEND
    CURR_TASK @d TASKID ENTRY_SIZE ENTRY_ARR @d INDEX
    C> C>
    \ events fd task_entry \

    ( set up events )
    events EPOLL_EVENT_CTL @d epoll_event.events FIELD !d
    CURR_TASK @d EPOLL_EVENT_CTL @d epoll_event.data FIELD !q

    TRY ( register fd )
        fd EPOLL_CTL_ADD ASYNCIO_EPOLL_CTL
    CATCH
        DUP EPERM == IF ( if a task tries to wait on something that is always ready, don't suspend it )
            POP RUNNABLE task_entry entry.state FIELD !b
            ( slightly weird here but we have to not only exit ASYNCIO_ONSUSPEND
            but also the task scheduler's SUSPEND so the task doesn't get unlinked )
            rSP@ 16 + rSP!
        THEN
        THROW ( if not EPERM, re-throw it )
    ENDTRY

    ( update metadata for the task )
    WAITING task_entry entry.state FIELD !b
    fd task_entry entry.fd FIELD !d
ENDFUNC

( A task that should run for the whole lifetime of a program using the async system, WAKER attempts
to wake suspended tasks if their fds are ready everytime execution reaches it, and blocks the whole
thread if there are no other runnable tasks to make sure we don't max out the CPU core Forth is running
on if there's nothing to be done. )
FUNCTION WAKER { revents_len task entry }
    BEGIN
        ( get ready tasks )
        RUNNABLE_COUNT @d 1 == IF
            SUSPENDED_LIST @d 0 == IF
                r" WAKER: No remaining runnable or suspended tasks, exiting." PRINTLN EXIT
            THEN
            -1 ASYNCIO_EPOLL_WAIT
        ELSE
            0 ASYNCIO_EPOLL_WAIT
        THEN
        TO revents_len

        ( wake each ready task )
        0 BEGIN
        DUP revents_len > WHILE
            DUP EPOLL_EVENT_SIZE EPOLL_EVENTS_WAIT @d INDEX
            epoll_event.data FIELD @q TO task

            task TASKID ENTRY_SIZE ENTRY_ARR @d INDEX
            TO entry

            ( deregister fd task was waiting on and link back into runnable tasks )
            entry entry.fd FIELD @d EPOLL_CTL_DEL ASYNCIO_EPOLL_CTL
            RUNNABLE entry entry.state FIELD !b
            task WAKE_TASK

            1 +
        REPEAT POP
        
        YIELD
    AGAIN
ENDFUNC

( Spawn a task that behaves asynchronously on IO, for stack effect see SPAWN_TASK in <stdco.f>. )
: ASYNC_SPAWN_TASK
    SPAWN_TASK DUP -1 == IF EXIT THEN ( spawn the task )
    RUNNABLE OVER TASKID ENTRY_SIZE ENTRY_ARR @d INDEX !b ( task starts as runnable with no fd registered )

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
;

( Asynchronous IO functions. )

( get the TIB macros )
<INCLUDE> Source/stdlib/stdinclude.f

( ASYNC versions of all the functions related to INTERPRET, technically these
make the language now self-hosting. )
: ASYNC_REFILL
    READTIB EAGAIN == IF
        TIB buf.fd FIELD @d EPOLLIN >C >C SUSPEND TSELF
    THEN
;

: ASYNC_WORD_START
    TIB_IDX 255 & BEGIN
    DUP TIB_LEN 255 & > WHILE

        DUP TIB + @b 32 ==
        OVER TIB + @b 10 == |
        IF
            1 +
        ELSE
            EXIT
        THEN

    REPEAT
    ( out of input )
    aTIB_IDX !b

    TIB_LEN 255 & 255 == IF
        CLEAR
    THEN

    ASYNC_REFILL
    TSELF ( retry )
;

: ASYNC_WORD
    ASYNC_WORD_START ( start index is the start of the word )
    BEGIN ( outer loop gives new input whenever we run out )
        DUP BEGIN ( inner loop parses characters and returns if we find a word )
        DUP TIB_LEN 255 & > WHILE
            DUP TIB + @b 32 ==
            OVER TIB + @b 10 == |
            IF
                0 OVER TIB + !b ( replace whitespace with nul delimiter )
                1 + aTIB_IDX !b ( parsing should start after nul, not at it )
                TIB + EXIT ( return start of word )
            ELSE
                1 +
            THEN

        REPEAT
        aTIB_IDX !b

        TIB_LEN 255 & 255 == IF
            POP 0
            CLEAR
        THEN

        ASYNC_REFILL
    AGAIN
;

: ASYNC_INTERPRET
    BEGIN
        ASYNC_WORD
        DUP NUMBER? -1 ( err ) == IF
            ( normal word case )
            POP
            FIND DUP -1 == IF
                POP /' " No such word." 10 ,b '/ ABORT
            ELSE
                STATE IF
                    DUP 8 + @b 1 & IF
                        EXECUTE
                    ELSE
                        ECR32
                    THEN
                ELSE
                    EXECUTE
                THEN
            THEN
        ELSE
            ( number case )
            NIP
            STATE IF
                COMPILE LITERAL
            THEN
        THEN
    AGAIN
;
