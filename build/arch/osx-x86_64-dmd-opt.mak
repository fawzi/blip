include $(ARCHDIR)/dmd.rules
include $(ARCHDIR)/osx.inc

DFLAGS_COMP=-release -O -gc -version=SuspendOneAtTime -version=NoFix
# -inline
CFLAGS_COMP=-O3
