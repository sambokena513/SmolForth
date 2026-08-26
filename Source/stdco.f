( Dependencies: bootstrap.f, stdstring.f, stdassert.f, stdctx.f, stdexcept.f, stdio.f, stddict.f, stdmem.f, stdslab.f )

( <stdco.f> :; Concurrency in the form of cooperative multitasking. )

(
    TODO: actually implement this;
    it'll be a round-robin scheduler with CPU budgets for each task and a `runnable?` field
    that if -1 means the scheduler is allowed to run the task, and if something else means the task
    is waiting on IO from that fd, epoll won't be in the core scheduler, but rather be one of the tasks.

    The epoll task will call epoll_wait with a timeout of 0 if there are still runnable tasks,
    and with a timeout of -1 if there are no tasks to run except itself.

    We also use EPOLLONESHOT, this lets async IO functions be a lot simpler as each function
    simply registers an fd with epoll_ctl, and the epoll task calls epoll_wait.
)

65536 CONSTANT MAX_TASKS
40 CONSTANT TASK_SIZE ( since a task is an i32 cpu_budget, i32 runnable?, and ctx context. )

DWORD_T VARIABLE TASK_SLAB 0 TASK_SLAB !d
DWORD_T VARIABLE RUNNABLE_LIST 0 RUNNABLE_LIST !d
DWORD_T VARIABLE SUSPENDED_LIST 0 SUSPENDED_LIST !d
DWORD_T VARIABLE CURR_TASK 0 CURR_TASK !d

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

( r | task -D- :; Given a task pointer, kill the task. )
: END_TASK
    TODO" free a task's entry in the task_slab, as well as its stacks, and unlink it from the task list it is a part of,
          with a special case if the task we're killing is the same as the current task
          (in which case it can't be done entirely atomically so it's more complex)"
;

( r | xt -D- :; Wrapper function to run a task, when spawning a task we
set up the context so that inside it RUN_TASK called that task's entry point. )
: RUN_TASK
    TODO" call execute wrapped in a TRY .. CATCH, and arrange for a task's memory to be freed when it exits or is killed"
;

( r | xt -D- task :; Given an xt, allocate memory for a new task and its stacks,
and arrange for switching to its context to execute that xt. )
: SPAWN_TASK
    TODO" allocate a new task, and set up its stacks such that the return stack starts with RUN_TASK"
;

( r | -D- :; Switch from the current task to the next one. )
: YIELD
    TODO" switch to the next task in the task list"
;

( r | -D- :; Subract 1 from the current task's CPU budget, if it goes under 0, reset it and call YIELD. )
: CHECKPOINT
    TODO" conditionally call YIELD"
;
