include $(ARCHDIR)/dmd.rules
include $(ARCHDIR)/osx.inc

DFLAGS_COMP=-gc -debug -version=SuspendOneAtTime -version=mpi -w 
# -version=DetailedLog -version=NoReuse -debug=SafeDeque -debug=TrackQueues -debug=TrackPools -debug=TrackTasks -version=UnserializationTrace -version=SerializationTrace  -debug=TrackFibers -version=NoPLoops -version=TrackRpc -version=TrackBInReadSome version=TrackSocketServer
CFLAGS_COMP=-g
