alias b := build
alias e := example
alias es := examples

build:
	zig build

examples: build
	find ./examples/ -iname '*.jix' -exec ./zig-out/bin/jix compile -r {} \;
	
example EXAMPLE: build
	./zig-out/bin/jix compile -r ./examples/{{EXAMPLE}}.jix
