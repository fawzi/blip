include $(ARCHDIR)/dmd.rules
include $(ARCHDIR)/osx.inc

DFLAGS_COMP=-gc -debug -version=SuspendOneAtTime -w # -version=TrackCollections -debug=TrackQueues -version=DetailedLog  #-version=noHwloc -version=noReuse   -debug=TrackFibers
CFLAGS_COMP=-g
