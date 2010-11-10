include $(ARCHDIR)/ldc.rules
include $(ARCHDIR)/linux.inc

DFLAGS_COMP=-g -w -d -unittest -d-debug=UnitTest -disable-d-passes
CFLAGS_COMP=-g
