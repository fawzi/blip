include $(ARCHDIR)/dmd.rules
include $(ARCHDIR)/osx.inc

DFLAGS_COMP=-gc -debug -version=SuspendOneAtTime -version=mpi -w
CFLAGS_COMP=-g
