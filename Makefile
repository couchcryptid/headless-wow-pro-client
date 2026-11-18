PREFIX ?= $(HOME)/.local

.PHONY: install uninstall

install:
	mkdir -p "$(PREFIX)/bin"
	ln -sf "$(CURDIR)/bin/hwc" "$(PREFIX)/bin/hwc"

# Remove the link only if it points at this repo's bin/hwc.
uninstall:
	@if [ "$$(readlink "$(PREFIX)/bin/hwc")" = "$(CURDIR)/bin/hwc" ]; then rm -f "$(PREFIX)/bin/hwc"; fi
