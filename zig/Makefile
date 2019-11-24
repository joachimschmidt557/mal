STEPS = step0_repl step1_read_print step2_eval step3_env

step1_read_print: reader.zig printer.zig types.zig
step2_eval: reader.zig printer.zig types.zig
step3_env: reader.zig printer.zig types.zig env.zig

%: %.zig
	zig build-exe $<
