include $(ARCHDIR)/dmd.rules
include $(ARCHDIR)/osx.inc

DFLAGS_COMP=-release -O -version=SuspendOneAtTime -version=mpi
# -inline
CFLAGS_COMP=-O3
