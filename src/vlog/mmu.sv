/*
 MMU with a bank of main memory and an IO port. The MMU is byte-addressable.
 Access latency is one clock.
 
 Memory Mapping:
 
 - 0x00000000 - 0x00000FFF ROM instruction memory
 - 0x10000000 - 0x7FFFFFFF Main memory
 - 0x80000000 - 0x800000FF I/O ports

 Exceptions are not generated from MMU

 Memory Bank Configuration: 4 interleaving banks of 8-bit wide SSP-BRAM
 
 Limitations: 
 - Data memory port cannot access instruction memory
 - Instruction memory port can only access instruction memory
 - Instruction memory is ROM

 */

module mmu(
      clk, resetb, dm_we,
      im_addr, im_do, dm_addr, dm_di, dm_do,
      dm_be, is_signed,
      // To Instruction Memory
      im_addr_out, im_data,
      // TO IO
      io_addr, io_en, io_we, io_data_read, io_data_write
      );
   
   parameter 
     WORD_DEPTH = 256,
     WORD_DEPTH_LOG = 8;

   localparam
     DEV_IM = 1,
     DEV_DM = 2,
     DEV_IO = 3,
     DEV_UNKN = 4;

   // Clock, reset, data memory write enable
   input wire clk, resetb, dm_we;
   // IM address, DM address, DM data in
   input wire [31:0] im_addr, dm_addr, dm_di;
   // DM data byte enable, non-encoded
   input wire [3:0]  dm_be;
   // DM sign extend or unsigned extend
   input wire       is_signed;
   // IM addr out to ROM
   output wire [11:2] im_addr_out;
   // IM data from ROM, IO data from IO bank
   input wire [31:0]  im_data, io_data_read;
   // IO data to IO bank, DM data output
   output reg [31:0]  io_data_write, dm_do;
   // A temporary register for dm_do
   reg [31:0]        dm_do_tmp;
   // IM data output
   output reg [31:0]  im_do;
   // IO address to IO bank
   output reg [7:0]   io_addr;
   // IO enable, IO write enable
   output reg        io_en, io_we;
   // Shift bytes and half words to correct bank
   reg [31:0]        dm_di_shift;
   // Address mapped to BRAM address
   reg [WORD_DEPTH_LOG-1:2] ram_addr;
   // BRAM write enable
   reg             ram_we;
   // BRAM data output
   wire [31:0]           ram_do;
   // BRAM data input
   reg [31:0]         ram_di;
   // Selected device
   integer         chosen_device_tmp;
   // Selected device, pipelined
   reg [2:0]          chosen_device_p;
   // DM byte enable, pipelined
   reg [3:0]          dm_be_p;
   // MMU signed/unsigned extend, pipelined
   reg             is_signed_p;
   // IO Read input, IO read input pipelined, IO write output
   reg [31:0]         io_data_read_tmp, io_data_read_p, io_data_write_tmp;
   // IO address
   reg [7:0]          io_addr_tmp;
   // IO enable, IO write enable
   reg             io_en_tmp, io_we_tmp;

   // In this implementaion, the IM ROM address is simply the 11:2 bits of IM address input
   assign im_addr_out[11:2] = im_addr[11:2];

   // BRAM bank in interleaved configuration
   BRAM_SSP  #(
          .DEPTH(WORD_DEPTH>>2), .DEPTH_LOG(WORD_DEPTH_LOG-2), .WIDTH(8)
          ) ram0 (
                .clk(clk), .we(ram_we), .en(dm_be[0]), 
                .addr(ram_addr[WORD_DEPTH_LOG-1:2]),
                .din(ram_di[0+:8]), .dout(ram_do[0+:8])
                );
   BRAM_SSP 
     #(
       .DEPTH(WORD_DEPTH>>2), .DEPTH_LOG(WORD_DEPTH_LOG-2), .WIDTH(8)
       )
   ram1 (
       .clk(clk), .we(ram_we), .en(dm_be[1]), 
       .addr(ram_addr[WORD_DEPTH_LOG-1:2]),
       .din(ram_di[8+:8]), .dout(ram_do[8+:8])
    );
   BRAM_SSP
     #(
       .DEPTH(WORD_DEPTH>>2), .DEPTH_LOG(WORD_DEPTH_LOG-2), .WIDTH(8)
       )
   ram2 (
       .clk(clk), .we(ram_we), .en(dm_be[2]), 
       .addr(ram_addr[WORD_DEPTH_LOG-1:2]),
       .din(ram_di[16+:8]), .dout(ram_do[16+:8])
       );
   BRAM_SSP
     #(
       .DEPTH(WORD_DEPTH>>2), .DEPTH_LOG(WORD_DEPTH_LOG-2), .WIDTH(8)
       )
   ram3 (
       .clk(clk), .we(ram_we), .en(dm_be[3]), 
       .addr(ram_addr[WORD_DEPTH_LOG-1:2]),
       .din(ram_di[24+:8]), .dout(ram_do[24+:8])
       );

   // The MMU pipeline
   always @ (posedge clk, negedge resetb) begin : MMU_PIPELINE
      if (!resetb) begin
    chosen_device_p <= 2'bX;
    is_signed_p <= 1'bX;
    dm_be_p <= 4'b0;
    // First instruction is initialized as NOP
    im_do <= 32'b0000_0000_0000_00000_000_00000_0010011;
    io_data_write <= 32'bX;
    io_en <= 1'b0;
    io_we <= 1'b0;
    io_addr <= 8'bX;
      end
      else if (clk) begin
    // Notice the pipeline. The naming is a bit inconsistent
    dm_be_p <= dm_be;
    chosen_device_p <= chosen_device_tmp;
    is_signed_p <= is_signed;
    im_do <= im_data;
    io_data_write <= io_data_write_tmp;
    io_en <= io_en_tmp;
    io_we <= io_we_tmp;
    io_addr <= io_addr_tmp;
      end
   end

   reg [31:0]         ram_addr_temp, io_addr_temp;
   // Device mapping from address
   // Note: X-Optimism might be a problem. Convert to Tertiary to fix
   always @ (*) begin : DM_ADDR_MAP
      ram_addr_temp = dm_addr - 32'h10000000;
      io_addr_temp = dm_addr - 32'h80000000;

      io_en_tmp = 1'b0;
      io_we_tmp = 1'b0;
      io_data_write_tmp = 32'bX;
      ram_we = 1'b0;
      ram_addr = {WORD_DEPTH_LOG-1{1'bX}};
      ram_di = 32'bX;
      chosen_device_tmp = DEV_UNKN;
      if (dm_addr[31:12] == 20'b0) begin
       // 0x00000000 - 0x00000FFF
       chosen_device_tmp = DEV_IM;
      end
      else if (dm_addr[31] == 1'b0 && dm_addr[30:28] != 3'b0) begin
       // 0x10000000 - 0x7FFFFFFF
       ram_addr = ram_addr_temp[2+:WORD_DEPTH_LOG];
       ram_di = dm_di_shift;
       ram_we = dm_we;
       chosen_device_tmp = DEV_DM;
      end
      else if (dm_addr[31:8] == 24'h800000) begin
       // 0x80000000 - 0x800000FF
       io_addr_tmp = io_addr_temp[7:0];
       io_en_tmp = 1'b1;
       io_we_tmp = dm_we;
       io_data_write_tmp = dm_di_shift;
       chosen_device_tmp = DEV_IO;
      end
   end // block: DM_ADDR_MAP
   
   // Shifting input byte/halfword to correct position
   // Note: X-Optimism might be a problem. Convert to Tertiary to fix   
   always @ (*) begin : DM_IN_SHIFT
      dm_di_shift = 32'bX;
      // Byte enable
      if (dm_be == 4'b1111) begin
       dm_di_shift = dm_di;
      end
      else if (dm_be == 4'b1100) begin
       dm_di_shift[16+:16] = dm_di[0+:16];
      end
      else if (dm_be == 4'b0011) begin
       dm_di_shift[0+:16] = dm_di[0+:16];
      end
      else if (dm_be == 4'b0001) begin
       dm_di_shift[0+:8] = dm_di[0+:8];
      end
      else if (dm_be == 4'b0010) begin
       dm_di_shift[8+:8] = dm_di[0+:8];
      end
      else if (dm_be == 4'b0100) begin
       dm_di_shift[16+:8] = dm_di[0+:8];
      end
      else if (dm_be == 4'b1000) begin
       dm_di_shift[24+:8] = dm_di[0+:8];
      end
   end // block: DM_IN_SHIFT
   
   // Shifting byte/halfword to correct output position
   // Note: X-Optimism might be a problem. Convert to Tertiary to fix
   always @ (*) begin : DM_OUT_SHIFT
      case (chosen_device_p)
      DEV_DM:
        dm_do_tmp = ram_do;
      DEV_IO:
        dm_do_tmp = io_data_read;
      default:
        dm_do_tmp = 32'bX;
      endcase // case (chosen_device_reg)
      // Byte enable
      dm_do = 32'bX;
      if (dm_be_p == 4'b1111) begin
       dm_do = dm_do_tmp;
      end
      else if (dm_be_p == 4'b1100) begin
       if (is_signed_p)
         dm_do = {{16{dm_do_tmp[31]}}, dm_do_tmp[16+:16]};
       else
         dm_do = {16'b0, dm_do_tmp[16+:16]};
      end
      else if (dm_be_p == 4'b0011) begin
       if (is_signed_p)
         dm_do = {{16{dm_do_tmp[15]}}, dm_do_tmp[0+:16]};
       else
         dm_do = {16'b0, dm_do_tmp[0+:16]};
      end
      else if (dm_be_p == 4'b0001) begin
       if (is_signed_p)
         dm_do = {{24{dm_do_tmp[7]}}, dm_do_tmp[0+:8]};
       else
         dm_do = {24'b0, dm_do_tmp[0+:8]};
      end
      else if (dm_be_p == 4'b0010) begin
       if (is_signed_p)
         dm_do = {{24{dm_do_tmp[15]}}, dm_do_tmp[8+:8]};
       else
         dm_do = {24'b0, dm_do_tmp[8+:8]};
      end
      else if (dm_be_p == 4'b0100) begin
       if (is_signed_p)
         dm_do = {{24{dm_do_tmp[23]}}, dm_do_tmp[16+:8]};
       else
         dm_do = {24'b0, dm_do_tmp[16+:8]};
      end
      else if (dm_be_p == 4'b1000) begin
       if (is_signed_p)
         dm_do = {{24{dm_do_tmp[31]}}, dm_do_tmp[24+:8]};
       else
         dm_do = {24'b0, dm_do_tmp[24+:8]};
      end
   end
   
dmmap_im: assert property (@(posedge clk) dm_addr < 32'h1000 |=> chosen_device_p == DEV_IM);
dmmap_dm: assert property (@(posedge clk) dm_addr >= 32'h10000000 && dm_addr < 32'h80000000
   |=> chosen_device_p == DEV_DM);
dmmap_io: assert property (@(posedge clk) dm_addr >= 32'h80000000 && dm_addr < 32'h80000100
   |=> chosen_device_p == DEV_IO);

write_disable_doesnot_write: assert property (
   @(posedge clk)
   !dm_we |=> 
      $stable(ram0.RAM) and
      $stable(ram1.RAM) and
      $stable(ram2.RAM) and
      $stable(ram3.RAM) and
      !io_we
   );

   // integer num_changed;
   // integer i;
   reg 	   past_valid = 1'b0;
   always @ (posedge clk)
     past_valid <= 1'b1;

   // always @ (posedge clk) begin : COUNT_CHANGE
   //    num_changed = 0;
   //    for (i = 0; i<256; i = i+1)
   // 	num_changed = num_changed + (($changed(ram0.RAM[i]))?1:0);
   //    at_most_one_write_0: assert property
   // 	 (~past_valid or ($stable(ram0.RAM) or num_changed == 1));
   // end
   

// at_most_one_write_1: assert property 
//    (
//     @(posedge clk)
//     $stable(ram1.RAM) or changed == 1
// );
// at_most_one_write_2: assert property 
//    (
//     @(posedge clk)
//     $stable(ram2.RAM) or changed == 1
// );
// at_most_one_write_3: assert property 
//    (
//     @(posedge clk)
//     $stable(ram3.RAM) or changed == 1
// );

be_no_spurious_enable_0: assert property(@(posedge clk)!dm_be[0]|->!ram0.en);
be_no_spurious_enable_1: assert property(@(posedge clk)!dm_be[1]|->!ram1.en);
be_no_spurious_enable_2: assert property(@(posedge clk)!dm_be[2]|->!ram2.en);
be_no_spurious_enable_3: assert property(@(posedge clk)!dm_be[3]|->!ram3.en);

be_no_spurious_write_0: assert property(@(posedge clk)!dm_be[0]|=>$stable(ram0.RAM));
be_no_spurious_write_1: assert property(@(posedge clk)!dm_be[1]|=>$stable(ram1.RAM));
be_no_spurious_write_2: assert property(@(posedge clk)!dm_be[2]|=>$stable(ram2.RAM));
be_no_spurious_write_3: assert property(@(posedge clk)!dm_be[3]|=>$stable(ram3.RAM));

io_no_spurious_read_01: assert property (
   @(posedge clk) 
   chosen_device_tmp != DEV_IO |=> !io_en
   );

// assume
im_addr_range: assume property(@(posedge clk) im_addr < 32'h00001000);
dm_be_range: assume property(@(posedge clk)(dm_be==4'b1111 || dm_be==4'b0011 || dm_be==4'b1100 || dm_be==4'b0001 || dm_be==4'b0010 || dm_be==4'b0100 || dm_be==4'b1000));
dm_addr_range: assume property(@(posedge clk) dm_addr < 32'h00001000 || dm_addr>=32'h80000000 || (dm_addr[31:WORD_DEPTH_LOG]==24'h100000 && dm_addr[1:0]==0) );
//input_value_varied: assume property(@(posedge clk) dm_we!=$past(dm_we) && dm_addr!=$past(dm_addr) && dm_di!=$past($past(dm_di)));




//write then read


write_then_read_1 : assert property (@(posedge clk) dm_we && dm_addr >= 32'h10000000 && dm_addr < 32'h80000000 && is_signed==0 && dm_be==4'b1111 
 ##1 !dm_we && dm_addr==$past(dm_addr) && is_signed==0 && dm_be==4'b1111 
 |=> dm_do==$past(dm_do) && dm_do==$past($past(dm_di)) ); 

write_then_read_2a: assert property (@(posedge clk) dm_we && dm_addr >= 32'h10000000 && dm_addr < 32'h80000000 && is_signed==0 && dm_be==4'b1111 ##1 dm_we && dm_addr!=$past(dm_addr)
 ##1 !dm_we && dm_addr==$past($past(dm_addr)) && is_signed==0 && dm_be==4'b1111 
 |=>   dm_do==$past($past(dm_do))); 

write_then_read_2c: cover  property (@(posedge clk) dm_we && dm_addr >= 32'h10000000 && dm_addr < 32'h80000000 && is_signed==0 && dm_be==4'b1111 
 ##2 !dm_we && dm_addr==$past($past(dm_addr)) && is_signed==0 && dm_be==4'b1111 
 |=>   dm_do==$past($past(dm_do))); 

write_then_read_3c: cover  property (@(posedge clk) dm_we && dm_addr >= 32'h10000000 && dm_addr < 32'h80000000 && is_signed==0 && dm_be==4'b1111 
 ##151 !dm_we && dm_addr==$past(dm_addr,151) && is_signed==0 && dm_be==4'b1111 
 |=>   dm_do==$past(dm_do,151 )); 

write_then_read_4c: cover  property (@(posedge clk) dm_we && dm_addr >= 32'h10000000 && dm_addr < 32'h80000000 && is_signed==0 && dm_be==4'b1111 
 ##151 !dm_we && dm_addr==$past(dm_addr,151) && is_signed==0 && dm_be==4'b1111 
  ##151 dm_we && dm_addr==$past(dm_addr,151) && is_signed==0 && dm_be==4'b1111 
  ##151 !dm_we && dm_addr==$past(dm_addr,151) && is_signed==0 && dm_be==4'b1111 
 |=>   dm_do==$past(dm_do,151 )); 

//assert

//write_then_output_the_shifted_value : assert property (@(posedge clk) dm_di==32'b1 && dm_we &&  dm_addr >= 32'h10000000 && dm_addr < 32'h80000000 && !is_signed && dm_be == 4'b1111 |=> dm_do==32'b1);
write_then_output_the_shifted_value  : assert property (@(posedge clk) (dm_we &&  dm_addr >= 32'h10000000 && dm_addr < 32'h80000000 && !is_signed )|=>(dm_do==$past(dm_di)));


//assert: the most significant valid bit is 1 and the number is signed, the number should also be correct 
write_then_output_the_shifted_signed_value_1111 : assert property (@(posedge clk) dm_di==32'hffffffff && dm_we &&  dm_addr >= 32'h10000000 && dm_addr < 32'h80000000 && is_signed && dm_be == 4'b1111 |=> dm_do==32'hffffffff);

write_then_output_the_shifted_signed_value_1100 : assert property (@(posedge clk) dm_di==32'h0000ffff && dm_we &&  dm_addr >= 32'h10000000 && dm_addr < 32'h80000000 && is_signed && dm_be == 4'b1100 |=> dm_do==32'hffffffff);

write_then_output_the_shifted_signed_value_0011 : assert property (@(posedge clk) dm_di==32'h0000ffff && dm_we &&  dm_addr >= 32'h10000000 && dm_addr < 32'h80000000 && is_signed && dm_be == 4'b0011 |=> dm_do==32'hffffffff);

write_then_output_the_shifted_signed_value_0001 : assert property (@(posedge clk) dm_di==32'h000000ff && dm_we &&  dm_addr >= 32'h10000000 && dm_addr < 32'h80000000 && is_signed && dm_be == 4'b0001 |=> dm_do==32'hffffffff);

write_then_output_the_shifted_signed_value_0010 : assert property (@(posedge clk) dm_di==32'h000000ff && dm_we &&  dm_addr >= 32'h10000000 && dm_addr < 32'h80000000 && is_signed && dm_be == 4'b0010 |=> dm_do==32'hffffffff);

write_then_output_the_shifted_signed_value_0100 : assert property (@(posedge clk) dm_di==32'h000000ff && dm_we &&  dm_addr >= 32'h10000000 && dm_addr < 32'h80000000 && is_signed && dm_be == 4'b0100 |=> dm_do==32'hffffffff);

write_then_output_the_shifted_signed_value_1000 : assert property (@(posedge clk) dm_di==32'h000000ff && dm_we &&  dm_addr >= 32'h10000000 && dm_addr < 32'h80000000 && is_signed && dm_be == 4'b1000 |=> dm_do==32'hffffffff);

// Inspired by https://zipcpu.com/zipcpu/2018/07/13/memories.html
//reg [WORD_DEPTH_LOG-1:0] f_addr;
//
//reg [7:0] f_data0;
//initial f_data0 = ram0.RAM[f_addr];
//
//always @ (posedge clk) 
//if (ram0.en&&ram0.we && ram0.addr==f_addr) f_data0 <= ram0.din;
//
//ram0_consistency: assert property (@(posedge clk) f_data0 == ram0.RAM[f_addr]);

endmodule // mmu

