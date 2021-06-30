`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: Soujanya S R (MS2019021)
// 
// Create Date: 24.02.2021 18:25:49
// Design Name: 
// Module Name: proc
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


//definitions for RS_1, RS_2  feilds
`define     rs_s_val2   31:0    //32-bits
`define     rs_s_val1   63:32   //32-bits
`define     rs_s_tag2   67:64   //4-bits
`define     rs_s_tag1   71:68   //4-bits
`define     rs_d_tag    75:72   //4-bits
`define     rs_busy     76      //1-bits
`define     rs_instr    86:77   //10-bits
`define     rs_init     87      //1-bit

//definitions for load buffers feilds
`define     lbuff_s_val         31:0    //32-bits
`define     lbuff_s_tag         35:32   //4-bits
`define     lbuff_add_offest    47:36   //12-bits
`define     lbuff_d_tag         51:48   //4-bits
`define     lbuff_busy          52      //1-bit
`define     lbuff_instr         55:53   //3-bits 
`define     lbuff_init          56      //1-bit

//definitials for RoB feilds

`define     RoB_value   31:0    // 32-bits
`define     RoB_dest    36:32  // 5-bits
`define     RoB_instr   46:37   // 10-bits
`define     RoB_valid   47       // 1-bit
`define     RoB_busy    48     // 1-bit



module proc #(DATAWIDTH = 32, IQ_SIZE = 2, RoB_SIZE = 8, RAT_SIZE = 10, INSTR_COUNT = 7 )(

    input [DATAWIDTH-1:0] instr,
    output reg IQ_FULL,

    input clk,
    input reset

    );
    

//opcodes : naming convenstion following the risc-v spec doc
localparam  LOAD    =   7'b0000011,     //for load
            OP      =   7'b0110011;     //for ADD,SUB,MUL,DIV 
          
//operations: derived from func7, func3
localparam  ADD     =   10'b0000000_000,
            SUB     =   10'b0100000_000,
            MUL     =   10'b0000001_000,
            DIV     =   10'b0000001_100,
            LW      =   3'b010;            
            
                       
 //Instruction queue 
 //since instruction is sent for decoding in the same cycle as it is fetched, IQ depth=1 should also suffice. or may be instr can be directly sent to decode stage
 reg [DATAWIDTH-1:0] IQ [IQ_SIZE : 1 ] ;
 integer IQ_counter;
 integer instr_tcount;
 
  //Decode
  reg decode_EN;
  reg decoder_busy;
  reg [31:0] decode_instr; 
  reg [6:0] opcode; 
  reg [6:0] func7;
  reg [2:0] func3;
  reg [4:0] rd, rs1, rs2;
  reg [11:0] imm;
  reg [9:0] func;
  
  
  //RS
  reg [87:0]RS_1 [2:0]; // for 3 ADD,SUB 
  reg [87:0]RS_2 [1:0]; // for 2 MUL,DIV
  reg [56:0]BUFF [2:0];  //for 3 LW
  reg [1:0] BUFF_free;
  reg [1:0] RS_1_free;
  reg [1:0] RS_2_free;
  reg BUFF_FULL;
  reg RS_1_FULL;
  reg RS_2_FULL;
  reg BUFF_idx;
  reg RS_1_idx;
  reg RS_2_idx;
  
  //Re-Order Buffer
  localparam   RoB_addrewidth = $clog2(RoB_SIZE); // = 3 but 1 to 8 4 bits required => [RoB_addrewidth:0] used instead of [RoB_addrewidth-1:0]
  reg   [48:0] RoB [RoB_SIZE : 1]; 
  reg   [RoB_addrewidth:0]   RoB_HP, RoB_TP;
  reg    RoB_FULL;
  
 //Latency counters
  integer  lat1, lat5, lat10, lat40;
  
  //Common Data Bus (CDB)
  reg [DATAWIDTH-1:0]       exe_lw_addr,exe_lw_offset,exe_add_a, exe_add_b,exe_sub_a,exe_sub_b,exe_mul_a,exe_mul_b,exe_div_a,exe_div_b;
  reg [DATAWIDTH-1:0]       exe_out_add,exe_out_sub,exe_out_mul,exe_out_div,exe_out_lw;
  reg [DATAWIDTH-1:0]       CDB_add,CDB_sub,CDB_mul,CDB_div,CDB_lw;
  reg [RoB_addrewidth:0]    temp_dest_add,temp_dest_sub, temp_dest_mul, temp_dest_div, temp_dest_lw, temp_dest_rob;
    
  //RAT
  reg [RoB_addrewidth:0] RAT [RAT_SIZE:1]; //phy reg size can be greater than ARF
    
  //ARF
  reg [31:0] ARF [10:1];
  reg [31:0] ARF_temp [10:1];
 
 //Memory
 reg [31:0] mem [99:0];
 
 //iteration variables
 integer i;
 integer i0,i1,i2,i3,i4,i5,i6,i7,i8,i9;  
 
 always @(posedge clk)
 begin
    if(reset)
    begin
          ARF[1] = 'd12;
          ARF[2] = 'd16;
          ARF[3] = 'd45;
          ARF[4] = 'd5;
          ARF[5] = 'd3;
          ARF[6] = 'd4;
          ARF[7] = 'd1;
          ARF[8] = 'd2;
          ARF[9] = 'd2;
          ARF[10] = 'd3;
          
          $readmemb("mem_32.mif", mem );
          
          //empty the IQ
           for(i=1;i<=10; i=i+1)
          begin
              ARF_temp[i] = ARF[i];
          end
          
          //copy ARF to temp
          //empty the IQ
           for(i=1;i<=IQ_SIZE; i=i+1)
          begin
              IQ[i] = {DATAWIDTH{1'b0}};
          end
          
          instr_tcount = 0;
          IQ_counter = 1;
          IQ_FULL = 0;
          
          decode_EN = 1'b0;
          
          decoder_busy = 0;
         
          for(i=1; i<=RAT_SIZE; i=i+1)
          begin
                RAT[i] =  {RoB_addrewidth+1{1'b0}};
          end
          
          RoB_FULL = 0;
          
          for(i=1; i<=RoB_SIZE; i=i+1)
          begin
                RoB[i] =  {49{1'b0}};
          end
          
          
          RoB_HP    =   1; //RoB1
          RoB_TP    =   0; //RoB1 //initially both point to the same loc //HP increaments with commit and TP increments with every destination rename
          
          //latency counter set to 0
          lat1  =   0;
          lat5  =   0;
          lat10 =   0;
          lat40 =   0;
          
          //empty the load/store BUFF
           for(i=0;i<3; i=i+1)
          begin
              BUFF[i] = {56{1'b0}};
          end
          //empty the RS_1
           for(i=0;i<3; i=i+1)
          begin
              RS_1[i] = {87{1'b0}};
          end
          //empty the RS_2
           for(i=0;i<2; i=i+1)
          begin
              RS_2[i] = {87{1'b0}};
          end
          BUFF_FULL =   0;                   
          RS_1_FULL =   0;
          RS_2_FULL =   0;
    end

 
    if(!reset)
    begin
    
      //////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
      //                                                      Fetch block                                                      //                                                                                                                             
      //////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
          
    
            if(!IQ_FULL && instr_tcount<= INSTR_COUNT)
            begin
                IQ[IQ_counter] = instr;
                instr_tcount = instr_tcount + 1;
                
                
                $display("\n\nClk_cycle \t%0t : IF: %h; INSTR_num:%d",$time*0.0001,IQ[IQ_counter],IQ_counter)  ;  
                IQ_counter = IQ_counter + 1 ;   
                decode_EN = 1'b1;  //else RoB gets assigned even when the instruction is not fetched (after !reset)                    
                
            end                     
        
           if(IQ_counter == IQ_SIZE)
             IQ_FULL = 1; 
             
           if(instr_tcount > INSTR_COUNT)
             decode_EN = 1'b0;  
 
      //////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
      //                                                       Decoder block                                                  //                                                                                                                             
      //////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    end  
    
    if(!reset && !decoder_busy && decode_EN)
             begin
            
            
                    //***always decode the instr at the bottom   
                    //read the instr at the bottom of IQ
                    //shift down the instructions in IQ             
                    //decode : clear old data & extract fields 
                    // issue to RS
                    //****
                    
                    //read
                    decode_instr = IQ[1];
                    IQ_counter = IQ_counter - 1 ;
                    
                    //push down
                    for(i=1;i<IQ_SIZE; i=i+1)
                    begin
                        IQ[i] = IQ[i+1];
                    end                    
                    
                    //extract fields            
                    //get the opcode
                    opcode = decode_instr[6:0];                                         
                    
                    //clear the fields
                    imm      =  0;            
                    rs1      =  0;
                    rs2      =  0;
                    func3    =  0;
                    func7    =  0;
                    
                    //using switch case to avoid priority logic
                    case(opcode)
                    
                        LOAD : begin
                                   imm      =   decode_instr[31:20];
                                   rs1      =   decode_instr[19:15];
                                   func3    =   decode_instr[14:12];
                                   //get RD
                                   rd = decode_instr[11:7]; 
                                   
                                    $display("Clk_cycle \t%0t : ID: (imm)%b_(rs1)%b_(func3)%b_(rd)%b_(opcode)%b ; INSTR:0x%h ", $time*0.0001,imm, rs1, func3, rd, opcode,decode_instr );
                                    
                                   //check LW  
                                   if(func3 == LW)
                                   begin
                                   
                                         //check if load buffer is free
                                         if(!BUFF_FULL)
                                              begin
                                                  BUFF[BUFF_free][`lbuff_busy]        = 1'b1;
                                                  BUFF[BUFF_free][`lbuff_instr]       = func3;                                                 
                                                  BUFF[BUFF_free][`lbuff_add_offest]  = imm;
                                                  
                                                  //a. Source read
                                                  BUFF[BUFF_free][`lbuff_s_tag]       = RAT[rs1];
                                                  if(BUFF[BUFF_free][`lbuff_s_tag] == 4'b0000)
                                                  begin
                                                      BUFF[BUFF_free][`lbuff_s_val]   =   ARF[rs1];
                                                      BUFF[BUFF_free][`lbuff_init]    =   1'b1;  
                                                  end
                                                        
                                                      
                                                  //b. Destination rename                                                   
                                                  
                                                   if(!RoB_FULL)
                                                   begin
                                                         RAT[rd] = RoB_TP+1; // use its address to map RAT dest rename  // RoB_TP -> 0 to 7 but we need 1 to 8
                                                           BUFF[BUFF_free][`lbuff_d_tag]       = RAT[rd];
                                                           //fillng RoB fields
                                                           RoB[RoB_TP+1][`RoB_instr]     =   func3;  
                                                           RoB[RoB_TP+1][`RoB_dest]      =   rd;
                                                           RoB[RoB_TP+1][`RoB_busy]      =   1'b1;  
                                                           
                                                           RoB_TP = (RoB_TP + 1)%8;
                                                   end 
                                                   
                                                   $display("Clk_cycle \t%0t : BUFF_%d:0x%h  (Src_tag):%b (Src_val_1):%d ; INSTR: 0x%h",$time*0.0001,BUFF_free, BUFF[BUFF_free], BUFF[BUFF_free][`lbuff_s_tag],BUFF[BUFF_free][`lbuff_s_val],decode_instr);
                                                   $display("Clk_cycle \t%0t : RoB%d = R%d \t RAT[%d] = RoB%d",$time*0.0001,RoB_TP+1 ,rd,rd,RAT[rd]);                                       
                                              end                                
                                   end
                                                        
                               end 
                               
                        OP:    begin//5
                                    func7   =   decode_instr[31:25];
                                    rs2     =   decode_instr[24:20];
                                    rs1     =   decode_instr[19:15];
                                    func3   =   decode_instr[14:12];                                                               
                                    func    =   {func7,func3}; 
                                    rd      =   decode_instr[11:7]; 
                                    $display("Clk_cycle \t%0t : ID: (func7)%b_(rs2)%b_(rs1)%b_(func3)%b_(rd)%b_(opcode)%b ; INSTR:0x%h ", $time*0.0001, func7,rs2, rs1, func3, rd, opcode,decode_instr );
                                   
                                    if (func == ADD || func == SUB)         
                                        begin//4
                                        
                                         //check if RS_1 is free
                                         if(!RS_1_FULL)
                                               begin//3
                                                   RS_1[RS_1_free][`rs_busy]        = 1'b1;
                                                   RS_1[RS_1_free][`rs_instr]       = func;
                                                   
                                                   //a. Source read                                                   
                                                   RS_1[RS_1_free][`rs_s_tag1]  =   RAT[rs1];
                                                   if(RS_1[RS_1_free][`rs_s_tag1] == 4'b0000)                                                 
                                                       RS_1[RS_1_free][`rs_s_val1]  =   ARF[rs1];
                                                       
                                                       
                                                   RS_1[RS_1_free][`rs_s_tag2]  =   RAT[rs2];    
                                                   if(RS_1[RS_1_free][`rs_s_tag2] == 4'b0000)
                                                       RS_1[RS_1_free][`rs_s_val2]  =   ARF[rs2]; 
                                                       
                                                   if(  RS_1[RS_1_free][`rs_s_tag1] == 4'b0000 && RS_1[RS_1_free][`rs_s_tag2] == 4'b0000)
                                                        RS_1[RS_1_free][`rs_init] = 1'b1;
                                                       
                                                  //b. Destination rename
                                                 
                                                  if(!RoB_FULL)
                                                  begin
                                                          RAT[rd] = RoB_TP+1; // use its address to map RAT dest rename 
                                                          RS_1[RS_1_free][`rs_d_tag]       = RAT[rd];
                                                          //fillng RoB fields
                                                          RoB[RoB_TP+1][`RoB_instr]     =   func;  
                                                          RoB[RoB_TP+1][`RoB_dest]      =   rd;
                                                          RoB[RoB_TP+1][`RoB_busy]      =   1'b1;  
                                                           
                                                         RoB_TP = (RoB_TP + 1)%8;  
                                                      end  
                                                      
                                                   $display("Clk_cycle \t%0t : RS_1_%d: 0x%h (Src_tag_1):%b (Src_tag_2):%b (Src_val_1):%d (Src_val_2):%d ; INST: 0x%h",$time*0.0001,RS_1_free, RS_1[RS_1_free],  RS_1[RS_1_free][`rs_s_tag1],RS_1[RS_1_free][`rs_s_tag2],RS_1[RS_1_free][`rs_s_val1],RS_1[RS_1_free][`rs_s_val2],decode_instr);                                                                                                             
                                                   $display("Clk_cycle \t%0t : RoB%d = R%d \t RAT[%d] = RoB%d",$time*0.0001, RoB_TP+1,rd,rd,RAT[rd]); 
                                          end //3    
                                          
                                           else
                                                    decoder_busy = 1'b1;                                      
                                                                
                                    end//4
                                    
                                    
                                         if ( func == MUL || func == DIV )
                                          begin//4
                                           //check if RS_2 is free
                                           
                                            if(!RS_2_FULL)                                
                                                     begin//3
                                                         RS_2[RS_2_free][`rs_busy]        = 1'b1; 
                                                         RS_2[RS_2_free][`rs_instr]       = func;
                                                         
                                                         //a. Source read
                                                         RS_2[RS_2_free][`rs_s_tag1]= RAT[rs1];
                                                         if(RS_2[RS_2_free][`rs_s_tag1] == 4'b0000)
                                                             RS_2[RS_2_free][`rs_s_val1]  =   ARF[rs1];
                                                             
                                                         RS_2[RS_2_free][`rs_s_tag2]  =   RAT[rs2];    
                                                         if(RS_2[RS_2_free][`rs_s_tag2] == 4'b0000)
                                                             RS_2[RS_2_free][`rs_s_val2]  =   ARF[rs2];
                                                             
                                                             
                                                         if(  RS_2[RS_2_free][`rs_s_tag1] == 4'b0000 && RS_2[RS_2_free][`rs_s_tag2] == 4'b0000)
                                                                RS_2[RS_2_free][`rs_init] = 1'b1;    
                                                             
                                                         
                                                         //b. Destination rename
                                                        
                                                        if(!RoB_FULL)
                                                        begin
                                                     
                                                                RAT[rd] = RoB_TP+1; // use its address to map RAT dest rename 
                                                                RS_2[RS_2_free][`rs_d_tag]       = RAT[rd];  
                                                                //fillng RoB fields
                                                                RoB[RoB_TP+1][`RoB_instr]     =   func;  
                                                                RoB[RoB_TP+1][`RoB_dest]      =   rd;
                                                                RoB[RoB_TP+1][`RoB_busy]      =   1'b1;  
                                                                
                                                                RoB_TP = (RoB_TP + 1)%8;                                  
                                                                
                                                            end 
                                                            
                                                             $display("Clk_cycle \t%0t : RS_2_%d: 0x%h  (Src_tag_1):%b (Src_tag_2):%b (Src_val_1):%d (Src_val_2):%d ; INST: 0x%h",$time*0.0001,RS_2_free,RS_2[RS_2_free], RS_2[RS_2_free][`rs_s_tag1], RS_2[RS_2_free][`rs_s_tag2], RS_2[RS_2_free][`rs_s_val1], RS_2[RS_2_free][`rs_s_val2],decode_instr); 
                                                             $display("Clk_cycle \t%0t : RoB%d = R%d \t RAT[%d] = RoB%d",$time*0.0001,RoB_TP+1,rd,rd,RAT[rd]);
                                                      
                                                      end//3
                                                      
                                                      
                                                     else
                                                        decoder_busy = 1'b1;  
                                           end//4                                      
                             end//5
                    endcase  
            end//decode      
    end//always decode
    
    
      
      //////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
      //                                                        Execution block                                                      //                                                                                                                             
      //////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
      
  
      always @(posedge clk)
      begin
      
        //check if RoB full
        for(i0=RoB_TP; i0<=RoB_SIZE; i0=i0+1) //check for free RoB
        begin//2
          if(RoB[i0][`RoB_busy] == 0) //when found
            begin
                RoB_FULL = 0;
                i0 = RoB_SIZE+1; 
            end
          else
            if(i0 == RoB_SIZE)
              RoB_FULL = 1;    
       end
     
     
       //------------------------------------------------------------------------------------------------------ 
      //check for free BUFF/RS
      //check if load buffer is free
          for(i1=0; i1<3; i1=i1+1)
          begin
               if(BUFF[i1][`lbuff_busy] == 0)
               begin
                    BUFF_free = i1;                    
                    i1 = 3; //break  
               end
               else
                 if(i1==2)
                 begin
                     BUFF_FULL = 1;                      
                 end 
         end  
         
               
       //check if RS_1 is free                             
          for(i2=0; i2<3; i2=i2+1)
          begin
               if(RS_1[i2][`rs_busy] == 0) //when found
               begin
                    RS_1_free = i2;                                      
                    i2 = 3; //break  
               end  
               else
                 if(i2==2)
                 begin
                     RS_1_FULL = 1;                      
                 end  
          end 
          
         
      //check if RS_2 is free                          
          for(i3=0; i3<2; i3=i3+1)
          begin
               if(RS_2[i3][`rs_busy] == 0) //when found
               begin
                    RS_2_free = i3;                                     
                    i3 = 2; //break  
               end  
               else
                 if(i3==1)
                 begin
                     RS_2_FULL = 1;                      
                 end  
          end  
     end   
        //------------------------------------------------------------------------------------------------------ 
       //check if RS/BUFF is busy and src tag == 0000
       //issue to exe and clear the entry in RS  
      //check load/store BUFF
      
      always @(posedge clk)
      begin
        for(i4=0; i4<3; i4=i4+1)
          begin//4
               if(BUFF[i4][`lbuff_busy] == 1)
               begin//3
                    if(BUFF[i4][`lbuff_s_tag] == 4'b0000)
                        begin//2
                            //issue to execution depending on instr
                            
                            if(BUFF[i4][`lbuff_instr] == LW)                            
                               
                                   begin//1
                                         
                                     //store the dest tag temporarily
                                     temp_dest_lw = BUFF[i4][`lbuff_d_tag];
                                     exe_lw_addr = BUFF[i4][`lbuff_s_val]; //adress
                                     exe_lw_offset = BUFF[i4][`lbuff_add_offest];//offset 
                                     //signextend
                                     exe_lw_offset = {{20{exe_lw_offset[11]}},exe_lw_offset[11:0]};
                                     BUFF_idx = i4; 
                                     
                                     if(BUFF[BUFF_idx][`lbuff_init])
                                         @(posedge clk); //in next clk cycle: clear the entry and issue to EX                                    
                                     
                                     BUFF[BUFF_idx] = {56{1'b0}};
                                     decoder_busy = 0;
                                     BUFF_FULL = 0; 
                                     $display("Clk_cycle \t%0t : Ex_Started(Load): address %d offset %d ",$time*0.0001,exe_lw_addr,exe_lw_offset,BUFF[BUFF_idx]);                                     
                                     load1(exe_out_lw,exe_lw_addr,exe_lw_offset);  
                                     $display("Clk_cycle \t%0t : Ex_Ended(Load):  ",$time*0.0001,exe_out_lw);
                                     
                                     @(posedge clk); //write to CDB in next cycle
                                     CDB_lw = exe_out_lw; //issue to CDB
                                     //Update RoB
                                     RoB[temp_dest_lw][`RoB_value]   =   CDB_lw;
                                     RoB[temp_dest_lw][`RoB_valid]   =   1'b1;
                                     
                                  end//1                                    
                        end//2 
               end//3
           end //4   
      end
      
           
       always @(posedge clk)
      begin     
      //check RS_1
         for(i5=0; i5<3; i5=i5+1)
          begin
               if(RS_1[i5][`rs_busy] == 1)
               begin
                    if(RS_1[i5][`rs_s_tag1] == 4'b0000 && RS_1[i5][`rs_s_tag2] == 4'b0000 )
                        begin
                            //issue to execution depending on instr
                            
                            if(RS_1[i5][`rs_instr] == ADD)                           
                               
                                  begin
                                   //store the dest tag temporarily
                                     temp_dest_add = RS_1[i5][`rs_d_tag];
                                     exe_add_a = RS_1[i5][`rs_s_val1];
                                     exe_add_b = RS_1[i5][`rs_s_val2]; 
                                     RS_1_idx = i5;
                                     
                                     if(RS_1[RS_1_idx][`rs_init])
                                        @(posedge clk); //in next clk cycle: clear the entry and issue to EX                                    
                                     
                                     RS_1[RS_1_idx] = {87{1'b0}};
                                     RS_1_FULL = 0; 
                                     decoder_busy = 0;
                                     $display("Clk_cycle \t%0t : Ex_Started(Add): %d\t+%d ",$time*0.0001,exe_add_a,exe_add_b);                                     
                                     add1(exe_out_add,exe_add_a,exe_add_b);  
                                     $display("Clk_cycle \t%0t : Ex_Ended(Add):  ",$time*0.0001,exe_out_add);  
                                     
                                     @(posedge clk); //write to CDB in next cycle                                                         
                                     CDB_add = exe_out_add; //issue to CDB
                                     //Update RoB
                                     RoB[temp_dest_add][`RoB_value]   =   CDB_add;
                                     RoB[temp_dest_add][`RoB_valid]   =   1'b1;
                                     
                                     $display("Clk_cycle \t%0t : WB : ADD RoB%d =\t%d  ",$time*0.0001,temp_dest_add,CDB_add);
                                  
                                  end
                         end
                     end
                  end 
               end        
                                  
                                  
  always @(posedge clk)
      begin     
      //check RS_1
         for(i5=0; i5<3; i5=i5+1)
          begin
               if(RS_1[i5][`rs_busy] == 1)
               begin
                    if(RS_1[i5][`rs_s_tag1] == 4'b0000 && RS_1[i5][`rs_s_tag2] == 4'b0000 )
                        begin
                            //issue to execution depending on instr                                
                                  
                                   if(RS_1[i5][`rs_instr] ==SUB)
                                  begin
                                  //store the dest tag temporarily
                                     temp_dest_sub = RS_1[i5][`rs_d_tag];
                                     exe_sub_a = RS_1[i5][`rs_s_val1];
                                     exe_sub_b = RS_1[i5][`rs_s_val2]; 
                                     RS_1_idx = i5;
                                     
                                     if(RS_1[RS_1_idx][`rs_init])
                                        @(posedge clk); //in next clk cycle: clear the entry and issue to EX                                    
                                     
                                     RS_1[RS_1_idx] = {87{1'b0}};
                                     RS_1_FULL = 0; 
                                     decoder_busy = 0;
                                     $display("Clk_cycle \t%0t : Ex_Started(Sub): %d\t-%d ",$time*0.0001, exe_sub_a,exe_sub_b);                                     
                                     sub1(exe_out_sub,exe_sub_a,exe_sub_b);  
                                     $display("Clk_cycle \t%0t : Ex_Ended(Sub):  ",$time*0.0001,exe_out_sub);  
                                     
                                     @(posedge clk); //write to CDB in next cycle                    
                                     CDB_sub = exe_out_sub; //issue to CDB
                                     //Update RoB
                                     RoB[temp_dest_sub][`RoB_value]   =   CDB_sub;
                                     RoB[temp_dest_sub][`RoB_valid]   =   1'b1;                                 
                                     $display("Clk_cycle \t%0t : WB : SUB RoB%d =\t%d  ",$time*0.0001,temp_dest_sub,CDB_sub);
                                  
                                  end                                
                                                          
                        end     
               end
          end
        end//always  
       
       
       
       always @(posedge clk)
      begin         
       //check RS_2        
          for(i6=0; i6<2; i6=i6+1)
          begin
          
           if(RS_2[i6][`rs_busy] == 1)
               begin                   
                    if(RS_2[i6][`rs_s_tag1] == 4'b0000 && RS_2[i6][`rs_s_tag2] == 4'b0000 )
                        begin
                            //issue to execution depending on instr                            
                            if(RS_2[i6][`rs_instr] == MUL)                            
                                  begin                                         
                                     //store the dest tag temporarily
                                     temp_dest_mul = RS_2[i6][`rs_d_tag];
                                     exe_mul_a = RS_2[i6][`rs_s_val1];
                                     exe_mul_b = RS_2[i6][`rs_s_val2]; 
                                     RS_2_idx = i6;
                                     
                                     if(RS_2[RS_2_idx][`rs_init])
                                         @(posedge clk); //in next clk cycle: clear the entry and issue to EX                                    
                                     
                                     RS_2[RS_2_idx] = {87{1'b0}};
                                     RS_2_FULL = 0; 
                                     decoder_busy = 0;
                                     $display("Clk_cycle \t%0t : Ex_Started(Mul): %d\t*%d  ",$time*0.0001,exe_mul_a,exe_mul_b);                                     
                                     mul1(exe_out_mul,exe_mul_a,exe_mul_b);  
                                     $display("Clk_cycle \t%0t : Ex_Ended(Mul):  ",$time*0.0001,exe_out_mul);  
                                     
                                     @(posedge clk); //write to CDB in next cycle                    
                                     CDB_mul = exe_out_mul; //issue to CDB
                                     //Update RoB
                                     RoB[temp_dest_mul][`RoB_value]   =   CDB_mul;
                                     RoB[temp_dest_mul][`RoB_valid]   =   1'b1;
                                     $display("Clk_cycle \t%0t : WB : MUL RoB%d =\t%d  ",$time*0.0001,temp_dest_mul,CDB_mul);
                                     
                                  end
                          end
                      end
                   end
                end
                
      always @(posedge clk)
      begin         
       //check RS_2
        
          for(i6=0; i6<2; i6=i6+1)
          begin
                if(RS_2[i6][`rs_busy] == 1)
                    begin                   
                    if(RS_2[i6][`rs_s_tag1] == 4'b0000 && RS_2[i6][`rs_s_tag2] == 4'b0000 )
                        begin
                            //issue to execution depending on instr                            
                            if(RS_2[i6][`rs_instr] ==  DIV)
                                  begin
                                   //store the dest tag temporarily
                                     temp_dest_div = RS_2[i6][`rs_d_tag];
                                     exe_div_a = RS_2[i6][`rs_s_val1];
                                     exe_div_b = RS_2[i6][`rs_s_val2]; 
                                     RS_2_idx = i6;
                                     
                                     if(RS_2[RS_2_idx][`rs_init])
                                        @(posedge clk); //in next clk cycle: clear the entry and issue to EX                                    
                                     
                                     RS_2[RS_2_idx] = {87{1'b0}};
                                     RS_2_FULL = 0; 
                                     decoder_busy = 0;
                                     $display("Clk_cycle \t%0t : Ex_Started(Div): %d\t/%d ",$time*0.0001,exe_div_a,exe_div_b);                                     
                                     div1(exe_out_div,exe_div_a,exe_div_b);  
                                     $display("Clk_cycle \t%0t : Ex_Ended(Div):  ",$time*0.0001,exe_out_div);  
                                      
                                     @(posedge clk); //write to CDB in next cycle                   
                                     CDB_div = exe_out_div; //issue to CDB
                                     $display("Clk_cycle \t%0t : WB : DIV RoB%d =\t%d  ",$time*0.0001,temp_dest_div,CDB_div);
                                     //Update RoB
                                     RoB[temp_dest_div][`RoB_value]   =   CDB_div;
                                     RoB[temp_dest_div][`RoB_valid]   =   1'b1;                                                                     
                                  
                                  end                             
                        end  
               end
          end 
          end
         
          //------------------------------------------------------------------------------------------------------ 
          
          //scan srctags and check for RoB valid bits and update RS tags to 4'b0000 when valid = 1
        always @(posedge clk)
      begin  
          //BUFF srctag scan
          for(i7=0; i7<3; i7=i7+1)
          begin
               if(BUFF[i7][`lbuff_busy] == 1)
               begin
                        
                    if(BUFF[i7][`lbuff_s_tag]!= 4'b0000)
                    begin
                        if(RoB[BUFF[i7][`lbuff_s_tag]][`RoB_valid] == 1)
                        begin                            
                            BUFF[i7][`lbuff_s_val] = RoB[BUFF[i7][`lbuff_s_tag]][`RoB_value];  
                            BUFF[i7][`lbuff_s_tag] = 4'b0000;                          
                        end                            
                    end
               end
          end         
         
          //RS_1 srctag scan
          for(i8=0; i8<3; i8=i8+1)
          begin
               if(RS_1[i8][`rs_busy] == 1)
               begin
                    //check srctag 1    
                    if(RS_1[i8][`rs_s_tag1]!= 4'b0000)
                    begin
                        if(RoB[RS_1[i8][`rs_s_tag1]][`RoB_valid] == 1)
                        begin
                            RS_1[i8][`rs_s_val1] = RoB[RS_1[i8][`rs_s_tag1]][`RoB_value]; 
                            RS_1[i8][`rs_s_tag1] = 4'b0000;                                                       
                        end                            
                    end
                    
                    //check srctag 2
                    if(RS_1[i8][`rs_s_tag2]!= 4'b0000)
                    begin
                        if(RoB[RS_1[i8][`rs_s_tag2]][`RoB_valid] == 1)
                        begin
                             RS_1[i8][`rs_s_val2] = RoB[RS_1[i8][`rs_s_tag2]][`RoB_value];     
                             RS_1[i8][`rs_s_tag2] = 4'b0000;                       
                        end                            
                    end
               end
          end
       
          //RS_2 srctag scan
          for(i9=0; i9<2; i9=i9+1)
          begin
               if(RS_2[i9][`rs_busy] == 1)
               begin
                    //check srctag 1    
                    if(RS_2[i9][`rs_s_tag1]!= 4'b0000)
                    begin
                        if(RoB[RS_2[i9][`rs_s_tag1]][`RoB_valid] == 1)
                        begin
                           
                            RS_2[i9][`rs_s_val1] = RoB[RS_2[i9][`rs_s_tag1]][`RoB_value];                           
                            RS_2[i9][`rs_s_tag1] = 4'b0000;                              
                        end                            
                    end
                    
                    //check srctag 2
                    if(RS_2[i9][`rs_s_tag2]!= 4'b0000)
                    begin
                        if(RoB[RS_2[i9][`rs_s_tag2]][`RoB_valid] == 1)
                        begin                            
                            RS_2[i9][`rs_s_val2] = RoB[RS_2[i9][`rs_s_tag2]][`RoB_value];  
                            RS_2[i9][`rs_s_tag2] = 4'b0000;                                                      
                        end                            
                    end               
               end
          end
          
          
                
      end// endRS
      
     
      //////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
      //                                                        Commit block                                                  //                                                                                                                             
      //////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
      
      //check RoB Head to see if it's valid and update ARF (Commit) and clear the RoB entry
      always@ (posedge clk)
      begin
            
            //update ARF
            if(RoB[RoB_HP][`RoB_valid] == 1)
            begin
                 
                 ARF_temp[RoB[RoB_HP][`RoB_dest]] <=  RoB[RoB_HP][`RoB_value];
                 temp_dest_rob <=  RoB_HP;      
                $display("Clk_cycle \t%0t : Commit: R[%d] = %d \n", $time*0.0001+0.001,RoB[RoB_HP][`RoB_dest], RoB[RoB_HP][`RoB_value]);
                 
                 //Increment the head pointer    
                 RoB_HP <=  (RoB_HP + 1)%8; 
            end         
                  
      end//always Rob check
    
      always@ (posedge clk)
      begin
        for(i=1; i<=10; i=i+1)
        begin
            ARF[i] <= ARF_temp[i];
            //clear RoB
                 RoB[temp_dest_rob] <=  {49{1'b0}};
                 RoB_FULL <= 1'b0;
        end
        
      end
      
      
      //////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
      //                                                        Execution units                                               //                                                                                                                             
      //////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
      
      //LOAD
      task automatic  load1;
      
         output reg [31:0] data1; 
         input  [11:0] offset;
         input  [31:0] address;       
        
        begin            
            repeat(4) @(posedge clk)  //introducing 5 clk cycle latency 
            data1 = mem[address+offset-1];
        end 
       endtask
      
      
      //ADDER
       task automatic  add1;
         
         output [31:0] sum;
         input  [31:0] a,b;      
        
        begin
        //1 clk cycle latency
         sum = a+b;
        end 
       endtask
       
      
      //SUBTRACTOR 
       task automatic  sub1;
     
         output [31:0] diff;
         input  [31:0] a,b;      
        
        begin
         //1 clk cycle latency
         diff = a-b;
        end 
       endtask
       
            
      //MULTIPLIER
      task automatic  mul1;
     
         output [31:0] prod;
         input  [31:0] a,b;      
        
        begin
         repeat(9) @(posedge clk)  //introducing 10 clk cycle latency                                     
         prod = a*b;        
        end 
      endtask
      
      
      //DIVIDER
      task automatic  div1;
      
         output [31:0] qt;
         input  [31:0] a,b;  
             
        begin
         repeat(39) @(posedge clk)  //introducing 10 clk cycle latency  
         qt = a/b;
        end 
       endtask
    
  
endmodule



