`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: Soujanya S R (MS2019021)
// 
// Create Date: 24.02.2021 18:29:00
// Design Name: 
// Module Name: tb_proc
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module tb_proc;

localparam DATAWIDTH = 32,
             IQ_SIZE = 7;

//Instructions:     HEX code

//LW R3, 0(R2)      0X00012183
//DIV R2, R3, R4    0x0241C133
//MUL R1, R5, R6    0X026280B3
//ADD R3, R7, R8    0X008381B3
//MUL R1, R1, R3    0X023080B3
//SUB R4, R1, R5    0X40508233
//ADD R1, R4, R2    0X002200B3

 reg [DATAWIDTH-1:0] instr;
 wire IQ_FULL;
 reg clk;
 reg reset;
 
 integer i;
 
 reg [DATAWIDTH-1:0] instr_set [6:0];

proc #(.DATAWIDTH(DATAWIDTH), .IQ_SIZE(IQ_SIZE)) inst1(

    .instr(instr),
    .IQ_FULL(IQ_FULL),

    .clk(clk),
    .reset(reset)

    );

initial
begin
   instr_set[0] = 32'h00012183; 
   instr_set[1] = 32'h0241C133;
   instr_set[2] = 32'h026280B3;
   instr_set[3] = 32'h008381B3;
   instr_set[4] = 32'h023080B3;
   instr_set[5] = 32'h40508233;
   instr_set[6] = 32'h002200B3;
end


initial
begin
  
	$dumpfile("test.vcd");
    $dumpvars(0,tb_proc);
    
    clk = 1;
    reset = 1;
    #10
    reset = 0;  
    
    i = 0; 
    
    repeat(7)
    begin
        instr = instr_set[i];        
        i = i+1;        
        #10;
        
    end   
    #470
    $finish;  
end


always #5 clk = ~clk;


endmodule
