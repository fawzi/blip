include $(ARCHDIR)/dmd.rules
include $(ARCHDIR)/osx.inc

DFLAGS_COMP=-gc -debug -version=SuspendOneAtTime -version=mpi
# -version=DetailedLog -version=NoReuse -debug=SafeDeque -debug=TrackQueues -debug=TrackPools -debug=TrackTasks -version=UnserializationTrace -debug=TrackFibers -version=NoPLoops
CFLAGS_COMP=-g
