include $(ARCHDIR)/dmd.rules
include $(ARCHDIR)/osx.inc

DFLAGS_COMP=-gc -debug -version=SuspendOneAtTime -version=mpi
# -version=DetailedLog -version=NoReuse -debug=SafeDeque -version=TrackQueues -debug=TrackPools -debug=TrackFibers -debug=TrackTasks -version=UnserializationTrace
CFLAGS_COMP=-g
