Ancillary library to tango, oriented toward scientific applications.

It has:

 * N-dimensional arrays (blip.narray) that have a nice interface to lapack
 * random and combinatorial(extensive) testing framework (blip.rtest), parallezied
 * serialization (blip.serialization) that supports json format, and can be used also for input files.
 * SMP parallelization (blip.parallel) (should improve much soon for many cores, and reduce task/fiber creation cost)

the random generation part now is in tango (tango.math.random).

To install see INSTALL.txt

enjoy

Fawzi Mohamed
