APP_NAME = vView

all: build

build:
	valac --pkg libadwaita-1 --pkg gdk-pixbuf-2.0 --pkg cairo --pkg pango --pkg pangocairo -X -Wno-deprecated-declarations -X -lm main.vala -o $(APP_NAME)

run: build
	./$(APP_NAME)

install:
	./install.sh install

install-lite:
	./install.sh install-lite

uninstall:
	./install.sh uninstall

clean:
	rm -f $(APP_NAME)

.PHONY: all build run install install-lite uninstall clean
