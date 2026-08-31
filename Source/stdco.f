( Dependencies: bootstrap.f, stdstring.f, stdassert.f, stdctx.f, stdexcept.f, stdio.f, stddict.f, stdmem.f, stdslab.f )

( <stdco.f> :; Concurrency in the form of cooperative multitasking. )

(
    This is a round-robin scheduler that tries to split a configurable timeslot over every
    runnable task. Tasks voluntarily call YIELD [ switch to next task ] or CHECKPOINT [ yield if needed ]
    to give other tasks a chance.

    C-style reference for the Task struct:

        typedef struct Task {
            Task *next;
            Task *prev;
            i64 timestamp;
            i32 runnable;
            Context ctx;
        } Task;

    We maintain two doubly-linked lists of tasks; one for runnable tasks and one for suspended tasks.
    A task is runnable if its `runnable` field is set to -1, otherwise the value of `runnable` corresponds
    to a file descriptor the task is waiting on. Note that this is for forwards compatibility with a privileged epoll task,
    the core scheduler does not actually deal with resuming suspended tasks.

    A task's `timestamp` is a TSC value that when reached, means the task has used its alloted run time. This is recalculated
    and set whenever a task is switched *to*, and periodically compared against RDTSC to decide whether CHECKPOINT should make
    the task yield or not.

    Finally, each task has a `ctx` field holding an execution context associated with that task, note that this is stored *by value*,
    it is not a pointer to an execution context, which makes the task struct in total 52 bytes with these fields and offsets:

        0 - DWORD_T next
        4 - DWORD_T prev
        8 - QWORD_T timestamp
        16 - DWORD_T runnable
        20 - DWORD_T ctx
        20 - DWORD_T ctx.dSP_BASE
        24 - DWORD_T ctx.rSP_BASE
        28 - DWORD_T ctx.eSP_BASE
        32 - DWORD_T ctx.lSP_BASE
        36 - DWORD_T ctx.dSP
        40 - DWORD_T ctx.rSP
        44 - DWORD_T ctx.eSP
        48 - DWORD_T ctx.lSP
)

( small wrapper around rdtsc )
: RDTSC
    [
        15 ,b -82 ,b -24 ,b 15 ,b
        49 ,b 15 ,b -82 ,b -24 ,b
        72 ,b -63 ,b -30 ,b 32 ,b
        72 ,b 9 ,b -48 ,b 73 ,b
        -119 ,b 6 ,b 73 ,b -125 ,b
        -58 ,b 8 ,b
    ]
;

QWORD_T 2 * TMPVAR calibration_timespec
0 calibration_timespec !q
1000000 calibration_timespec QWORD_T + !q

( get the length of a second in timestamp counter cycles )
: GET_STSCVAL
    RDTSC ( start )
    ( sys_nanosleep for 1ms )
    calibration_timespec BASE + 35 #SYSCALL1 POP
    RDTSC - ( elapsed = now - start )
    940 * ( we don't multiply by 1000 here because we expect roughly 5.5% scheduler overhead. )
    ( it's better for this to be off by being too short than to be off by being too long. )
;

( CYCLE_SPEED is the target time it should take to run every task once.
We set this to 1 second by default for low overhead, but for more IO-heavy
programs or ones that need to be more responsive you'd want this lower. Such as
maybe 16.6ms for a game loop, or 1ms for a multi-client server. Note that this
would of course increase scheduler overhead since YIELD is pretty expensive. )
QWORD_T VARIABLE CYCLE_SPEED GET_STSCVAL CYCLE_SPEED !q
65536 CONSTANT MAX_TASKS
52 CONSTANT TASK_SIZE

MACROS

0 CONSTANT task.next
4 CONSTANT task.prev
8 CONSTANT task.timestamp ( when we should switch tasks, ie. if rdtsc >= task.timestamp we yield )
16 CONSTANT task.runnable
20 CONSTANT task.ctx

20 CONSTANT task.ctx.dSP_BASE
24 CONSTANT task.ctx.rSP_BASE
28 CONSTANT task.ctx.eSP_BASE
32 CONSTANT task.ctx.lSP_BASE

36 CONSTANT task.ctx.dSP
40 CONSTANT task.ctx.rSP
44 CONSTANT task.ctx.eSP
48 CONSTANT task.ctx.lSP

ENDMACROS

DWORD_T VARIABLE TASK_SLAB 0 TASK_SLAB !d
DWORD_T VARIABLE RUNNABLE_LIST 0 RUNNABLE_LIST !d
DWORD_T VARIABLE SUSPENDED_LIST 0 SUSPENDED_LIST !d
DWORD_T VARIABLE CURR_TASK 0 CURR_TASK !d
( while technically the max task count is representable in 16 bits, it's not representable
as a *signed* 16-bit integer, so RUNNABLE_COUNT is a DWORD_T. )
DWORD_T VARIABLE RUNNABLE_COUNT 0 RUNNABLE_COUNT !d

( Print out a task's fields. )
: PRINT_TASK
    r" next: " PRINT DUP task.next FIELD @d .
    r" prev: " PRINT DUP task.prev FIELD @d .
    r" timestamp: " PRINT DUP task.timestamp FIELD @q .
    r" runnable: " PRINT DUP task.runnable FIELD @d .
    task.ctx FIELD PRINT_CTX
;

( save a few bytes on this string constant since its reused )
HERE " ------------------" 0 ,b  MACROS CONSTANT PADDING_STRING ENDMACROS
( Print out both task lists. )
: DUMP_TASKS
    r" -----RUNNABLE-----" PRINTLN
    RUNNABLE_LIST @d BEGIN
    DUP WHILE
    r" ----" DUP PRINT OVER PRINTNUM PRINTLN
    DUP PRINT_TASK @d
    PADDING_STRING PRINTLN
    REPEAT POP

    r" -----SUSPENDED----" PRINTLN
    SUSPENDED_LIST @d BEGIN
    DUP WHILE
    r" -----" DUP PRINT OVER PRINTNUM PRINTLN
    DUP PRINT_TASK @d
    PADDING_STRING PRINTLN
    REPEAT POP
;

( r | task -D- )
: UNLINK_TASK
    DUP
    DUP task.prev FIELD @d IF
        ( task.prev.next = task.next )
        DUP task.prev FIELD @d task.next FIELD
        SWAP task.next FIELD @d SWAP !d
    ELSE
        ( head = task.next )
        DUP task.runnable FIELD @d TRUE == IF
            task.next FIELD @d RUNNABLE_LIST !d
            RUNNABLE_COUNT @d -1 + RUNNABLE_COUNT !d
        ELSE
            task.next FIELD @d SUSPENDED_LIST !d
        THEN
    THEN

    DUP task.next FIELD @d IF
        ( task.next.prev = task.prev )
        DUP task.next FIELD @d task.prev FIELD
        SWAP task.prev FIELD @d SWAP !d
    ELSE
        POP
    THEN
;

( r | task -D- )
: LINK_RUNNABLE
    RUNNABLE_LIST @d DUP IF
        ( head.prev = new; new.next = head; )
        2DUP task.prev FIELD !d
        OVER task.next FIELD !d
    ELSE
        ( new.next = 0 )
        POP
        0 OVER task.next FIELD !d
    THEN
    ( head = new; new.prev = 0 )
    DUP RUNNABLE_LIST !d
    0 SWAP task.prev FIELD !d

    RUNNABLE_COUNT @d 1 + RUNNABLE_COUNT !d
;

( r | task -D- )
: LINK_SUSPENDED
    SUSPENDED_LIST @d DUP IF
        ( head.prev = new; new.next = head; )
        2DUP task.prev FIELD !d
        OVER task.next FIELD !d
    ELSE
        ( new.next = 0 )
        POP
        0 OVER task.next FIELD !d
    THEN
    ( head = new; new.prev = 0 )
    DUP SUSPENDED_LIST !d
    0 SWAP task.prev FIELD !d
;

( r | task -D- Given a task pointer, set the task's timestamp and switch to it. )
: SWITCH_TASK
    RUNNABLE_COUNT @d CYCLE_SPEED @q /
    RDTSC + OVER task.timestamp FIELD !q
    DUP CURR_TASK !d
    task.ctx FIELD SWITCH_CTX
;

( r | -D- task :; Assuming there is at least one runnable task, return the next one. )
: GET_NEXT_TASK
    CURR_TASK @d task.next FIELD @d DUP 0 == IF
        POP RUNNABLE_LIST @d
    THEN
;

( r | fd -D- :; Suspend the current task and switch to another runnable one. If there are no runnable tasks to switch to, exit the scheduler. )
: SUSPEND
    CURR_TASK @d
    DUP UNLINK_TASK
    GET_NEXT_TASK >C
    DUP LINK_SUSPENDED
    task.runnable FIELD !d

    C> DUP 0 == IF
        POP MAIN_CTX SWITCH_CTX EXIT
    THEN
    SWITCH_TASK
;

( r | task -D- :; Make a suspended task runnable once more. Note for any asynchronous IO scheduler,
since we clear the fd field here, this means that you need to either also clear your own metadata on 
what a task is waiting on, possibly deregistering fds with epoll_ctl for example, *or* maintain a separate
data structure mapping task pointers to their fds and have async IO functions check that before calling SUSPEND. )
: WAKE_TASK
    DUP UNLINK_TASK 
    DUP LINK_RUNNABLE
    TRUE SWAP task.runnable FIELD !d
;

( r | -D- :; Switch from the current task to the next one. )
: YIELD
    GET_NEXT_TASK SWITCH_TASK
;

( r | -D- :; Yield if needed. More performant than force-yielding using YIELD, use for CPU-bound tasks. )
: CHECKPOINT
    RDTSC CURR_TASK @d task.timestamp FIELD @q < IF YIELD THEN
;

( r | task -D- :; Given a task pointer, kill the task. )
: END_TASK
    DUP CURR_TASK @d == IF
        RUNNABLE_COUNT @d -1 + IF
            GET_NEXT_TASK
            [ COMP_START ] LITERAL BASE + OVER task.ctx FIELD >rR
            CURR_TASK @d OVER task.ctx FIELD >rD
            SWITCH_TASK
        ELSE
            [ COMP_START ] LITERAL BASE + MAIN_CTX >rR
            CURR_TASK @d MAIN_CTX >rD
            0 CURR_TASK !d ( exit scheduler )
            MAIN_CTX SWITCH_CTX
        THEN
    ELSE
        DUP UNLINK_TASK
        DUP task.ctx.dSP_BASE FIELD @d 6 SWAP pFREE
        TASK_SLAB @d SLAB_FREE
    THEN
;

( r | xt -D- :; Wrapper function to run a task, when spawning a task we
set up the context so that inside it RUN_TASK called that task's entry point. )
: RUN_TASK
    DYN_CATCH DUP IF ( nonzero value means it threw )
        r" Uncaught exception in task with ID <" PRINT CURR_TASK @d PRINTNUM
        r" > and exception value <" PRINT PRINTNUM r" >, killing task." PRINTLN
    ELSE
        POP
    THEN
    CURR_TASK @d END_TASK
;

( Pop n values from the data stack. )
( r | argn .. arg2 arg1 count -D- )
: nPOP
    BEGIN
    DUP WHILE
        NIP -1 +
    REPEAT POP
;

( r | argn .. arg2 arg1 argc xt -D- task | -1 :; Given an xt and argument count, allocate memory for a new task and its stacks,
and arrange for switching to its context to execute that xt with provided arguments. )
: SPAWN_TASK
    TASK_SLAB @d SLAB_ALLOC DUP -1 == IF
        2POP nPOP -1 EXIT
    THEN
    DUP LINK_RUNNABLE
    TRUE SWAP task.runnable FIELD !d

    ( 6 pages in total; 2 for dS, 2 for rS, 1 for eS, and 1 for lS )
    6 pALLOC DUP -1 == IF
        2POP nPOP
        RUNNABLE_LIST @d DUP
        UNLINK_TASK TASK_SLAB @d SLAB_FREE
        -1 EXIT
    THEN

    ( initialize stacks )
    RUNNABLE_LIST @d

    2DUP task.ctx.dSP_BASE FIELD !d
    2DUP task.ctx.dSP FIELD !d SWAP [ 4 4096 * ] LITERAL + SWAP

    2DUP task.ctx.rSP_BASE FIELD !d
    2DUP task.ctx.rSP FIELD !d

    2DUP task.ctx.eSP_BASE FIELD !d
    2DUP task.ctx.eSP FIELD !d SWAP 4096 + SWAP

    2DUP task.ctx.lSP_BASE FIELD !d
    TUCK task.ctx.lSP FIELD !d

    ( push RUN_TASK's entry point to the new task's return stack )
    [ ' RUN_TASK 4 + @d ] LITERAL BASE + SWAP task.ctx FIELD >rR

    ( number of items to copy into the task's data stack is 1 + the arg count because of the xt arg to RUN_TASK )
    SWAP 1 +

    ( copy n items into the new task's data stack )
    QWORD_T * RUNNABLE_LIST @d task.ctx.dSP_BASE FIELD @d +
    DUP RUNNABLE_LIST @d task.ctx.dSP FIELD !d
    BEGIN
        DUP RUNNABLE_LIST @d task.ctx.dSP_BASE FIELD @d
    < WHILE ( loop until we reach the task's stack base )
        TUCK -8 + !q -8 +
    REPEAT POP

    ( return the new task )
    RUNNABLE_LIST @d
;

( r | -D- :; Initialize all necessary scheduler state for task spawning and switching to work. )
: STDCO_INIT
    GET_STSCVAL CYCLE_SPEED !q

    ( initialize task slab so we can allocate tasks )
    TASK_SIZE MAX_TASKS MAKE_SLAB
    DUP -1 == IF
        EXIT
    THEN
    TASK_SLAB !d

    ( initialize task lists and counts )
    0 RUNNABLE_LIST !d
    0 SUSPENDED_LIST !d
    0 RUNNABLE_COUNT !d
;

(

    A note on performance, during testing with this code:

        4 VARIABLE Atask
        4 VARIABLE Btask
        : A BEGIN RDTSC Btask @d SWITCH_TASK RDTSC - . AGAIN ;
        : B BEGIN Atask @d SWITCH_TASK AGAIN ;
        0 ' A SPAWN_TASK Atask !d
        0 ' B SPAWN_TASK Btask !d
        Atask @d SWITCH_TASK

    We got output of around 950 most of the time, this is for *two* context switches,
    so the actual time is around 475 TSC cycles on the machine I tested it on, which corresponds to around 200ns.

    This means that if we *only* switched tasks constantly without any actual work inside the task we could do 5 million task switches a second.
    If we say that we can only take 5% of available CPU time that becomes 250000 tasks, which is much higher than the 65536 max tasks.

    So keep that in mind once you start adjusting the CYCLE_SPEED variable.

)
