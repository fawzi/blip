Library oriented toward scientific applications.

It has:

 * N-dimensional arrays (blip.narray) that have a nice interface to lapack
 * random and combinatorial(extensive) testing framework (blip.rtest), parallel
 * serialization (blip.serialization) that supports both json format, that can be used also for input files and an efficient binary representation
 * SMP parallelization (blip.parallel.smp) (should improve much soon for many cores, and reduce task/fiber creation cost)
 * MPI parallelization built on the top of mpi, but abstracting it away (so that a pure tcp implementation is possible), for tightly coupled parallelization
 * a Distribued Objects framework that does rpc via proxies (blip.parallel.rpc)
 * a simple socket library that can be used to connect external programs, even if written in fortran or C (for a weak parallel coupling)

the random generation part now is in tango (tango.math.random).

To install see INSTALL.txt or the installation instruction for linux on the blip site (explains also how to setup the other libs)

enjoy

Fawzi Mohamed
