# Taken from: https://tech.davis-hansson.com/p/make/
ifeq ($(origin .RECIPEPREFIX), undefined)
	$(error This Make does not support .RECIPEPREFIX. Please use GNU Make 4.0 or later)
endif

.RECIPEPREFIX = >

hexrun.com: hexrun.asm
> fasm hexrun.asm hexrun.com

run-qemu: hexrun.com
> qemu-system-i386 -drive format=raw,file=hexrun.com
.PHONY: run-qemu
