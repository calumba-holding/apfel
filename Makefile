PREFIX ?= /usr/local
BINARY = apfel

.PHONY: build install uninstall clean version-bump

build:
	swift build -c release

install: build
	install -d $(PREFIX)/bin
	install .build/release/$(BINARY) $(PREFIX)/bin/$(BINARY)

uninstall:
	rm -f $(PREFIX)/bin/$(BINARY)

clean:
	swift package clean

version-bump:
	@v=$$(grep 'let version = ' Sources/main.swift | head -1 | sed 's/.*"\(.*\)"/\1/'); \
	major=$$(echo $$v | cut -d. -f1); \
	minor=$$(echo $$v | cut -d. -f2); \
	patch=$$(echo $$v | cut -d. -f3); \
	new="$$major.$$minor.$$((patch+1))"; \
	sed -i '' "s/let version = \"$$v\"/let version = \"$$new\"/" Sources/main.swift; \
	echo "$$v → $$new"
