SDK    := $(shell xcrun --show-sdk-path)
CC     := clang
CFLAGS := -fobjc-arc -Wall -Wextra -mmacosx-version-min=12.0 -isysroot $(SDK)
LFLAGS := -framework Cocoa -framework WebKit
SRCS   := src/main.m src/AppDelegate.m src/MDDocument.m src/SlashMenu.m \
           src/MDSyntaxHighlighter.m src/MDPreview.m
APP    := MarkdownEditor.app
BIN    := $(APP)/Contents/MacOS/MarkdownEditor

.PHONY: build run clean

build: $(BIN) $(APP)/Contents/Info.plist $(APP)/Contents/Resources/AppIcon.icns

$(BIN): $(SRCS)
	@mkdir -p $(APP)/Contents/MacOS
	$(CC) $(CFLAGS) $(LFLAGS) -o $@ $(SRCS)

$(APP)/Contents/Info.plist: Info.plist
	@mkdir -p $(APP)/Contents/Resources
	cp $< $@

$(APP)/Contents/Resources/AppIcon.icns: MarkdownEditor.icns
	cp $< $@

run: build
	open $(APP)

clean:
	rm -rf $(APP)
