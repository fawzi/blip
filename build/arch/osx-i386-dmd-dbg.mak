include $(ARCHDIR)/dmd.rules
include $(ARCHDIR)/osx.inc

DFLAGS_COMP=-gc -debug -version=SuspendOneAtTime -version=mpi -w -version=NoLog # -version=TrackRpc -version=TrackSocketServer -version=StcpNoCache -version=UnserializationTrace -version=TrackEvents # -version=TrackBInReadSome -debug=TrackQueues -version=DetailedLog # -version=StcpTextualSerialization -version=SerializationTrace -version=TrackBInReadSome -version=UnserializationTrace
# -version=DetailedLog -version=NoReuse -debug=SafeDeque -debug=TrackQueues -debug=TrackPools -debug=TrackTasks -version=UnserializationTrace -version=SerializationTrace  -debug=TrackFibers -version=NoPLoops -version=TrackRpc -version=TrackBInReadSome -version=TrackSocketServer -version=StcpTextualSerialization -version=StcpNoCache -version=TrackEvents -version=SocketEcho -version=
CFLAGS_COMP=-g
