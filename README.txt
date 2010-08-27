Library oriented toward scientific applications.

It has:

 * N-dimensional arrays (blip.narray) that have a nice interface to lapack (that leverages the wrappers of baxissimo)
 * 2,3 and 4D vectors, matrixes and quaternions from the omg library of h3r3tic
 * random and combinatorial(extensive) testing framework (blip.rtest), parallel
 * serialization (blip.serialization) that supports both json format, that can be used also for input files and an efficient binary representation
 * SMP parallelization (blip.parallel.smp) a numa aware very flexible framework
 * MPI parallelization built on the top of mpi, but abstracting it away (so that a pure tcp implementation is possible), for tightly coupled parallelization
 * a Distribued Objects framework that does rpc via proxies (blip.parallel.rpc)
 * a simple socket library that can be used to connect external programs, even if written in fortran or C (for a weak parallel coupling)
 * a coherent and efficient io abstraction

the random generation part now is in tango (tango.math.random).

To install see INSTALL.txt or the installation instruction for linux on the blip site (explains also how to setup the other libs)

As the building of the tests can take a non negligible time (lot of template instantiations) the tests are separated from the library, even if the template that creates them is often part of the library.

The library uses D1.0, and probably some will ask why. Indeed D 2.0 does have some nice features, but by definition it is less stable than D1.0, furthermore the only really up to date working compiler is dmd, and that does not support x86_64 natively.
For a library that is used by a small number of users, and does tricky stuff like the smp parallelization, where finding bugs can be very time consuming, stability and availability for x86_64 are definitely more important than D 2.0 features.
D 1.0 is already nice and flexible enough to be able to do everything in an acceptable way, yes some things could be better, but there are no show stoppers, and already with D 1.0 I had my share of compiler regressions that needed code rewrites, D2.0 can only be worse (especially if one wants to support several compilers).
Thus for now blip will remain D 1.0, this might change in the future, and I did try to set things so that a future possible migration will not be too painful, but as of now of for some time more blip will be D 1.0, and maybe it will remain as such, just as there are libraries that use only C and not C++...

enjoy

Fawzi Mohamed
