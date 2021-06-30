# Tomasulo-Out-of-order-Processor


- Out-of-order processor built based on the standard Tomasulo algorithm with re-order buffer. It’s a single-issue RISC-V 4-stage pipelined processor with Instruction Fetch, decode and writing to reservation station happens in stage-1, followed by Execution in stage-2, writing back through common data bus in stage-3 and Commit in stage-4.
- Basic arithmetic and load/store instructions were tested successfully.

- Tools used: Vivado Design Suite 2020.1
