include $(ARCHDIR)/dmd.rules
include $(ARCHDIR)/osx.inc

DFLAGS_COMP=-gc -debug -version=SuspendOneAtTime -version=mpi
# -version=DetailedLog -version=NoReuse -debug=SafeDeque -version=TrackQueues
CFLAGS_COMP=-g
