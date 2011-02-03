---
title: testNArrayPerf
layout: Default
---
Timings for testNArrayPerf.d
============================

This tests the performance of various loops that are used in NArray and how much worse is the "naive" N-dimensional looping

        for (int i=0;i < ndim;i++)
        for (int j=0;j < ndim;j++)
        for (int k=0;k < ndim;k++){
            resNArr[i]=resNArr[i]+d1[i,j,k]*d2[0,j,k];
        }

t9 with respect to loops that use global reduction operations on NArrays (t10-t12), implementation in simplified struct/arrays that could represent possible implementation strategies of NArray assuming various compiler optimizations (t2-t8), and with respect to the "optimal" implementation that knows that everything is contiguous and takes advantage of that to do a single loop (tref).

Timings and timings wrt. tref are shown for various compilers, to see how bad the situation is without optimization, and how much it improves with compiler optimizations.

    osx 10.5.7, Intel Core 2 Duo 1.83 GHz 2GB RAM
    dmd 1.045
    ldc 6766485fb584+ tip (07.07.09) llvm r74519

    dmd -g
    tref: 0.06 t1:0.41 t2:0.54 t6:0.16 t7:0.20 t8:0.15 t9:1.13 t10:0.21, t11:0.06 t12:0.11 t13:0.08 t14:0.08
    tref: 1.00 t1:6.35 t2:8.39 t6:2.49 t7:3.09 t8:2.41 t9:17.65 t10:3.22, t11:1.04, t12:1.65 t13:1.35 t14:1.36
    ldc -g
    tref: 0.07 t1:0.53 t2:0.65 t6:0.14 t7:0.17 t8:0.14 t9:1.46 t10:0.16, t11:0.07 t12:0.11 t13:0.08 t14:0.08
    tref: 1.00 t1:6.91 t2:8.48 t6:1.89 t7:2.25 t8:1.90 t9:19.18 t10:2.06, t11:0.98, t12:1.43 t13:1.16 t14:1.16
    dmd -release -inline -O
    tref: 0.05 t1:0.12 t2:0.11 t6:0.08 t7:0.08 t8:0.09 t9:0.37 t10:0.05, t11:0.05 t12:0.08 t13:0.05 t14:0.05
    tref: 1.00 t1:2.16 t2:1.96 t6:1.53 t7:1.54 t8:1.75 t9:6.71 t10:1.03, t11:0.96, t12:1.50 t13:0.98 t14:0.98
    ldc -release -inline -O3
    tref: 0.02 t1:0.08 t2:0.07 t6:0.05 t7:0.05 t8:0.05 t9:0.10 t10:0.05, t11:0.03 t12:0.05 t13:0.02 t14:0.02
    tref: 1.00 t1:3.12 t2:2.69 t6:2.18 t7:2.18 t8:2.14 t9:3.76 t10:1.99, t11:1.33, t12:2.00 t13:0.93 t14:0.93

    tref: contiguous pointer loop
    t1: index loop on struct
    t2: index loop on class (const strides)
    t6: index op floated to outer loops on struct (smart compiler)
    t7: index op floated to outer loops on class (smart compiler)
    t8: index op floated to outer loops and removal of multiplication on struct (smart compiler)
    t9: index loop on NArray
    t10: loop+binaryOp on NArray
    t11: loop+mixin pLoopPtr on NArray
    t12: loop+mixin pLoopIdx on NArray
    t13: index op floated to outer loops and removal of multiplication on struct without *T.sizeof(smart compiler)
    t14: index op floated to outer loops and removal of multiplication on struct with (no native,w var )

t3-t5 were using Multiarray and were in general 100s times slower, so I did not time them and are not shown

The global arrays op are obviously better and are written in such a way that they could be rewritten using blocking techniques or multiple threading without changing the calling code, even if at the moment they use a quite straightforward implementation, and offer always a fair timing; within 1-2, at most 3 times the optimized version at the same level of compiler optimization, and within 10 times (normally less) of the most optimized reference implementation.

t9 without optimization is much slower (up to almost 20 times of the optimized implementation at the same level and up to 70 times of the best optimized implementation

Without optimizations ldc is slower, but with all optimization on the situation is reversed, with ldc being much faster, and accomplishing the feat of making t9 just 3.76 times slower than the most optimized version, and the global array ops within 2 times the optimized version.

With dmd t9 is 6.7 times the optimized version and the global ops are also withing 2 times the optimized version, but the optimized version if twice as slow as the ldc one.

Obviously I would like that the compiler make all overhead of the abstraction go away, but still I think that this is very usable, and even t9 is (for example) still more then 100s times faster than numpy indexing in python.
