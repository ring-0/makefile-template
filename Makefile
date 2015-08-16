################################ .vars - build   ################################
# set MAKEFLAGS, if -p is used, consider http://savannah.gnu.org/bugs/?20501
MAKEFLAGS += -rR --no-print-directory
$(eval SHELL := $(shell which bash))
.ONESHELL:
# disable built-in rules
.SUFFIXES:

BUILD 			:= 
PROJECT_LIST	:= 
BUILD_ORDER		:=
BUILD_TARGETS	:= 

################################ .util           ################################
define string_is_equal 
	$(and $(findstring $(1),$(2)),$(findstring $(2),$(1)),1)
endef


################################ .functions      ################################
define add_project
	$(eval PROJECT_LIST += $(1))
endef

# FOREACH:	Run find Makefile in relative path, remove "./" and sort
define recursive_project_list 
	$(foreach	cmk, \
				$(shell find $(1) -maxdepth 2 -mindepth 2 -name Makefile -printf "%h\n" | sed 's!^\./!!' | sort), \
				$(call recursive_project_list, $(cmk))  $(call add_project,$(cmk)))
endef


# FOREACH:	BUILD_ORDER entry, check if $(1) exists
# IF:		$(1) not found, add it to the queue
define add_build_order 
	$(eval entry_found := 0)
	$(foreach	entry,			\
				$(BUILD_ORDER),	\
					$(eval match = $(call string_is_equal,$(1),$(entry)))
					$(if $(match),$(eval entry_found := 1)))

	$(if	$(findstring $(entry_found),0), \
			$(eval BUILD_ORDER := $(value BUILD_ORDER) $(1)))
endef


# EVAL:		Load defaults
# EVAL:		Load the makefile to build
# IF:		Recursive dependency
# FOREACH:	Dependency, add a buildqueue entry
# EVAL:		Remove dependency track
# CALL:		Add the makefile to buildqueue
define create_makefile_dep
	$(COMMENT info create_makefile_dep |$(1)|)
	$(eval include Make.defaults)
	$(eval include $(1)/Makefile)
	$(eval PROJECT_ID := $(subst /,-,$(PROJECT_ID)))

	$(if	$(RECURSION_PROTECTOR_$(1)),
			$(error "Recursive dependencies for $(1)"),
			$(eval RECURSION_PROTECTOR_$(1) := 1))


	$(foreach	dep,				\
				$(DEPENDENCIES),	\
				$(call create_makefile_dep,$(dep))
				$(call add_build_order,$(dep)))

	$(eval RECURSION_PROTECTOR_$(1) := )

	$(call add_build_order,$(1))
endef


# FOREACH:	Resolve dependencies for each project
define recursive_build_order
	$(foreach	project,			\
				$(PROJECT_LIST),	\
				$(call create_makefile_dep,$(project)))
endef


# EVAL:		Load make definition file - can be overwritten by sub-directory Makefile
# EVAL:		Load make default file    - WILL be overwritten by sub-directory Makefile
# EVAL:		Load the sub-directory Makefile
# EVAL:		Generate the template name
# EVAL:		Generate the actual rules
define create_makefile_rules
	$(eval include Make.defaults)
	$(eval include $(1)/Makefile)
	$(eval PROJECT_ID := $(subst /,-,$(PROJECT_ID)))
	$(eval template := $(join $(PROJECT_TYPE), _TEMPLATE))

	$(COMMENT info create_makefile_rules $(PROJECT_ID) ----> $(template))
	$(eval $(call $(template),$(PROJECT_ID),$(1)))
endef


# FOREACH:	Create the Makefile rules and add the target
define create_all_rules
	$(foreach	project,		\
				$(BUILD_ORDER),	\
				$(call create_makefile_rules,$(project)) $(eval BUILD_TARGETS += $(subst /,-,$(project))))
endef

############################### .main 

# ------------- .vars
ifndef mode
mode := debug
endif

MODE := $(mode)

ifneq ($(MAKECMDGOALS),clean)
ifneq ($(MAKECMDGOALS),)
SINGLE_PROJECT := $(subst -,/,$(MAKECMDGOALS))
SINGLE_TARGET  := $(subst /,-,$(MAKECMDGOALS))
endif
endif


ifdef clean
SINGLE_PROJECT := $(subst -,/,$(clean))
SINGLE_TARGET  := $(subst /,-,$(clean))
MAKECMDGOALS   := clean
endif

BUILD			:= build/$(MODE)
SANDBOX			:= sandbox/$(MODE)
SANDBOX_DIRS	:= $(addprefix $(SANDBOX)/,bin lib)

include Make.templates


# ------------- .static rules
.PHONY: all clean sandbox project_list filter_list build_order project_rules build_targets

all: sandbox build_targets

clean: build_targets

.DEFAULT_GOAL: all

# sandbox preparation
sandbox:		$(SANDBOX_DIRS)

$(SANDBOX_DIRS):
	@echo "SANDBOX  $@"
	@mkdir -p $@


# ------------- .execution

# Step 1: create project list
$(call recursive_project_list, .)

# Step 2: filter project list
ifdef SINGLE_PROJECT
# build only a single project AND dependencies
$(eval PROJECT_LIST := $(SINGLE_PROJECT))
$(SINGLE_PROJECT) $(SINGLE_TARGET): sandbox build_targets
endif

# Step 3: create build order of projects
$(eval $(call recursive_build_order))
#$(info BUILD_ORDER= $(BUILD_ORDER))

# Step 4: create all rules for all projects
$(eval $(call create_all_rules))

# Step 5: if clean is specified, turn all BUILD_TARGETS into '%_clean' 
ifeq ($(MAKECMDGOALS),clean)
BUILD_TARGETS := $(addsuffix _clean,$(BUILD_TARGETS))
endif

# Step 6: build em all
$(info BUILD_TARGETS: $(BUILD_TARGETS))
# Step 7: if we have a single target, remove it from the BUILD_TARGETS to avoid recursion
ifdef SINGLE_TARGET
BUILD_TARGETS := $(filter-out $(SINGLE_TARGET),$(BUILD_TARGETS))
endif
$(info ==============================================)
build_targets:	$(BUILD_TARGETS) 

