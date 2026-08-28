( Dependencies: bootstrap.f, stdstring.f, stdassert.f, stdctx.f, stdexcept.f, stdio.f, stddict.f, stdmem.f, stdslab.f )

( <stdco.f> :; Concurrency in the form of cooperative multitasking. )

(
    This is a round-robin scheduler that tries to split a roughly 1 second long timeslot over every
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
    A task is runnable if its `runnable?` field is set to -1, otherwise the value of `runnable?` corresponds
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
        16 - DWORD_T runnable?
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

QWORD_T VARIABLE STSCVAL GET_STSCVAL STSCVAL !q
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

: UNLINK_TASK
    DUP
    DUP task.prev FIELD @d IF
        ( task.prev.next = task.next )
        DUP task.prev FIELD @d task.next FIELD
        SWAP task.next FIELD @d SWAP !d
    ELSE
        ( head = task.next )
        DUP task.runnable FIELD @d -1 == IF
            task.next FIELD @d RUNNABLE_LIST !d
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

( r | task -D- :; Given a task pointer, kill the task. )
: END_TASK
    TODO" free a task's entry in the task_slab, as well as its stacks, and unlink it from the task list it is a part of,
          with a special case if the task we're killing is the same as the current task
          (in which case it can't be done entirely atomically so it's more complex)"

    CURR_TASK @d == IF
        TODO" edge case: task is the same one we're inside of"
    ELSE
        TODO" normal case, can free task memory and unlink it"
    THEN
;

( r | xt -D- :; Wrapper function to run a task, when spawning a task we
set up the context so that inside it RUN_TASK called that task's entry point. )
: RUN_TASK
    DYN_CATCH IF ( nonzero value means it threw )
        r" Uncaught exception in task with ID " PRINT CURR_TASK @d PRINTNUM r"  and exception value " PRINT .
        r" Killing task." PRINT
    THEN
    CURR_TASK @d END_TASK
;

( r | argn .. arg2 arg1 argcount xt -D- task :; Given an xt and argument count, allocate memory for a new task and its stacks,
and arrange for switching to its context to execute that xt with provided arguments. )
: SPAWN_TASK
    TODO" allocate a new task, and set up its stacks such that the return stack starts with RUN_TASK"
;

( r | -D- :; Switch from the current task to the next one. )
: YIELD
    TODO" switch to the next task in the task list"
;

( r | -D- :; Yield if needed. More performant than force-yielding using YIELD, use for CPU-bound tasks. )
: CHECKPOINT
    RDTSC CURR_TASK @d task.timestamp FIELD @d < IF YIELD THEN
;

( r | -D- :; Initialize all necessary scheduler state for task spawning and switching to work. )
: STDCO_INIT
    GET_STSCVAL STSCVAL !q

    ( initialize task slab so we can allocate tasks )
    TASK_SIZE MAX_TASKS MAKE_SLAB
    DUP -1 == IF
        EXIT
    THEN
    TASK_SLAB !d

    ( initialize task lists )
    0 RUNNABLE_LIST !d
    0 SUSPENDED_LIST !d
;
