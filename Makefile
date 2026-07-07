SDK    := $(shell xcrun --show-sdk-path)
CC     := clang
CFLAGS := -fobjc-arc -Wall -Wextra -mmacosx-version-min=12.0 -isysroot $(SDK)
LFLAGS := -framework Cocoa -framework WebKit -framework UniformTypeIdentifiers
SRCS   := src/main.m src/AppDelegate.m src/MDDocument.m src/SlashMenu.m \
           src/MDSyntaxHighlighter.m src/MDPreview.m src/MDUpdateChecker.m \
           src/MDSchemeHandler.m src/MDTextView.m src/MDFileSearch.m
APP    := MarkdownEditor.app
BIN    := $(APP)/Contents/MacOS/MarkdownEditor

.PHONY: build run clean release

VERSION := $(shell /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist)

build: $(BIN) $(APP)/Contents/Info.plist $(APP)/Contents/Resources/AppIcon.icns \
       $(APP)/Contents/Resources/mermaid.min.js.z \
       $(APP)/Contents/Resources/highlight.min.js.z

$(BIN): $(SRCS)
	@mkdir -p $(APP)/Contents/MacOS
	$(CC) $(CFLAGS) $(LFLAGS) -o $@ $(SRCS)

$(APP)/Contents/Info.plist: Info.plist
	@mkdir -p $(APP)/Contents/Resources
	cp $< $@

$(APP)/Contents/Resources/AppIcon.icns: MarkdownEditor.icns
	cp $< $@

# JS engines ship DEFLATE-compressed (~4:1); MDPreview inflates at first use
$(APP)/Contents/Resources/%.js.z: resources/%.js
	@mkdir -p $(APP)/Contents/Resources
	python3 -c 'import zlib;c=zlib.compressobj(9,zlib.DEFLATED,-15);d=open("$<","rb").read();open("$@","wb").write(c.compress(d)+c.flush())'

run: build
	open $(APP)

clean:
	rm -rf $(APP)

# Publish the current version as a GitHub release. Installed apps discover it
# via their daily check of /releases/latest. Bump CFBundleShortVersionString
# in Info.plist (and CFBundleVersion), commit, then run `make release`.
release:
	@git diff --quiet && git diff --cached --quiet || \
		{ echo "error: working tree dirty — commit first"; exit 1; }
	@git rev-parse "v$(VERSION)" >/dev/null 2>&1 && \
		{ echo "error: tag v$(VERSION) already exists — bump Info.plist first"; exit 1; } || true
	$(MAKE) clean build
	ditto -c -k --keepParent $(APP) MarkdownEditor-$(VERSION).zip
	git tag "v$(VERSION)"
	git push origin main "v$(VERSION)"
	gh release create "v$(VERSION)" MarkdownEditor-$(VERSION).zip \
		--title "v$(VERSION)" --generate-notes
	rm -f MarkdownEditor-$(VERSION).zip
