include $(ARCHDIR)/dmd.rules
include $(ARCHDIR)/osx.inc

DFLAGS_COMP=-gc -debug -version=SuspendOneAtTime -version=mpi -w # -version=TrackRpc -version=TrackBInReadSome -version=StcpTextualSerialization -version=TrackSocketServer -version=SerializationTrace -version=TrackBInReadSome -version=UnserializationTrace
# -version=DetailedLog -version=NoReuse -debug=SafeDeque -debug=TrackQueues -debug=TrackPools -debug=TrackTasks -version=UnserializationTrace -version=SerializationTrace  -debug=TrackFibers -version=NoPLoops -version=TrackRpc -version=TrackBInReadSome -version=TrackSocketServer -version=StcpTextualSerialization
CFLAGS_COMP=-g
