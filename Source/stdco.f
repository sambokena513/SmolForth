( Dependencies: bootstrap.f, stdstring.f, stdassert.f, stdctx.f, stdexcept.f, stdio.f, stddict.f, stdmem.f, stdslab.f )

( <stdco.f> :; Concurrency in the form of cooperative multitasking. )

( This file is currently a placeholder! )

(
    TODO: actually implement this;
    it'll be a round-robin scheduler with CPU budgets for each task and a `runnable?` field
    that if -1 means the scheduler is allowed to run the task, and if something else means the task
    is waiting on IO from that fd, epoll/poll won't be in the core scheduler, but rather be one of the tasks.
)

CREATE STDCOF_PLACEHOLDER
