DEV_DIR := /Library/Developer/CommandLineTools/Library/Developer
# With only the Command Line Tools installed, SwiftPM can't find swift-testing on its own.
TEST_FLAGS := $(if $(wildcard $(DEV_DIR)/Frameworks/Testing.framework),\
	-Xswiftc -F$(DEV_DIR)/Frameworks -Xlinker -F$(DEV_DIR)/Frameworks \
	-Xlinker -rpath -Xlinker $(DEV_DIR)/Frameworks -Xlinker -rpath -Xlinker $(DEV_DIR)/usr/lib)

.PHONY: build run install test clean

build:
	./scripts/bundle.sh

run: build
	-pkill -x omw
	open build/omw.app

install: build
	-pkill -x omw
	rm -rf /Applications/omw.app
	cp -R build/omw.app /Applications/omw.app
	open /Applications/omw.app

test:
	swift test $(TEST_FLAGS)

clean:
	rm -rf .build build
