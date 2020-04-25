# Native Cross Compiler

To emit a cross compiler, we need to be able to emit code to both platforms,

## Stdlib

There is some ways to deal with the stdlib, but ideally we shouldn't mix them, so there is just two options.

As dynamic libs would be using the host one, I choose to also use the host stdlib

### Host stdlib

Can be faster overall as you don't need an target stdlib to x86, but that would require essentially rewriting the Makefile.

- host stdlib to run on host
- different than the target compiler on this

### Target stdlib

- mimicks the target platform better
- needs to build the native stdlib two times(host and target)

## Dynamic Libs

Ideally we would want to use the target stdlibs to better mimick the target, but this isn't possible without emulation, and a "target like host dyn lib" it's a lot harder to generate and not always will work.

- TODO: Is that a problem?

## TODO

### ocamlc.host vs ocamlc.target

Does it actually matter at all?

### Reduce build time using host data

It should be possible to reduce build time probably consideraly by copying files from \$OCAML_HOST/compilerlibs, as both should emit the same file, it shouldn't be needed to build it two times.
