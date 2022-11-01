alias b := build
alias r := run

build example='all':
  if [ '{{example}}' = 'all' ]; then \
    for file in `ls examples/*.jix`; do \
      zig build run -- compile $file; \
    done \
  else \
    zig build run -- compile examples/{{example}}.jix; \
  fi

run example='all':
  if [ '{{example}}' = 'all' ]; then \
    for file in `ls examples/*.jix`; do \
      echo -e \\n$file:; \
      zig build run -- compile -r $file; \
    done \
  else \
    zig build run -- compile -r examples/{{example}}.jix; \
  fi
