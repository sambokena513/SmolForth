( Dependencies: bootstrap.f, stdstring.f, stdassert.f, stdctx.f, stdexcept.f, stdio.f, stddict.f, stdmem.f, stdslab.f )

( <stdco.f> :; Concurrency in the form of cooperative multitasking. )

( This file is currently a placeholder! )

(
    TODO: actually implement this;
    it'll be a round-robin scheduler with CPU budgets for each task and a `runnable?` field
    that if -1 means the scheduler is allowed to run the task, and if something else means the task
    is waiting on IO from that fd, epoll/poll won't be in the core scheduler, but rather be one of the tasks.
)

65536 CONSTANT MAX_TASKS
40 CONSTANT TASK_SIZE ( since a task is an i32 cpu_budget, i32 runnable?, and ctx context. )
DWORD_T VARIABLE TASK_SLAB 0 TASK_SLAB !d

: STDCO_INIT
    TASK_SIZE MAX_TASKS MAKE_SLAB
    DUP -1 == IF
        EXIT
    THEN
    TASK_SLAB !d

    ( TODO: initialize the two task lists )
;
