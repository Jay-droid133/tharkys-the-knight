PROJECT_NAME = NuevoJuego

all: build

build:
	sjasmplus code/main.asm --sym=$(PROJECT_NAME).sym --sld=$(PROJECT_NAME).sld --lst=$(PROJECT_NAME).lst --msg=war

clean:
	del /Q *.tap *.sna *.sym *.sld *.lst 2>nul
