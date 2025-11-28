`timescale 1ns/1ps

`define START_TESTBENCH error_o = 0; pass_o = 0; #10;
`define FINISH_WITH_FAIL error_o = 1; pass_o = 0; #10; $finish();
`define FINISH_WITH_PASS pass_o = 1; error_o = 0; #10; $finish();

module testbench
  (output logic error_o = 1'bx,
   output logic pass_o  = 1'bx);

  localparam width_p = 8;
  localparam depth_p = 8;

  logic clk_i;
  logic reset_i;

  logic [width_p-1:0] data_i;
  logic        valid_i;
  logic        ready_o;
  logic [width_p-1:0] data_o;
  logic        valid_o;
  logic        ready_i;

  nonsynth_clock_gen
    #(.cycle_time_p(10))
  cg (.clk_o(clk_i));

  nonsynth_reset_gen
    #(.reset_cycles_lo_p(1),
      .reset_cycles_hi_p(10))
  rg (.clk_i(clk_i),
      .async_reset_o(reset_i));

  fifo_1r1w #(
    
  ) dut (
    .clk_i(clk_i),
    .reset_i(reset_i),
    .data_i(data_i),
    .valid_i(valid_i),
    .ready_o(ready_o),
    .valid_o(valid_o),
    .data_o(data_o),
    .ready_i(ready_i)
  );
  
  logic [width_p-1:0] ref_q[$];
  int num_errors, num_tests;

  logic wr;
  logic rd;
  assign wr = valid_i && ready_o;   
  assign rd = valid_o && ready_i; 
  logic [width_p-1:0] expected;

  // Handshake Checker
  always @(posedge clk_i) begin
    if (!reset_i) begin
      // On write handshake, enqueue data
      if (wr) begin
        ref_q.push_back(data_i);
        $display("[%0t] PUSH: %h (qsize=%0d)", $time, data_i, ref_q.size());
      end
      // On read handshake, dequeue and check
      if (rd) begin
        if (ref_q.size() > 0) begin
          expected = ref_q[0];
          ref_q.pop_front();
          if (data_o !== expected) begin
            $display("[%0t] ERROR: Got %h expected %h (qsize=%0d)",
            $time, data_o, expected, ref_q.size());
            num_errors++;
          end else begin
            $display("[%0t] POP: %h (qsize=%0d)", $time, data_o, ref_q.size());
          end
          num_tests++;
        end else begin
          $display("[%0t] ERROR: Read from empty FIFO!", $time);
          num_errors++;
        end
      end
    end
  end

  initial begin
    `START_TESTBENCH

    valid_i = 0;
    ready_i = 0;
    data_i  = 0;
    num_errors = 0;
    num_tests  = 0;
    ref_q = {};

    @(negedge reset_i);
    @(posedge clk_i);

    $display("[%0t] Starting random test phase", $time);
    
    repeat (100) begin
      data_i  = $urandom_range(0, (1<<width_p)-1);
      valid_i = $urandom_range(0,1);
      ready_i = ($urandom_range(0,9) < 8);

      @(posedge clk_i);  
    end

    // Test: Fill the FIFO completely
    $display("[%0t] Starting fill test", $time);
    valid_i = 1;
    ready_i = 0;
    
    repeat (130) begin
      data_i = $urandom_range(0, (1<<width_p)-1);
      
      @(posedge clk_i);
      
      if (ref_q.size() == 9 && ready_o) begin
        $display("[%0t] ERROR: FIFO should be full but ready_o is high!", $time);
        num_errors++;
      end
      if (ref_q.size() > 0 && !ready_o) begin
        $display("[%0t] ERROR: FIFO has %0d elements (not full) but ready_o is low!", 
        $time, ref_q.size());
        num_errors++;
      end
      if (ref_q.size() > 0 && !valid_o) begin
        $display("[%0t] ERROR: FIFO has %0d elements but valid_o is low!", 
        $time, ref_q.size());
        num_errors++;
      end
      if (ref_q.size() == 0 && valid_o) begin
        $display("[%0t] ERROR: FIFO is empty but valid_o is high!", $time);
        num_errors++;
      end
    end
    
    // Drain the FIFO
    $display("[%0t] Starting drain (qsize=%0d)", $time, ref_q.size());
    valid_i = 0;
    ready_i = 1;

    repeat (135) begin
      @(posedge clk_i);

      if (ref_q.size() == 0 && !valid_o) begin
        $display("[%0t] Drain complete", $time);
        break;
      end
    end

    if (ref_q.size() != 0) begin
      $display("[%0t] ERROR: Queue not empty: %0d items remain", $time, ref_q.size());
      num_errors++;
    end

    if (!ready_o) begin
      $display("[%0t] ERROR: FIFO should be ready when empty!", $time);
      num_errors++;
    end

    if (valid_o) begin
      $display("[%0t] ERROR: FIFO should not be valid when empty!", $time);
      num_errors++;
    end

    $display("[%0t] Starting simultaneous read/write test", $time);
    
    // Fill partially
    valid_i = 1;
    ready_i = 0;
    repeat (depth_p / 2) begin
      data_i = $urandom_range(0, (1<<width_p)-1);
      @(posedge clk_i);
    end
    
    // Simultaneous operations
    valid_i = 1;
    ready_i = 1;
    repeat (20) begin
      data_i = $urandom_range(0, (1<<width_p)-1);
      @(posedge clk_i);
    end

    // Final drain
    valid_i = 0;
    ready_i = 1;
    repeat (depth_p + 5) begin
      @(posedge clk_i);
      if (ref_q.size() == 0 && !valid_o) break;
    end

    #5;
    if (num_errors > 0) begin
      $display("FAILED with %0d errors out of %0d tests.", num_errors, num_tests);
      `FINISH_WITH_FAIL;
    end else begin
      $display("PASSED all %0d tests.", num_tests);
      `FINISH_WITH_PASS;
    end
  end

  final begin
    $display("Simulation time is %t", $time);
    if(error_o === 1) begin
      $display("\033[0;31m    ______                    \033[0m");
      $display("\033[0;31m   / ____/_____________  _____\033[0m");
      $display("\033[0;31m  / __/ / ___/ ___/ __ \\/ ___/\033[0m");
      $display("\033[0;31m / /___/ /  / /  / /_/ / /    \033[0m");
      $display("\033[0;31m/_____/_/  /_/   \\____/_/     \033[0m");
      $display("Simulation Failed");
    end else if (pass_o === 1) begin
      $display("\033[0;32m    ____  ___   __________\033[0m");
      $display("\033[0;32m   / __ \\/   | / ___/ ___/\033[0m");
      $display("\033[0;32m  / /_/ / /| | \\__ \\\\__ \\ \033[0m");
      $display("\033[0;32m / ____/ ___ |___/ /__/ / \033[0m");
      $display("\033[0;32m/_/   /_/  |_/____/____/  \033[0m");
      $display();
      $display("Simulation Succeeded!");
    end else begin
      $display("   __  ___   ____ __ _   ______ _       ___   __");
      $display("  / / / / | / / //_// | / / __ \\ |     / / | / /");
      $display(" / / / /  |/ / ,<  /  |/ / / / / | /| / /  |/ / ");
      $display("/ /_/ / /|  / /| |/ /|  / /_/ /| |/ |/ / /|  /  ");
      $display("\\____/_/ |_/_/ |_/_/ |_/\\____/ |__/|__/_/ |_/   ");
      $display("Please set error_o or pass_o!");
    end
  end

endmodule