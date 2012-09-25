#*******************************************************************************************************************
#* Config files                                                                                                    *
#*******************************************************************************************************************
#* File:             .gitignore.d/Makefile                                                                         *
#* Copyright:        (c) 2012 alimonda.com; Emanuele Alimonda                                                      *
#*                   Public Domain                                                                                 *
#*******************************************************************************************************************

# All the repos
REPOS = $(shell vcsh list)

INCLUDEFILES = $(addsuffix .incl, $(REPOS))
EXCLUDEFILES = $(addsuffix .excl, $(REPOS))

# Ensure a good working shell is being used
SHELL = /bin/bash

all: gitignore

gitignore: includedfiles $(REPOS)
	@echo "Creating ignore files..."

includedfiles: $(addsuffix .incl, $(REPOS))
	@echo "Sorting list of repository files..."
	@DUPES="$$(cat *.incl | egrep -v '(^#|^\s*$$)' | sort | uniq -d | wc -l | tr -d ' ')"; \
	      if [ "$$DUPES" -gt 0 ]; then\
	        echo "Found $$DUPES files living in multiple repositories:";\
		cat *.incl | egrep -v '(^#|^\s*$$)' | sort | uniq -d;\
		exit 1;\
	      fi

clean:
	@echo "Cleaning up..."
	-rm -f $(REPOS) $(INCLUDEFILES)

%.incl:
	@echo "Generating list of files for repository $@..."
	( cd && vcsh list-tracked-by $(basename $@) || echo ) > $@

%.excl:
	@echo "Ensuring presence of a list of repository-specific excluded files $@..."
	[[ -f "$@" ]] || touch $@

$(REPOS): %: %.incl _global _local $(INCLUDEFILES) $(EXCLUDEFILES)
	@echo "Generating gitignore for repository $@..."
	( cat _global _local $(EXCLUDEFILES) $(filter-out $<, $(INCLUDEFILES)) $(addsuffix .excl, $@) | egrep -v '(^#|^\s*$$)' && cat $< | sed 's/^/!/' ) > $@

_local:
	[ -e "$@" ] || cp "$@".template "$@"

.PHONY: all gitignore clean

