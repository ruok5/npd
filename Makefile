PREFIX     ?= $(HOME)/bin
BIN        := $(PREFIX)/npd
PLIST      := $(HOME)/Library/LaunchAgents/org.fyvm.npd.plist
LABEL      := org.fyvm.npd
LOG        := $(HOME)/Library/Logs/npd.log

.PHONY: build install uninstall reload run tail clean

build: npd

npd: npd.swift
	swiftc -O npd.swift -o npd

install: build
	mkdir -p $(PREFIX) $(HOME)/Library/LaunchAgents $(HOME)/Library/Logs
	cp -f npd $(BIN)
	sed 's|__HOME__|$(HOME)|g' org.fyvm.npd.plist.in > $(PLIST)
	-launchctl bootout gui/$(shell id -u)/$(LABEL) 2>/dev/null
	launchctl bootstrap gui/$(shell id -u) $(PLIST)
	launchctl kickstart -k gui/$(shell id -u)/$(LABEL)

uninstall:
	-launchctl bootout gui/$(shell id -u)/$(LABEL)
	rm -f $(PLIST) $(BIN)

reload:
	launchctl kickstart -k gui/$(shell id -u)/$(LABEL)

run: build
	./npd

tail:
	tail -F $(LOG)

clean:
	rm -f npd
