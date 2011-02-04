---
title: Blip Overview
layout: Default
---
Blip.parellel
=============
an overview of the parallelization strategies available in the blip library
    by Fawzi Mohamed

Note that there is a [preprint of an article](https://github.com/fawzi/blip/raw/master/paraArt.pdf) on the parallelization

Parallelization hierarchy
-------------------------
 * smp is the first level in the parallelization hierarchy/methods supported in
   blip, it is the more basic one and the one used by all the others. Smp offers
   shared memory and several execution contextes, and is confined on one machine
   (there are ways to extend it further, but I don't think that it is a good
   idea)
 * mpi is the second level, it stands for message passing interface, and more or
   less mirrors what is offered by MPI 1.2: message passing but on a fixed number
   N of "executers", these can be identified with a simple number from 0 to N-1.
   These can be distributed in various ways (higher dimensional spaces,
   subsetting,...). Loosing an executer is not supported. While mpi is called
   message passing and simple point to point message passing is possible the
   emphasis is on collective communication that is normally implemented
   efficiently. Mpi is just an interface, it can be realized on the top of mpi,
   but it doesn't have to.
 * rpc stays for remote procedure calling, it is implemented using some ideas
   from xml rpc and rest interfaces, and has an api similar to Next distributed
   objects (DO): you have a way to publish objects, and you can connect and call
   method using proxies to communicate to remote objects. Remote objects are
   identified through url-like strings, several low level protocols can be
   supported

SMP
----
Today computers are able to execute several threads concurrently both by having
multiple cores, and having multiple issuer per core (Hyperthreading and
similar).

Obviously one wants to take advantage of these computing resources.

Threads are an obvious way to try to use these resources, but in my opinion
normally they are not a very good primitive to expose to the programmer, because
they work well when their number is equal to the number of executing units, an
worse when it is very different. So the optimal choice is to use a number of
threads equal to the number of hardware threads, and subdivide the work so that
all thread are busy.

Subdividing the the work in n_threads chunks is a natural choice. This is
possible, but not so easy, as this number is not constant, and this approach is
not robust with respect to having other work progress concurrently (both by your
own program and by the OS). The same task A might be executed both alone and
concurrently with task B, so finding the correct number of threads to assign to
the task A is not easy.

Assuming that tasks management/switching costs x it is much better to try to
subdivide the problem in as many tasks as possible, but making sure that each
task on average still needs y >> x time to execute (for example y~10x)
independently of the number of processors. In this case a scheduler can keep
processors busy by distributing tasks around, and if load on cone processor
changes the work can be automatically moved. This means that the unit of
computation one has to think about is not the thread, but one of these smaller
units, that we call tasks.

Having many tasks also works well as latency hiding mechanism, many tasks can do
operations that can stall the cpu. I/O: network and disk operations, and lately
also things like GPU computation. To avoid wasting cpu cycles one should switch
to another task as soon one of these operations is started.

There is one thing that speaks against creating as many tasks as possible: task
handling and management uses up resources, and some problems would create really
many tasks. The solution to this is not to create too many tasks at once but
create them lazily. This must be done in concert with the evaluation strategy.

To find a way to strike a balance between these two we will consider a recursive
computation. Recursive computations build an important class of computations,
all divide and conquer approaches can be cast in this form for example, thus
having a good solution for them will likely improve much the value of our
solution. A recursive function calls itself, and generates other tasks. to
evaluate this on a single processor there is a well known efficient strategy:
eager evaluation, evaluate first the subtasks before finishing the main task.
This means a depth first evaluation of the tasks. Thus we have our evaluation
strategy for recursive tasks: evaluate subtasks first.

In general we will not get rid of the task switching overhead (this is safely
possible only in few instances), but we will avoid creating too many task at the
same time. The recursive approach is not always correct: independent tasks
should be scheduled on an equal footing independently on how "deep" each one is.
With this we have the core of the idea behind blip.parallel.smp : efficiently
evaluate several recursive tasks.

This also indirectly explains why threads are not the ideal parallelization
primitive: disregarding technical problems (like wired memory,...) threads have
an implicit "fairness" in them that means that all threads have more or less
the same chance of executing (depending on the priority), and should not be
ignored for long times.
This is correct for external tasks, between different recursive task, but
within a recursive task it forces tasks up in the hierarchy to be executed,
and gives a breath first execution that will allocate too many tasks.

The execution characteristics within a recursive task or between different tasks
is very different, and it is the programmer job to choose between them,
Recursive tasks *might* be parallel and should be executed in parallel
if free hardware resources are available, whereas independent tasks *should*
be executed in parallel with some kind of fairness.
Recursive tasks cope well with data parallel workloads, thread-like parallelization
copes well with webserver-like load.
Making some automatic scheduler choose between them is not going to work well.

Now lets look at the ugly details a little bit more.

In general it is better to always try to keep all computation resources busy
(there are some exceptions like intel processors with memory intensive tasks
when they still were memory starved), and to make things more difficult there is
a memory hierarchy and different processors share different levels of the memory
hierarchy, and thus moving things between them has different cost.

To simplify things I will assume that it is never worthwhile to keep a processor
idle. I will take the view of the computational scientist: one that knows that
the problem is big enough to use the whole machine, and is interested in maximum
throughput. Deciding to use only part of the available resources, or putting an
upper bound on the latency of the tasks is a refinement that can be done later.

Blip.parallel.smp is mainly based on schedulers (queues) fixed at
processor/thread level that if idle try to steal work from the neighboring
schedulers (in the order given by the level of memory hierarchy sharing).

Ideally when stealing one should try to equalize the amount of work between the
schedulers. As the execution time of a task is unknown this is impossible to do
exactly, but in general you should try to steal large tasks, which means root
tasks (that will spawn other tasks) in recursive tasks: steal root tasks,
execute children tasks first. The actual stealing amount is randomized a bit, to
increase the chance of good work distribution.

Using this approach one can have a simple model and a simple conceptual model to
describe concurrent programs.

One has tasks (see blip.parallel.smp.BasicTasks) that execute a given function and:

 - can be created and spawn
 - are always spawn in the context of a super task
 - are finished only when all their subtasks are finished

 it is possible to:
 
 - add operations to execute when a task finishes
 - wait for the completion of some task
 - delay the executing task and then resubmit it later (useful when the task
   executes one of those operations that stall the cpu, see Taks.delay and
   Task.resubmitDelayed)
 - you can ask the current task for a cache that is common to the current numa
   node (this is useful for pools, and delete lists in general, see cachedPool,
   cachedPoolNext in blip.container.Cache).

Some languages try have special syntax for some of these operations, but
normally the program does not have so many of them to make any special syntax
really worth it, it should be clean, but method calling work just well enough.

Another concept useful to build parallel programs are dataflow variables.
Dataflow variables are variables that can be set several times but always to the
same value. Reading a dataflow variable blocks until a value is set. The nice
thing about dataflow variables is that they do not introduce race conditions: a
program using them either always blocks or never does.

Using this you have solution that does work well most of the time. Most of the
time is not always, sometime you need to ensure that a task stays on one
processor, sometime you might want to start with a specific task distribution
that you calculated using information of the numa topology. The advantage of
realizing everything as a library and with normal objects is that this is easily
possible.

With this you should understand the main ideas behind parallelization in Blip,
what is left are the "boring" optimizations, and implementation details that
really make a difference when using the library, but should not be important to
simply understand it.

Go to [BlipOverview](BlipOverview.html) to see some examples