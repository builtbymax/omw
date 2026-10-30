DEV_DIR := /Library/Developer/CommandLineTools/Library/Developer
# With only the Command Line Tools installed, SwiftPM can't find swift-testing on its own.
TEST_FLAGS := $(if $(wildcard $(DEV_DIR)/Frameworks/Testing.framework),\
	-Xswiftc -F$(DEV_DIR)/Frameworks -Xlinker -F$(DEV_DIR)/Frameworks \
	-Xlinker -rpath -Xlinker $(DEV_DIR)/Frameworks -Xlinker -rpath -Xlinker $(DEV_DIR)/usr/lib)

.PHONY: build run install test release clean

build:
	./scripts/bundle.sh

run: build
	-pkill -x omw; while pgrep -x omw >/dev/null; do sleep 0.1; done
	open build/omw.app

install: build
	-pkill -x omw; while pgrep -x omw >/dev/null; do sleep 0.1; done
	rm -rf /Applications/omw.app
	cp -R build/omw.app /Applications/omw.app
	open /Applications/omw.app

test:
	swift test $(TEST_FLAGS)

# make release VERSION=1.0.3 (see scripts/release.sh for the one-time setup)
release:
	./scripts/release.sh $(VERSION)

clean:
	rm -rf .build build
