APP_NAME = vView

all: build

build:
	valac --pkg libadwaita-1 main.vala -o $(APP_NAME)

run: build
	./$(APP_NAME)

install:
	./install.sh install

uninstall:
	./install.sh uninstall

clean:
	rm -f $(APP_NAME)

.PHONY: all build run install uninstall clean
