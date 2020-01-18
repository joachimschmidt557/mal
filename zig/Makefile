STEPS = step0_repl step1_read_print step2_eval step3_env step4_if_fn_do step5_tco

all: $(STEPS)

clean:
	$(RM) $(STEPS)

.PHONY: all clean

step1_read_print: reader.zig printer.zig types.zig
step2_eval: reader.zig printer.zig types.zig
step3_env: reader.zig printer.zig types.zig env.zig
step4_if_fn_do: reader.zig printer.zig types.zig env.zig core.zig rc.zig
step5_tco: reader.zig printer.zig types.zig env.zig core.zig rc.zig

%: %.zig
	zig build-exe -lc $<
