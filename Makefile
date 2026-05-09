CONTRIBUTION = "lua-placeholders-$(shell git describe --tags --always).tar.gz"
PACKAGE_DIR = ${CURDIR}
CNF_LINE = -cnf-line shell_escape_commands=git
COMPILE = lualatex --interaction=nonstopmode --shell-restricted $(CNF_LINE)
RM = rm
ifeq ($(OS),Windows_NT)
	RM = del
endif

export TEXINPUTS  := $(PACKAGE_DIR)/tex//:
export LUAINPUTS  := $(PACKAGE_DIR)/scripts//:

TEXMFHOME         := $(HOME)/src/texmf-packaging
export TEXMFHOME

TEST_BUILD_DIR  := $(PACKAGE_DIR)/test/build
TEST_EXPECTED   := $(PACKAGE_DIR)/test/expected/example.txt
EXAMPLE_DIR     := doc/lua-placeholders-example

.PHONY: doc/lua-placeholders-manual.pdf doc/lua-placeholders-example/example.pdf \
        test test-example test-update test-clean

all: build clean

package: $(CONTRIBUTION)

build: doc/lua-placeholders-manual.pdf

clean:
	cd doc && latexmk -c lua-placeholders-manual
	cd doc/lua-placeholders-example && latexmk -c example

clean-all:
	cd doc && latexmk -C lua-placeholders-manual
	cd doc/lua-placeholders-example && latexmk -C example

doc/lua-placeholders-example/example.pdf: doc/lua-placeholders-example/example.tex tex/lua-placeholders.sty $(wildcard scripts/*.lua)
	@echo "Creating example PDF"
	cd doc/lua-placeholders-example && \
	$(COMPILE) example

doc/lua-placeholders-manual.pdf: doc/lua-placeholders-example/example.pdf doc/lua-placeholders-manual.tex tex/lua-placeholders.sty $(wildcard scripts/*.lua)
	@echo "Creating documentation PDF"
	cd doc && \
	$(COMPILE) lua-placeholders-manual && \
	biber lua-placeholders-manual && \
	$(COMPILE) lua-placeholders-manual && \
	$(COMPILE) lua-placeholders-manual

$(CONTRIBUTION): doc/lua-placeholders-manual.pdf clean
	@echo "Creating package tarball"
	tar --transform 's,^\.,lua-placeholders,' \
		--exclude=doc/.latexmkrc \
		-czvf $(CONTRIBUTION) ./README.md ./doc ./scripts ./tex

test: test-example test-tables test-lists test-objects test-complex test-complex-empty

# ---------------------------------------------------------------------------
# Per-type case tests live under test/cases/<name>.tex (with sibling
# <name>-spec.yaml / <name>-payload.yaml).  Same compile + normalise +
# diff pipeline as the rich example test.
# ---------------------------------------------------------------------------
TEST_CASES_DIR := $(PACKAGE_DIR)/test/cases

$(TEST_BUILD_DIR)/tables.pdf: $(TEST_CASES_DIR)/tables.tex \
                              $(TEST_CASES_DIR)/tables-spec.yaml \
                              $(TEST_CASES_DIR)/tables-payload.yaml \
                              tex/lua-placeholders.sty \
                              $(wildcard scripts/*.lua)
	@mkdir -p $(TEST_BUILD_DIR)
	cd $(TEST_CASES_DIR) && \
	  $(COMPILE) -output-directory=$(TEST_BUILD_DIR) tables

$(TEST_BUILD_DIR)/tables.txt: $(TEST_BUILD_DIR)/tables.pdf
	pdftotext -layout $< $@.raw
	sed -E \
	    -e 's|version [^ ]+ written on [0-9]{4}[-/][0-9]{2}[-/][0-9]{2}|version <VERSION> written on <DATE>|' \
	    -e 's|^[[:space:]]+[A-Z][a-z]+ [0-9]{1,2}, [0-9]{4}[[:space:]]*$$|                                  <DATE>|' \
	    -e 's|^[[:space:]]+[0-9]{1,2}(st\|nd\|rd\|th) [A-Z][a-z]+ [0-9]{4}[[:space:]]*$$|                                  <DATE>|' \
	    -e 's|^[[:space:]]+[0-9]{1,2} [a-z]+ [0-9]{4}[[:space:]]*$$|                                  <DATE>|' \
	    $@.raw > $@
	@$(RM) $@.raw

test-tables: $(TEST_BUILD_DIR)/tables.txt
	@if [ ! -f $(PACKAGE_DIR)/test/expected/tables.txt ]; then \
	    echo "No expected file at test/expected/tables.txt."; \
	    echo "Run 'make test-tables-update' once to seed it, then commit."; \
	    exit 1; \
	fi
	@diff -u $(PACKAGE_DIR)/test/expected/tables.txt $< && echo "OK: tables matches"

test-tables-update: $(TEST_BUILD_DIR)/tables.txt
	@mkdir -p $(PACKAGE_DIR)/test/expected
	cp $< $(PACKAGE_DIR)/test/expected/tables.txt
	@echo "Tables expected file updated"

# ---------------------------------------------------------------------------
# Generic per-case rule.  For test/cases/<name>.tex with sibling YAML files,
# defining a make target test-<name> compiles, normalises, and diffs.
# ---------------------------------------------------------------------------
define CASE_template
$$(TEST_BUILD_DIR)/$(1).pdf: $$(TEST_CASES_DIR)/$(1).tex \
                              $$(wildcard $$(TEST_CASES_DIR)/$(1)-*.yaml) \
                              tex/lua-placeholders.sty \
                              $$(wildcard scripts/*.lua)
	@mkdir -p $$(TEST_BUILD_DIR)
	cd $$(TEST_CASES_DIR) && \
	  $$(COMPILE) -output-directory=$$(TEST_BUILD_DIR) $(1)

$$(TEST_BUILD_DIR)/$(1).txt: $$(TEST_BUILD_DIR)/$(1).pdf
	pdftotext -layout $$< $$@.raw
	sed -E \
	    -e 's|version [^ ]+ written on [0-9]{4}[-/][0-9]{2}[-/][0-9]{2}|version <VERSION> written on <DATE>|' \
	    -e 's|^[[:space:]]+[A-Z][a-z]+ [0-9]{1,2}, [0-9]{4}[[:space:]]*$$$$|                                  <DATE>|' \
	    -e 's|^[[:space:]]+[0-9]{1,2}(st\|nd\|rd\|th) [A-Z][a-z]+ [0-9]{4}[[:space:]]*$$$$|                                  <DATE>|' \
	    -e 's|^[[:space:]]+[0-9]{1,2} [a-z]+ [0-9]{4}[[:space:]]*$$$$|                                  <DATE>|' \
	    $$@.raw > $$@
	@$$(RM) $$@.raw

test-$(1): $$(TEST_BUILD_DIR)/$(1).txt
	@if [ ! -f $$(PACKAGE_DIR)/test/expected/$(1).txt ]; then \
	    echo "No expected file at test/expected/$(1).txt."; \
	    echo "Run 'make test-$(1)-update' once to seed it, then commit."; \
	    exit 1; \
	fi
	@diff -u $$(PACKAGE_DIR)/test/expected/$(1).txt $$< && echo "OK: $(1) matches"

test-$(1)-update: $$(TEST_BUILD_DIR)/$(1).txt
	@mkdir -p $$(PACKAGE_DIR)/test/expected
	cp $$< $$(PACKAGE_DIR)/test/expected/$(1).txt
	@echo "$(1) expected file updated"
endef

$(eval $(call CASE_template,lists))
$(eval $(call CASE_template,objects))
$(eval $(call CASE_template,complex))
$(eval $(call CASE_template,complex-empty))

# complex.tex and complex-empty.tex share complex-body.tex; complex-empty
# also reuses complex-spec.yaml (the wildcard captures only complex-empty-*).
$(TEST_BUILD_DIR)/complex.pdf:       $(TEST_CASES_DIR)/complex-body.tex
$(TEST_BUILD_DIR)/complex-empty.pdf: $(TEST_CASES_DIR)/complex-body.tex \
                                     $(TEST_CASES_DIR)/complex-spec.yaml

$(TEST_BUILD_DIR)/example.pdf: $(EXAMPLE_DIR)/example.tex \
                               $(EXAMPLE_DIR)/example.yaml \
                               $(EXAMPLE_DIR)/example-specification.yaml \
                               tex/lua-placeholders.sty \
                               $(wildcard scripts/*.lua)
	@mkdir -p $(TEST_BUILD_DIR)
	cd $(EXAMPLE_DIR) && \
	  $(COMPILE) -output-directory=$(TEST_BUILD_DIR) example

$(TEST_BUILD_DIR)/example.txt: $(TEST_BUILD_DIR)/example.pdf
	pdftotext -layout $< $@.raw
	sed -E \
	    -e 's|version [^ ]+ written on [0-9]{4}[-/][0-9]{2}[-/][0-9]{2}|version <VERSION> written on <DATE>|' \
	    -e 's|^[[:space:]]+[A-Z][a-z]+ [0-9]{1,2}, [0-9]{4}[[:space:]]*$$|                                  <DATE>|' \
	    -e 's|^[[:space:]]+[0-9]{1,2}(st\|nd\|rd\|th) [A-Z][a-z]+ [0-9]{4}[[:space:]]*$$|                                  <DATE>|' \
	    -e 's|^[[:space:]]+[0-9]{1,2} [a-z]+ [0-9]{4}[[:space:]]*$$|                                  <DATE>|' \
	    -e 's|^([[:space:]]+).+\xe2\x8c\xa9.+\xe2\x8c\xaa[[:space:]]*$$|\1<AUTHOR>|' \
	    $@.raw > $@
	@$(RM) $@.raw

test-example: $(TEST_BUILD_DIR)/example.txt
	@if [ ! -f $(TEST_EXPECTED) ]; then \
	    echo "No example file at $(TEST_EXPECTED)."; \
	    echo "Run 'make test-update' once to seed it, then commit."; \
	    exit 1; \
	fi
	@diff -u $(TEST_EXPECTED) $< && echo "OK: example matches"

test-update: $(TEST_BUILD_DIR)/example.txt
	@mkdir -p $(dir $(TEST_EXPECTED))
	cp $< $(TEST_EXPECTED)
	@echo "Example file updated: $(TEST_EXPECTED)"
	@echo "Inspect with: git diff $(TEST_EXPECTED)"

test-clean:
	$(RM) -rf $(TEST_BUILD_DIR)
