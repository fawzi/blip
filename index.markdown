---
title: Blip
layout: Default
---

Welcome to Blip
===============

a library that focuses on basic things that can be useful for scientific HPC programs.
It offers:

 * N-dimensional arrays (blip.narray) that have a nice interface to lapack (that leverages the wrappers of baxissimo)
 * 2,3 and 4D vectors, matrixes and quaternions from the omg library of h3r3tic
 * random and combinatorial(extensive) testing framework (blip.rtest), parallel
 * serialization (blip.serialization) that supports both json format, that can be used also for input files and an efficient binary representation
 * SMP parallelization (blip.parallel.smp) a numa aware very flexible framework
 * MPI parallelization built on the top of mpi, but abstracting it away (so that a pure tcp implementation is possible), for tightly coupled parallelization
 * a Distribued Objects framework that does rpc via proxies (blip.parallel.rpc)
 * a simple socket library that can be used to connect external programs, even if written in fortran or C (for a weak parallel coupling)
 * a coherent and efficient io abstraction

The source is available at github

 * browse: http://github.com/fawzi/blip

 * install: `git clone git://github.com/fawzi/blip.git` (see GettingStarted for the details)

 * requires either the latest trunk of [tango](http://dsource.org/projects/tango/) or an older special version (until next release)

News
----

 * 2010-11-17 announcing blip 0.5

 * 2010-10-22 smp parallelization interface has stabilized

 * 2010-10-22 native (non tango based) input handling is used for sockets, output is pretty much stable.

 * 2010-10-22 libev is used for socket io and sleep

 * 2010-10-22 ip6 socket implementation is available on *nix
 
 * 2010-10-22 rpc parallelization is also working

Starting Points
---------------

 * AboutBlip --  some background on the library

 * GettingStarted -- how to start using the library

 * BlipOverview -- an overview of the main features of blip

 * ParallelizationConcepts --the concepts behind the parallelization of blip

 * [wiki:NArrayPerformace] -- indexing and looping performance with 3D arrays

 * A talk about the random testing framework that is part of blip http://petermodzelewski.blogspot.com/2009/02/tango-conference-2008-rolling-dice.html
 
 * [wiki:HowToD], how to set up a D environment on linux x86_64

 * LicenseContributing -- license of blip, and how to contribute to it
