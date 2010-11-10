include $(ARCHDIR)/ldc.rules
include $(ARCHDIR)/linux.inc

DFLAGS_COMP=-inline -release -O3 -g -disable-d-passes
CFLAGS_COMP=-O2
