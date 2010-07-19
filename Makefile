# Makefile that builds the blip library
#
# * Targets
# all:       (the default) builds lib
# lib:       should build the optimized blip library
# newFiles:  updates the module list when new d diles are added
#            either this or clean-all or distclean have to be called to compile the new files
# clean:     cleans the buildobjects
# clean-all: removes the current object directory
# distclean: removes all object directories 
#
# * Compiler
# By default make tries to guess the compiler to use. If you have several compilers you can 
# select the compiler to use by setting the DC environment variable or by setting DC in the
# make invocation
#
# * Version
# By default the optimized version will be built, you can build other versions by passing
# VERSION=dbg or VERSION=tst (for example) to the make invocation
# 
# * Architecture
# The architecture is identified by what is returned by blip/build/tools/archName.sh
# (which is os-machine) togheter with the compiler and version. This forms a quadruplet
# os-machine-compiler-version that is called IDENT.
# It is used to generate the object directory, and to get the architecture dependent flags
# and rules.
# This is done by reading the file blip/build/arch/$(IDENT).mak
# It is possible to override IDENT by passing IDENT=mySpecialIdent to the make invocation.
# In this case the version flag is disregarded. 
# For problems with the flags (or if you want to define a new special build setting)
# normally you should edit the blip/build/arch/$(IDENT).mak file.
#
# * Other important variables
#  DFLAGS_ADD: adds the given D flags
#  CFLAGS_ADD: adds the given C flags
#  DFLAGS: as environment variable is not changed
#  CFLAGS: adds the given C flags
#  EXTRA_LIBS: add the given link flags (to link tango user for example)
#  MOD_OMG: set it to none to not compile xf.omg into the blip library
#
# apache 2.0 license, © 2009 Fawzi Mohamed

BLIP_HOME=$(PWD)
TOOLDIR=$(BLIP_HOME)/build/tools
VERSION=opt
DC=$(shell $(TOOLDIR)/guessCompiler.sh --path)
DC_SHORT=$(shell $(TOOLDIR)/guessCompiler.sh $(DC))
IDENT=$(shell $(TOOLDIR)/archName.sh)-$(DC_SHORT)-$(VERSION)

SRCDIR=$(BLIP_HOME)
TESTS_DIR=$(BLIP_HOME)/tests
EXE_DIR=$(BLIP_HOME)/exe
OBJDIRBASE=$(BLIP_HOME)
OBJDIR=$(OBJDIRBASE)/blipBuild/objs-$(IDENT)
ARCHDIR=$(BLIP_HOME)/build/arch
EXCLUDEPAT_ALL=$(EXCLUDEPAT_OS) *objs-*
ARCHFILE=$(ARCHDIR)/$(IDENT).mak
MAKEFILE=$(BLIP_HOME)/Makefile
DFLAGS_MAIN=-I$(BLIP_HOME)
WHAT=_lib

LIB=libblip.$(LIB_EXT)
INSTALL_LIB=libblip-$(shell $(TOOLDIR)/getCompVers.sh $(IDENT)).$(LIB_EXT)

all: $(OBJDIR)/MODULES.inc $(OBJDIR)/intermediate.rule
	@mkdir -p $(OBJDIR)
	$(MAKE) -f $(MAKEFILE) -C $(OBJDIR) TANGO_HOME="$(TANGO_HOME)"  BLIP_HOME="$(BLIP_HOME)" IDENT="$(IDENT)" DC="$(DC)" WHAT="_tests" build

include $(ARCHFILE)
ifeq ($(shell if [ -e "$(OBJDIR)/MODULES.inc" ]; then echo 1; fi;),1)
include $(OBJDIR)/MODULES.inc
endif

vpath %d $(SRCDIR)
vpath %di $(SRCDIR)

MODULES=$(MOD_BLIP) $(MOD_GOBO) $(MOD_OMG)

EXCLUDE_DEP_ALL=$(EXCLUDE_DEP_COMP) object.di ^tango.*

OBJS=$(MODULES:%=%.$(OBJ_EXT))

TESTS=testTextParsing testRTest testSerial testNArrayPerf testNuma testHwloc testSmp testBlip testNArray
.PHONY: _genDeps newFiles build clean distclean _tests tests lib $(TESTS)

lib: $(OBJDIR)/MODULES.inc $(OBJDIR)/intermediate.rule
	@mkdir -p $(OBJDIR)
	$(MAKE) -f $(MAKEFILE) -C $(OBJDIR) TANGO_HOME="$(TANGO_HOME)"  BLIP_HOME="$(BLIP_HOME)" IDENT="$(IDENT)" DC="$(DC)" WHAT="_lib" build

allVersions:	$(OBJDIR)/MODULES.inc $(OBJDIR)/intermediate.rule
	@mkdir -p $(OBJDIR)
	$(MAKE) -f $(MAKEFILE) -C $(OBJDIR) TANGO_HOME="$(TANGO_HOME)" BLIP_HOME="$(BLIP_HOME)" VERSION=opt DC="$(DC)" all
	$(MAKE) -f $(MAKEFILE) -C $(OBJDIR) TANGO_HOME="$(TANGO_HOME)" BLIP_HOME="$(BLIP_HOME)" VERSION=tst DC="$(DC)" all
	$(MAKE) -f $(MAKEFILE) -C $(OBJDIR) TANGO_HOME="$(TANGO_HOME)" BLIP_HOME="$(BLIP_HOME)" VERSION=dbg DC="$(DC)" all

build: $(OBJDIR)/MODULES.inc $(OBJDIR)/intermediate.rule
	@mkdir -p $(OBJDIR)
	@echo "XXX using the architecture file $(ARCHFILE)"
	$(MAKE) -f $(MAKEFILE) -C $(OBJDIR) TANGO_HOME="$(TANGO_HOME)" BLIP_HOME="$(BLIP_HOME)" IDENT="$(IDENT)" DC="$(DC)" _genDeps
	$(MAKE) -f $(MAKEFILE) -C $(OBJDIR) TANGO_HOME="$(TANGO_HOME)" BLIP_HOME="$(BLIP_HOME)" IDENT="$(IDENT)" DC="$(DC)" $(WHAT)

tests:
	@mkdir -p $(OBJDIR)
	$(MAKE) -f $(MAKEFILE) -C $(OBJDIR) TANGO_HOME="$(TANGO_HOME)"  BLIP_HOME="$(BLIP_HOME)" IDENT="$(IDENT)" DC="$(DC)" WHAT="_tests" build

_genDeps: $(MODULES:%=%.dep)

_lib:$(LIB) $(BLIP_HOME)/libs/$(INSTALL_LIB)

$(LIB):  $(OBJS)
	rm -f $@
	$(mkLib) $@ $(OBJS)
	$(ranlib) $@

$(BLIP_HOME)/libs/$(INSTALL_LIB): $(LIB)
	mkdir -p $(BLIP_HOME)/libs
	cp $(OBJDIR)/$(LIB) $(BLIP_HOME)/libs/$(INSTALL_LIB)

$(TESTS:%=$(OBJDIR)/%.d):$(TESTS:%=$(TESTS_DIR)/%.d)
	cp $(TESTS_DIR)/$(shell basename $@) $@

$(TESTS:%=_%): _% : $(OBJDIR)/%.$(OBJ_EXT) $(LIB)
	$(DC) $(OUT_NAME)$@ $(@:_%=$(OBJDIR)/%.$(OBJ_EXT)) $(LIB_DIR). $(LIB_LINK)blip $(EXTRA_LIBS)
	mkdir -p $(EXE_DIR)
	cp $@ $(EXE_DIR)/$(@:_%=%)

$(TESTS):
	@mkdir -p $(OBJDIR)
	$(MAKE) -f $(MAKEFILE) -C $(OBJDIR) TANGO_HOME="$(TANGO_HOME)"  BLIP_HOME="$(BLIP_HOME)" IDENT="$(IDENT)" DC="$(DC)" WHAT="_$@" build

_tests: $(TESTS:%=_%)

$(OBJDIR)/MODULES.inc:
	@mkdir -p $(OBJDIR)
	$(TOOLDIR)/mkMods.sh --out-var MOD_BLIP $(SRCDIR)/blip $(EXCLUDEPAT_ALL) > $(OBJDIR)/MODULES.inc
	$(TOOLDIR)/mkMods.sh --out-var MOD_GOBO $(SRCDIR)/gobo $(EXCLUDEPAT_ALL) >> $(OBJDIR)/MODULES.inc
	$(TOOLDIR)/mkMods.sh --out-var MOD_OMG $(SRCDIR)/xf/omg $(EXCLUDEPAT_ALL) >> $(OBJDIR)/MODULES.inc

$(OBJDIR)/intermediate.rule:
	@mkdir -p $(OBJDIR)
	$(TOOLDIR)/mkIntermediate.sh $(SRCDIR)/blip $(EXCLUDEPAT_ALL) > $(OBJDIR)/intermediate.rule
	$(TOOLDIR)/mkIntermediate.sh $(SRCDIR)/gobo $(EXCLUDEPAT_ALL) >> $(OBJDIR)/intermediate.rule
	$(TOOLDIR)/mkIntermediate.sh $(SRCDIR)/xf $(EXCLUDEPAT_ALL) >> $(OBJDIR)/intermediate.rule

newFiles:
	@mkdir -p $(OBJDIR)
	@echo regenerating MODULES.inc and intermediate.rule
	$(TOOLDIR)/mkMods.sh --out-var MOD_BLIP $(SRCDIR)/blip $(EXCLUDEPAT_ALL) > $(OBJDIR)/MODULES.inc
	$(TOOLDIR)/mkMods.sh --out-var MOD_GOBO $(SRCDIR)/gobo $(EXCLUDEPAT_ALL) >> $(OBJDIR)/MODULES.inc
	$(TOOLDIR)/mkMods.sh --out-var MOD_OMG $(SRCDIR)/xf/omg $(EXCLUDEPAT_ALL) >> $(OBJDIR)/MODULES.inc
	$(TOOLDIR)/mkIntermediate.sh $(SRCDIR) $(EXCLUDEPAT_ALL) > $(OBJDIR)/intermediate.rule

clean:
	rm -f $(OBJDIR)/*.$(OBJ_EXT)
	rm -f $(OBJDIR)/*.dep

clean-all:
	rm -rf $(OBJDIR)

distclean:
	rm -rf $(OBJDIRBASE)/blipBuild/objs-*
	rm -rf $(EXE_DIR)
	rm -rf $(BASE_DIR)/libs

ifeq ($(shell if [ -e "$(OBJDIR)/intermediate.rule" ]; then echo 1; fi;),1)
include $(OBJDIR)/intermediate.rule
endif
ifneq ($(strip $(wildcard *.dep)),)
include $(wildcard *.dep)
endif
