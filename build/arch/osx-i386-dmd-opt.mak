include $(ARCHDIR)/dmd.rules
include $(ARCHDIR)/osx.inc

DFLAGS_COMP=-release -O -version=SuspendOneAtTime -version=NoFix
# -inline
CFLAGS_COMP=-O3
