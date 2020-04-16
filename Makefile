build: format
	dune build

install:
	dune build @install


format:
	dune build @fmt --auto-promote | true

test: build
	dune exec src/main.exe -- --debug --backend LaTeX --output \
		test/allocations_familiales.tex test/allocations_familiales.catala

inspect:
	gitinspector -f ml,mli,mly,iro,tex,catala,md,ir --grading
