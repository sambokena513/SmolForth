( Dependencies: bootstrap.f, stdstring.f, stdassert.f, stdctx.f, stdexcept.f, stdio.f, stddict.f, stdmem.f, stdslab.f )

( <stdco.f> :; Concurrency in the form of cooperative multitasking. )

(
    TODO: actually implement this;
    it'll be a round-robin scheduler with timestamps for each task and a `runnable?` field
    that if -1 means the scheduler is allowed to run the task, and if something else means the task
    is waiting on IO from that fd, epoll won't be in the core scheduler, but rather be one of the tasks.

    The epoll task will call epoll_wait with a timeout of 0 if there are still runnable tasks,
    and with a timeout of -1 if there are no tasks to run except itself.

    We also use EPOLLONESHOT, this lets async IO functions be a lot simpler as each function
    simply registers an fd with epoll_ctl, and the epoll task calls epoll_wait.

    C-style reference for the Task struct:

        typedef struct Task {
            Task *next;
            Task *prev;
            i64 timestamp;
            i32 runnable;
            Context *ctx;
        } Task;
)

65536 CONSTANT MAX_TASKS
56 CONSTANT TASK_SIZE ( since a task is an i32 cpu_budget, i32 runnable?, and ctx context. )

MACROS

0 CONSTANT task.next
4 CONSTANT task.prev
8 CONSTANT task.timestamp ( value of rdtsc when we switched to the task )
16 CONSTANT task.runnable
20 CONSTANT task.ctx

24 CONSTANT task.ctx.dSP_BASE
28 CONSTANT task.ctx.rSP_BASE
32 CONSTANT task.ctx.eSP_BASE
36 CONSTANT task.ctx.lSP_BASE

40 CONSTANT task.ctx.dSP
44 CONSTANT task.ctx.rSP
48 CONSTANT task.ctx.eSP
52 CONSTANT task.ctx.lSP

ENDMACROS

DWORD_T VARIABLE TASK_SLAB 0 TASK_SLAB !d
DWORD_T VARIABLE RUNNABLE_LIST 0 RUNNABLE_LIST !d
DWORD_T VARIABLE SUSPENDED_LIST 0 SUSPENDED_LIST !d
DWORD_T VARIABLE CURR_TASK 0 CURR_TASK !d

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

( r | -D- :; Call rdtsc and compare it to the current task's timestamp, if the difference crosses a threshold, call YIELD, else, do nothing. )
: CHECKPOINT
    TODO" conditionally call YIELD"
;

: STDCO_INIT
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
