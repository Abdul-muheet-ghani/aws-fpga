// Amazon FPGA Hardware Development Kit
//
// Copyright 2016 Amazon.com, Inc. or its affiliates. All Rights Reserved.
//
// Licensed under the Amazon Software License (the "License"). You may not use
// this file except in compliance with the License. A copy of the License is
// located at
//
//    http://aws.amazon.com/asl/
//
// or in the "license" file accompanying this file. This file is distributed on
// an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, express or
// implied. See the License for the specific language governing permissions and
// limitations under the License.

module cl_dram_dma #(parameter NUM_DDR=4) 

(
   `include "cl_ports.vh"

);

`include "cl_common_defines.vh"      // CL Defines for all examples
`include "cl_id_defines.vh"          // Defines for ID0 and ID1 (PCI ID's)
`include "cl_dram_dma_defines.vh"

// TIE OFF ALL UNUSED INTERFACES
// Including all the unused interface to tie off
// This list is put in the top of the fie to remind
// developers to remve the specific interfaces
// that the CL will use

`include "unused_sh_bar1_template.inc"

// Define the addition pipeline stag
// needed to close timing for the various
// place where ATG (Automatic Test Generator)
// is defined
   
   localparam NUM_CFG_STGS_CL_DDR_ATG = 8;
   localparam NUM_CFG_STGS_SH_DDR_ATG = 4;
   localparam NUM_CFG_STGS_PCIE_ATG = 4;

// To reduce RTL simulation time, only 8KiB of
// each external DRAM is scrubbed in simulations

`ifdef SIM
   localparam DDR_SCRB_MAX_ADDR = 64'h1FFF;
`else   
   localparam DDR_SCRB_MAX_ADDR = 64'h3FFFFFFFF; //16GB 
`endif
   localparam DDR_SCRB_BURST_LEN_MINUS1 = 15;

`ifdef NO_CL_TST_SCRUBBER
   localparam NO_SCRB_INST = 1;
`else
   localparam NO_SCRB_INST = 0;
`endif   

//---------------------------- 
// Internal signals
//---------------------------- 
axi_bus_t lcl_cl_sh_ddra();
axi_bus_t lcl_cl_sh_ddrb();
axi_bus_t lcl_cl_sh_ddrd();
axi_bus_t axi_bus_tied();

axi_bus_t sh_cl_dma_pcis_bus();
axi_bus_t sh_cl_dma_pcis_q();

axi_bus_t cl_axi_mstr_bus();

axi_bus_t cl_sh_pcim_bus();
axi_bus_t cl_sh_ddr_bus();

axi_bus_t sda_cl_bus();
axi_bus_t sh_ocl_bus();

cfg_bus_t pcim_tst_cfg_bus();
cfg_bus_t ddra_tst_cfg_bus();
cfg_bus_t ddrb_tst_cfg_bus();
cfg_bus_t ddrc_tst_cfg_bus();
cfg_bus_t ddrd_tst_cfg_bus();
cfg_bus_t axi_mstr_cfg_bus();
cfg_bus_t int_tst_cfg_bus();

scrb_bus_t ddra_scrb_bus();
scrb_bus_t ddrb_scrb_bus();
scrb_bus_t ddrc_scrb_bus();
scrb_bus_t ddrd_scrb_bus();


logic clk;
(* dont_touch = "true" *) logic pipe_rst_n;
logic pre_sync_rst_n;
(* dont_touch = "true" *) logic sync_rst_n;
logic sh_cl_flr_assert_q;

logic [3:0] all_ddr_scrb_done;
logic [3:0] all_ddr_is_ready;
logic [2:0] lcl_sh_cl_ddr_is_ready;

logic dbg_scrb_en;
logic [2:0] dbg_scrb_mem_sel;

//---------------------------- 
// End Internal signals
//----------------------------

// Unused 'full' signals
assign cl_sh_dma_rd_full  = 1'b0;
assign cl_sh_dma_wr_full  = 1'b0;

// Unused *burst signals
assign cl_sh_ddr_arburst[1:0] = 2'h0;
assign cl_sh_ddr_awburst[1:0] = 2'h0;


assign clk = clk_main_a0;

//reset synchronizer
lib_pipe #(.WIDTH(1), .STAGES(4)) PIPE_RST_N (.clk(clk), .rst_n(1'b1), .in_bus(rst_main_n), .out_bus(pipe_rst_n));
   
always_ff @(negedge pipe_rst_n or posedge clk)
   if (!pipe_rst_n)
   begin
      pre_sync_rst_n <= 0;
      sync_rst_n <= 0;
   end
   else
   begin
      pre_sync_rst_n <= 1;
      sync_rst_n <= pre_sync_rst_n;
   end

//FLR response 
always_ff @(negedge sync_rst_n or posedge clk)
   if (!sync_rst_n)
   begin
      sh_cl_flr_assert_q <= 0;
      cl_sh_flr_done <= 0;
   end
   else
   begin
      sh_cl_flr_assert_q <= sh_cl_flr_assert;
      cl_sh_flr_done <= sh_cl_flr_assert_q && !cl_sh_flr_done;
   end

///////////////////////////////////////////////////////////////////////
///////////////// Scrubber enable and status //////////////////////////
///////////////////////////////////////////////////////////////////////

// Bit 31: Debug enable (for cl_sh_id0 and cl_sh_id1)
// Bit 30:28: Debug Scrb memory select
   
// Bit 3 : DDRC Scrub enable
// Bit 2 : DDRD Scrub enable
// Bit 1 : DDRB Scrub enable
// Bit 0 : DDRA Scrub enable
logic [31:0] sh_cl_ctl0_q;
always_ff @(posedge clk or negedge sync_rst_n)
  if (!sync_rst_n)
    sh_cl_ctl0_q <= 32'd0;
  else
    sh_cl_ctl0_q <= sh_cl_ctl0;

assign ddra_scrb_bus.enable = sh_cl_ctl0_q[0];
assign ddrb_scrb_bus.enable = sh_cl_ctl0_q[1];
assign ddrd_scrb_bus.enable = sh_cl_ctl0_q[2];
assign ddrc_scrb_bus.enable = sh_cl_ctl0_q[3];


assign dbg_scrb_en = sh_cl_ctl0_q[31];
assign dbg_scrb_mem_sel[2:0] = sh_cl_ctl0_q[30:28];

// The functionality for these signals is TBD so they can can be tied-off.
assign cl_sh_status0 = 32'h0;
assign cl_sh_status1 = 32'h0;

always_ff @(posedge clk)
    cl_sh_id0 <= dbg_scrb_en ? (dbg_scrb_mem_sel == 3'd3 ? ddrc_scrb_bus.addr[31:0] :
                                dbg_scrb_mem_sel == 3'd2 ? ddrd_scrb_bus.addr[31:0] :
                                dbg_scrb_mem_sel == 3'd1 ? ddrb_scrb_bus.addr[31:0] : ddra_scrb_bus.addr[31:0]) :
                                `CL_SH_ID0; 
always_ff @(posedge clk)
    cl_sh_id1 <= dbg_scrb_en ? (dbg_scrb_mem_sel == 3'd3 ? ddrc_scrb_bus.addr[63:32] :
                                dbg_scrb_mem_sel == 3'd2 ? ddrd_scrb_bus.addr[63:32] :
                                dbg_scrb_mem_sel == 3'd1 ? ddrb_scrb_bus.addr[63:32] : ddra_scrb_bus.addr[63:32]) :
                                `CL_SH_ID1;

logic sh_cl_ddr_is_ready_q;
always_ff @(posedge clk or negedge sync_rst_n)
  if (!sync_rst_n)
  begin
    sh_cl_ddr_is_ready_q <= 1'b0;
  end
  else
  begin
    sh_cl_ddr_is_ready_q <= sh_cl_ddr_is_ready;
  end  

assign all_ddr_is_ready = {lcl_sh_cl_ddr_is_ready[2], sh_cl_ddr_is_ready_q, lcl_sh_cl_ddr_is_ready[1:0]};

assign all_ddr_scrb_done = {ddrc_scrb_bus.done, ddrd_scrb_bus.done, ddrb_scrb_bus.done, ddra_scrb_bus.done};


///////////////////////////////////////////////////////////////////////
///////////////// Scrubber enable and status //////////////////////////
///////////////////////////////////////////////////////////////////////


///////////////////////////////////////////////////////////////////////
///////////////// DMA PCIS SLAVE module ///////////////////////////////
///////////////////////////////////////////////////////////////////////
 
assign sh_cl_dma_pcis_bus.awvalid = sh_cl_dma_pcis_awvalid;
assign sh_cl_dma_pcis_bus.awaddr = sh_cl_dma_pcis_awaddr;
assign sh_cl_dma_pcis_bus.awid[5:0] = sh_cl_dma_pcis_awid;
assign sh_cl_dma_pcis_bus.awlen = sh_cl_dma_pcis_awlen;
assign sh_cl_dma_pcis_bus.awsize = sh_cl_dma_pcis_awsize;
assign cl_sh_dma_pcis_awready = sh_cl_dma_pcis_bus.awready;
assign sh_cl_dma_pcis_bus.wvalid = sh_cl_dma_pcis_wvalid;
assign sh_cl_dma_pcis_bus.wdata = sh_cl_dma_pcis_wdata;
assign sh_cl_dma_pcis_bus.wstrb = sh_cl_dma_pcis_wstrb;
assign sh_cl_dma_pcis_bus.wlast = sh_cl_dma_pcis_wlast;
assign cl_sh_dma_pcis_wready = sh_cl_dma_pcis_bus.wready;
assign cl_sh_dma_pcis_bvalid = sh_cl_dma_pcis_bus.bvalid;
assign cl_sh_dma_pcis_bresp = sh_cl_dma_pcis_bus.bresp;
assign sh_cl_dma_pcis_bus.bready = sh_cl_dma_pcis_bready;
assign cl_sh_dma_pcis_bid = sh_cl_dma_pcis_bus.bid[5:0];
assign sh_cl_dma_pcis_bus.arvalid = sh_cl_dma_pcis_arvalid;
assign sh_cl_dma_pcis_bus.araddr = sh_cl_dma_pcis_araddr;
assign sh_cl_dma_pcis_bus.arid[5:0] = sh_cl_dma_pcis_arid;
assign sh_cl_dma_pcis_bus.arlen = sh_cl_dma_pcis_arlen;
assign sh_cl_dma_pcis_bus.arsize = sh_cl_dma_pcis_arsize;
assign cl_sh_dma_pcis_arready = sh_cl_dma_pcis_bus.arready;
assign cl_sh_dma_pcis_rvalid = sh_cl_dma_pcis_bus.rvalid;
assign cl_sh_dma_pcis_rid = sh_cl_dma_pcis_bus.rid[5:0];
assign cl_sh_dma_pcis_rlast = sh_cl_dma_pcis_bus.rlast;
assign cl_sh_dma_pcis_rresp = sh_cl_dma_pcis_bus.rresp;
assign cl_sh_dma_pcis_rdata = sh_cl_dma_pcis_bus.rdata;
assign sh_cl_dma_pcis_bus.rready = sh_cl_dma_pcis_rready;

assign cl_sh_ddr_awid = cl_sh_ddr_bus.awid;
assign cl_sh_ddr_awaddr = cl_sh_ddr_bus.awaddr;
assign cl_sh_ddr_awlen = cl_sh_ddr_bus.awlen;
assign cl_sh_ddr_awsize = cl_sh_ddr_bus.awsize;
assign cl_sh_ddr_awvalid = cl_sh_ddr_bus.awvalid;
assign cl_sh_ddr_bus.awready = sh_cl_ddr_awready;
assign cl_sh_ddr_wid = 16'b0;
assign cl_sh_ddr_wdata = cl_sh_ddr_bus.wdata;
assign cl_sh_ddr_wstrb = cl_sh_ddr_bus.wstrb;
assign cl_sh_ddr_wlast = cl_sh_ddr_bus.wlast;
assign cl_sh_ddr_wvalid = cl_sh_ddr_bus.wvalid;
assign cl_sh_ddr_bus.wready = sh_cl_ddr_wready;
assign cl_sh_ddr_bus.bid = sh_cl_ddr_bid;
assign cl_sh_ddr_bus.bresp = sh_cl_ddr_bresp;
assign cl_sh_ddr_bus.bvalid = sh_cl_ddr_bvalid;
assign cl_sh_ddr_bready = cl_sh_ddr_bus.bready;
assign cl_sh_ddr_arid = cl_sh_ddr_bus.arid;
assign cl_sh_ddr_araddr = cl_sh_ddr_bus.araddr;
assign cl_sh_ddr_arlen = cl_sh_ddr_bus.arlen;
assign cl_sh_ddr_arsize = cl_sh_ddr_bus.arsize;
assign cl_sh_ddr_arvalid = cl_sh_ddr_bus.arvalid;
assign cl_sh_ddr_bus.arready = sh_cl_ddr_arready;
assign cl_sh_ddr_bus.rid = sh_cl_ddr_rid;
assign cl_sh_ddr_bus.rresp = sh_cl_ddr_rresp;
assign cl_sh_ddr_bus.rvalid = sh_cl_ddr_rvalid;
assign cl_sh_ddr_bus.rdata = sh_cl_ddr_rdata;
assign cl_sh_ddr_bus.rlast = sh_cl_ddr_rlast;
assign cl_sh_ddr_rready = cl_sh_ddr_bus.rready;

(* dont_touch = "true" *) logic dma_pcis_slv_sync_rst_n;
lib_pipe #(.WIDTH(1), .STAGES(4)) DMA_PCIS_SLV_SLC_RST_N (.clk(clk), .rst_n(1'b1), .in_bus(sync_rst_n), .out_bus(dma_pcis_slv_sync_rst_n));
cl_dma_pcis_slv #(.SCRB_BURST_LEN_MINUS1(DDR_SCRB_BURST_LEN_MINUS1),
                    .SCRB_MAX_ADDR(DDR_SCRB_MAX_ADDR),
                    .NO_SCRB_INST(NO_SCRB_INST)) CL_DMA_PCIS_SLV (
    .aclk(clk),
    .aresetn(dma_pcis_slv_sync_rst_n),

    .ddra_tst_cfg_bus(ddra_tst_cfg_bus),
    .ddrb_tst_cfg_bus(ddrb_tst_cfg_bus),
    .ddrc_tst_cfg_bus(ddrc_tst_cfg_bus),
    .ddrd_tst_cfg_bus(ddrd_tst_cfg_bus),

    .ddra_scrb_bus(ddra_scrb_bus),
    .ddrb_scrb_bus(ddrb_scrb_bus),
    .ddrc_scrb_bus(ddrc_scrb_bus),
    .ddrd_scrb_bus(ddrd_scrb_bus),

    .sh_cl_dma_pcis_bus(sh_cl_dma_pcis_bus),
    .cl_axi_mstr_bus(cl_axi_mstr_bus),

    .lcl_cl_sh_ddra(lcl_cl_sh_ddra),
    .lcl_cl_sh_ddrb(lcl_cl_sh_ddrb),
    .lcl_cl_sh_ddrd(lcl_cl_sh_ddrd),

    .sh_cl_dma_pcis_q(sh_cl_dma_pcis_q),

    .cl_sh_ddr_bus     (cl_sh_ddr_bus)
  );

///////////////////////////////////////////////////////////////////////
///////////////// DMA PCIS SLAVE module ///////////////////////////////
///////////////////////////////////////////////////////////////////////

///////////////////////////////////////////////////////////////////////
///////////////// Secondary AXI Master module /////////////////////////
///////////////////////////////////////////////////////////////////////
cl_dram_dma_axi_mstr  CL_DRAM_DMA_AXI_MSTR (
    .aclk(clk),
    .aresetn(dma_pcis_slv_sync_rst_n),
    .cl_axi_mstr_bus(cl_axi_mstr_bus),
    .axi_mstr_cfg_bus(axi_mstr_cfg_bus)
  );

///////////////////////////////////////////////////////////////////////
///////////////// Secondary AXI Master module /////////////////////////
///////////////////////////////////////////////////////////////////////

///////////////////////////////////////////////////////////////////////
///////////////// PCIM MSTR module ////////////////////////////////////
///////////////////////////////////////////////////////////////////////

assign cl_sh_pcim_awid = cl_sh_pcim_bus.awid;
assign cl_sh_pcim_awaddr = cl_sh_pcim_bus.awaddr;
assign cl_sh_pcim_awlen = cl_sh_pcim_bus.awlen;
assign cl_sh_pcim_awvalid = cl_sh_pcim_bus.awvalid;
assign cl_sh_pcim_awsize = cl_sh_pcim_bus.awsize;
assign cl_sh_pcim_bus.awready = sh_cl_pcim_awready;
assign cl_sh_pcim_wdata = cl_sh_pcim_bus.wdata;
assign cl_sh_pcim_wstrb = cl_sh_pcim_bus.wstrb;
assign cl_sh_pcim_wlast = cl_sh_pcim_bus.wlast;
assign cl_sh_pcim_wvalid = cl_sh_pcim_bus.wvalid;
assign cl_sh_pcim_bus.wready = sh_cl_pcim_wready;
assign cl_sh_pcim_bus.bid = sh_cl_pcim_bid;
assign cl_sh_pcim_bus.bresp = sh_cl_pcim_bresp;
assign cl_sh_pcim_bus.bvalid = sh_cl_pcim_bvalid;
assign cl_sh_pcim_bready = cl_sh_pcim_bus.bready;
assign cl_sh_pcim_arid = cl_sh_pcim_bus.arid;
assign cl_sh_pcim_araddr = cl_sh_pcim_bus.araddr;
assign cl_sh_pcim_arlen = cl_sh_pcim_bus.arlen;
assign cl_sh_pcim_arvalid = cl_sh_pcim_bus.arvalid;
assign cl_sh_pcim_bus.arready = sh_cl_pcim_arready;
assign cl_sh_pcim_arsize = cl_sh_pcim_bus.arsize;
assign cl_sh_pcim_bus.rid = sh_cl_pcim_rid;
assign cl_sh_pcim_bus.rresp = sh_cl_pcim_rresp;
assign cl_sh_pcim_bus.rvalid = sh_cl_pcim_rvalid;
assign cl_sh_pcim_bus.rdata = sh_cl_pcim_rdata;
assign cl_sh_pcim_bus.rlast = sh_cl_pcim_rlast;
assign cl_sh_pcim_rready = cl_sh_pcim_bus.rready;

// note: cl_sh_pcim_aruser/awuser are ignored by the shell
// and the axi4 size is set fixed for 64-bytes
//  cl_sh_pcim_arsize/awsize = 3'b6;

(* dont_touch = "true" *) logic pcim_mstr_sync_rst_n;
lib_pipe #(.WIDTH(1), .STAGES(4)) PCIM_MSTR_SLC_RST_N (.clk(clk), .rst_n(1'b1), .in_bus(sync_rst_n), .out_bus(pcim_mstr_sync_rst_n));
cl_pcim_mstr CL_PCIM_MSTR (

     .aclk(clk),
     .aresetn(pcim_mstr_sync_rst_n),

     .cfg_bus(pcim_tst_cfg_bus),

     .cl_sh_pcim_bus     (cl_sh_pcim_bus)
);

///////////////////////////////////////////////////////////////////////
///////////////// OCL SLAVE module ////////////////////////////////////
///////////////////////////////////////////////////////////////////////

assign sh_ocl_bus.awvalid = sh_ocl_awvalid;
assign sh_ocl_bus.awaddr[31:0] = sh_ocl_awaddr;
assign ocl_sh_awready = sh_ocl_bus.awready;
assign sh_ocl_bus.wvalid = sh_ocl_wvalid;
assign sh_ocl_bus.wdata[31:0] = sh_ocl_wdata;
assign sh_ocl_bus.wstrb[3:0] = sh_ocl_wstrb;
assign ocl_sh_wready = sh_ocl_bus.wready;
assign ocl_sh_bvalid = sh_ocl_bus.bvalid;
assign ocl_sh_bresp = sh_ocl_bus.bresp;
assign sh_ocl_bus.bready = sh_ocl_bready;
assign sh_ocl_bus.arvalid = sh_ocl_arvalid;
assign sh_ocl_bus.araddr[31:0] = sh_ocl_araddr;
assign ocl_sh_arready = sh_ocl_bus.arready;
assign ocl_sh_rvalid = sh_ocl_bus.rvalid;
assign ocl_sh_rresp = sh_ocl_bus.rresp;
assign ocl_sh_rdata = sh_ocl_bus.rdata[31:0];
assign sh_ocl_bus.rready = sh_ocl_rready;

(* dont_touch = "true" *) logic ocl_slv_sync_rst_n;
lib_pipe #(.WIDTH(1), .STAGES(4)) OCL_SLV_SLC_RST_N (.clk(clk), .rst_n(1'b1), .in_bus(sync_rst_n), .out_bus(ocl_slv_sync_rst_n));
cl_ocl_slv CL_OCL_SLV (

   .clk(clk),
   .sync_rst_n(ocl_slv_sync_rst_n),

   .sh_cl_flr_assert_q(sh_cl_flr_assert_q),

   .sh_ocl_bus  (sh_ocl_bus),

   .pcim_tst_cfg_bus(pcim_tst_cfg_bus),
   .ddra_tst_cfg_bus(ddra_tst_cfg_bus),
   .ddrb_tst_cfg_bus(ddrb_tst_cfg_bus),
   .ddrc_tst_cfg_bus(ddrc_tst_cfg_bus),
   .ddrd_tst_cfg_bus(ddrd_tst_cfg_bus),
   .axi_mstr_cfg_bus(axi_mstr_cfg_bus),
   .int_tst_cfg_bus(int_tst_cfg_bus)

);

///////////////////////////////////////////////////////////////////////
///////////////// OCL SLAVE module ////////////////////////////////////
///////////////////////////////////////////////////////////////////////

//----------------------------------------- 
// DDR controller instantiation   
//-----------------------------------------
logic [7:0] sh_ddr_stat_addr_q[2:0];
logic[2:0] sh_ddr_stat_wr_q;
logic[2:0] sh_ddr_stat_rd_q; 
logic[31:0] sh_ddr_stat_wdata_q[2:0];
logic[2:0] ddr_sh_stat_ack_q;
logic[31:0] ddr_sh_stat_rdata_q[2:0];
logic[7:0] ddr_sh_stat_int_q[2:0];


lib_pipe #(.WIDTH(1+1+8+32), .STAGES(NUM_CFG_STGS_CL_DDR_ATG)) PIPE_DDR_STAT0 (.clk(clk), .rst_n(sync_rst_n),
                                               .in_bus({sh_ddr_stat_wr0, sh_ddr_stat_rd0, sh_ddr_stat_addr0, sh_ddr_stat_wdata0}),
                                               .out_bus({sh_ddr_stat_wr_q[0], sh_ddr_stat_rd_q[0], sh_ddr_stat_addr_q[0], sh_ddr_stat_wdata_q[0]})
                                               );


lib_pipe #(.WIDTH(1+8+32), .STAGES(NUM_CFG_STGS_CL_DDR_ATG)) PIPE_DDR_STAT_ACK0 (.clk(clk), .rst_n(sync_rst_n),
                                               .in_bus({ddr_sh_stat_ack_q[0], ddr_sh_stat_int_q[0], ddr_sh_stat_rdata_q[0]}),
                                               .out_bus({ddr_sh_stat_ack0, ddr_sh_stat_int0, ddr_sh_stat_rdata0})
                                               );


lib_pipe #(.WIDTH(1+1+8+32), .STAGES(NUM_CFG_STGS_CL_DDR_ATG)) PIPE_DDR_STAT1 (.clk(clk), .rst_n(sync_rst_n),
                                               .in_bus({sh_ddr_stat_wr1, sh_ddr_stat_rd1, sh_ddr_stat_addr1, sh_ddr_stat_wdata1}),
                                               .out_bus({sh_ddr_stat_wr_q[1], sh_ddr_stat_rd_q[1], sh_ddr_stat_addr_q[1], sh_ddr_stat_wdata_q[1]})
                                               );


lib_pipe #(.WIDTH(1+8+32), .STAGES(NUM_CFG_STGS_CL_DDR_ATG)) PIPE_DDR_STAT_ACK1 (.clk(clk), .rst_n(sync_rst_n),
                                               .in_bus({ddr_sh_stat_ack_q[1], ddr_sh_stat_int_q[1], ddr_sh_stat_rdata_q[1]}),
                                               .out_bus({ddr_sh_stat_ack1, ddr_sh_stat_int1, ddr_sh_stat_rdata1})
                                               );

lib_pipe #(.WIDTH(1+1+8+32), .STAGES(NUM_CFG_STGS_CL_DDR_ATG)) PIPE_DDR_STAT2 (.clk(clk), .rst_n(sync_rst_n),
                                               .in_bus({sh_ddr_stat_wr2, sh_ddr_stat_rd2, sh_ddr_stat_addr2, sh_ddr_stat_wdata2}),
                                               .out_bus({sh_ddr_stat_wr_q[2], sh_ddr_stat_rd_q[2], sh_ddr_stat_addr_q[2], sh_ddr_stat_wdata_q[2]})
                                               );


lib_pipe #(.WIDTH(1+8+32), .STAGES(NUM_CFG_STGS_CL_DDR_ATG)) PIPE_DDR_STAT_ACK2 (.clk(clk), .rst_n(sync_rst_n),
                                               .in_bus({ddr_sh_stat_ack_q[2], ddr_sh_stat_int_q[2], ddr_sh_stat_rdata_q[2]}),
                                               .out_bus({ddr_sh_stat_ack2, ddr_sh_stat_int2, ddr_sh_stat_rdata2})
                                               ); 

//convert to 2D 
logic[15:0] cl_sh_ddr_awid_2d[2:0];
logic[63:0] cl_sh_ddr_awaddr_2d[2:0];
logic[7:0] cl_sh_ddr_awlen_2d[2:0];
logic[2:0] cl_sh_ddr_awsize_2d[2:0];
logic[1:0] cl_sh_ddr_awburst_2d[2:0];
logic cl_sh_ddr_awvalid_2d [2:0];
logic[2:0] sh_cl_ddr_awready_2d;

logic[15:0] cl_sh_ddr_wid_2d[2:0];
logic[511:0] cl_sh_ddr_wdata_2d[2:0];
logic[63:0] cl_sh_ddr_wstrb_2d[2:0];
logic[2:0] cl_sh_ddr_wlast_2d;
logic[2:0] cl_sh_ddr_wvalid_2d;
logic[2:0] sh_cl_ddr_wready_2d;

logic[15:0] sh_cl_ddr_bid_2d[2:0];
logic[1:0] sh_cl_ddr_bresp_2d[2:0];
logic[2:0] sh_cl_ddr_bvalid_2d;
logic[2:0] cl_sh_ddr_bready_2d;

logic[15:0] cl_sh_ddr_arid_2d[2:0];
logic[63:0] cl_sh_ddr_araddr_2d[2:0];
logic[7:0] cl_sh_ddr_arlen_2d[2:0];
logic[2:0] cl_sh_ddr_arsize_2d[2:0];
logic[1:0] cl_sh_ddr_arburst_2d[2:0];
logic[2:0] cl_sh_ddr_arvalid_2d;
logic[2:0] sh_cl_ddr_arready_2d;

logic[15:0] sh_cl_ddr_rid_2d[2:0];
logic[511:0] sh_cl_ddr_rdata_2d[2:0];
logic[1:0] sh_cl_ddr_rresp_2d[2:0];
logic[2:0] sh_cl_ddr_rlast_2d;
logic[2:0] sh_cl_ddr_rvalid_2d;
logic[2:0] cl_sh_ddr_rready_2d;

 logic         tie_zero;
  logic [  1:0] tie_zero_burst;
  logic [ 15:0] tie_zero_id;
  logic [ 63:0] tie_zero_addr;
  logic [  7:0] tie_zero_len;
  logic [511:0] tie_zero_data;
  logic [511:0] tie_zero_rdata;
  logic [ 63:0] tie_zero_strb;
  logic tie_zero_ready;
  logic [ 15:0] tie_zero_bid;
  logic [  1:0] tie_zero_bresp;
  logic [  2:0] tie_zero_rlast;

  logic [63:0] DDR_AXI4_araddr;
  logic [1:0]  DDR_AXI4_arburst;
  logic [3:0]  DDR_AXI4_arcache;
  logic [15:0] DDR_AXI4_arid;
  logic [7:0]  DDR_AXI4_arlen;
  logic [0:0]  DDR_AXI4_arlock;
  logic [2:0]  DDR_AXI4_arprot;
  logic [3:0]  DDR_AXI4_arqos;
  logic [2:0]  DDR_AXI4_arready;
  logic [3:0]  DDR_AXI4_arregion;
  logic [2:0]  DDR_AXI4_arsize;
  logic [0:0]  DDR_AXI4_arvalid;
  logic [63:0] DDR_AXI4_awaddr;
  logic [1:0]  DDR_AXI4_awburst;
  logic [3:0]  DDR_AXI4_awcache;
  logic [15:0] DDR_AXI4_awid;
  logic [7:0]  DDR_AXI4_awlen;
  logic [0:0]  DDR_AXI4_awlock;
  logic [2:0]  DDR_AXI4_awprot;
  logic [3:0]  DDR_AXI4_awqos;
  logic [2:0]  DDR_AXI4_awready;
  logic [3:0]  DDR_AXI4_awregion;
  logic [2:0]  DDR_AXI4_awsize;
  logic [0:0]  DDR_AXI4_awvalid;
  logic [15:0] DDR_AXI4_bid [2:0];
  logic [0:0]  DDR_AXI4_bready;
  logic [1:0]  DDR_AXI4_bresp[2:0];
  logic [2:0]  DDR_AXI4_bvalid;
  logic [511:0]DDR_AXI4_rdata [2:0];
  logic [15:0] DDR_AXI4_rid [2:0];
  logic [2:0]  DDR_AXI4_rlast;
  logic [0:0]  DDR_AXI4_rready;
  logic [1:0]  DDR_AXI4_rresp [2:0];
  logic [2:0]  DDR_AXI4_rvalid;
  logic [511:0]DDR_AXI4_wdata;
  logic [0:0]  DDR_AXI4_wlast;
  logic [2:0]  DDR_AXI4_wready;
  logic [63:0] DDR_AXI4_wstrb;
  logic [0:0]  DDR_AXI4_wvalid;

  assign tie_zero       =   1'b0;
  assign tie_zero_burst  =   2'b01; // Only INCR is supported, must be tied to 2'b01
  assign tie_zero_id     =  16'b0;
  assign tie_zero_addr  =  64'b0;
  assign tie_zero_len    =   8'b0;
  assign tie_zero_data  = 512'b0;
  assign tie_zero_strb   =  64'b0;


assign cl_sh_ddr_awid_2d = '{lcl_cl_sh_ddrd.awid, lcl_cl_sh_ddrb.awid, lcl_cl_sh_ddra.awid};
assign cl_sh_ddr_awaddr_2d = '{lcl_cl_sh_ddrd.awaddr, lcl_cl_sh_ddrb.awaddr, lcl_cl_sh_ddra.awaddr};
assign cl_sh_ddr_awlen_2d = '{lcl_cl_sh_ddrd.awlen, lcl_cl_sh_ddrb.awlen, lcl_cl_sh_ddra.awlen};
assign cl_sh_ddr_awsize_2d = '{lcl_cl_sh_ddrd.awsize, lcl_cl_sh_ddrb.awsize, lcl_cl_sh_ddra.awsize};
assign cl_sh_ddr_awvalid_2d = '{lcl_cl_sh_ddrd.awvalid, lcl_cl_sh_ddrb.awvalid, lcl_cl_sh_ddra.awvalid};
assign cl_sh_ddr_awburst_2d = {2'b01, 2'b01, 2'b01};
assign {lcl_cl_sh_ddrd.awready, lcl_cl_sh_ddrb.awready, lcl_cl_sh_ddra.awready} = sh_cl_ddr_awready_2d;

assign cl_sh_ddr_wid_2d = '{lcl_cl_sh_ddrd.wid, lcl_cl_sh_ddrb.wid, lcl_cl_sh_ddra.wid};
assign cl_sh_ddr_wdata_2d = '{lcl_cl_sh_ddrd.wdata, lcl_cl_sh_ddrb.wdata, lcl_cl_sh_ddra.wdata};
assign cl_sh_ddr_wstrb_2d = '{lcl_cl_sh_ddrd.wstrb, lcl_cl_sh_ddrb.wstrb, lcl_cl_sh_ddra.wstrb};
assign cl_sh_ddr_wlast_2d = {lcl_cl_sh_ddrd.wlast, lcl_cl_sh_ddrb.wlast, lcl_cl_sh_ddra.wlast};
assign cl_sh_ddr_wvalid_2d = {lcl_cl_sh_ddrd.wvalid, lcl_cl_sh_ddrb.wvalid, lcl_cl_sh_ddra.wvalid};
assign {lcl_cl_sh_ddrd.wready, lcl_cl_sh_ddrb.wready, lcl_cl_sh_ddra.wready} = sh_cl_ddr_wready_2d;

assign {lcl_cl_sh_ddrd.bid, lcl_cl_sh_ddrb.bid, lcl_cl_sh_ddra.bid} = {sh_cl_ddr_bid_2d[2], sh_cl_ddr_bid_2d[1], sh_cl_ddr_bid_2d[0]};
assign {lcl_cl_sh_ddrd.bresp, lcl_cl_sh_ddrb.bresp, lcl_cl_sh_ddra.bresp} = {sh_cl_ddr_bresp_2d[2], sh_cl_ddr_bresp_2d[1], sh_cl_ddr_bresp_2d[0]};
assign {lcl_cl_sh_ddrd.bvalid, lcl_cl_sh_ddrb.bvalid, lcl_cl_sh_ddra.bvalid} = sh_cl_ddr_bvalid_2d;
assign cl_sh_ddr_bready_2d = {lcl_cl_sh_ddrd.bready, lcl_cl_sh_ddrb.bready, lcl_cl_sh_ddra.bready};

assign cl_sh_ddr_arid_2d = '{lcl_cl_sh_ddrd.arid, lcl_cl_sh_ddrb.arid, lcl_cl_sh_ddra.arid};
assign cl_sh_ddr_araddr_2d = '{lcl_cl_sh_ddrd.araddr, lcl_cl_sh_ddrb.araddr, lcl_cl_sh_ddra.araddr};
assign cl_sh_ddr_arlen_2d = '{lcl_cl_sh_ddrd.arlen, lcl_cl_sh_ddrb.arlen, lcl_cl_sh_ddra.arlen};
assign cl_sh_ddr_arsize_2d = '{lcl_cl_sh_ddrd.arsize, lcl_cl_sh_ddrb.arsize, lcl_cl_sh_ddra.arsize};
assign cl_sh_ddr_arvalid_2d = {lcl_cl_sh_ddrd.arvalid, lcl_cl_sh_ddrb.arvalid, lcl_cl_sh_ddra.arvalid};
assign cl_sh_ddr_arburst_2d = {2'b01, 2'b01, 2'b01};
assign {lcl_cl_sh_ddrd.arready, lcl_cl_sh_ddrb.arready, lcl_cl_sh_ddra.arready} = sh_cl_ddr_arready_2d;

assign {lcl_cl_sh_ddrd.rid, lcl_cl_sh_ddrb.rid, lcl_cl_sh_ddra.rid} = {sh_cl_ddr_rid_2d[2], sh_cl_ddr_rid_2d[1], sh_cl_ddr_rid_2d[0]};
assign {lcl_cl_sh_ddrd.rresp, lcl_cl_sh_ddrb.rresp, lcl_cl_sh_ddra.rresp} = {sh_cl_ddr_rresp_2d[2], sh_cl_ddr_rresp_2d[1], sh_cl_ddr_rresp_2d[0]};
assign {lcl_cl_sh_ddrd.rdata, lcl_cl_sh_ddrb.rdata, lcl_cl_sh_ddra.rdata} = {sh_cl_ddr_rdata_2d[2], sh_cl_ddr_rdata_2d[1], sh_cl_ddr_rdata_2d[0]};
assign {lcl_cl_sh_ddrd.rlast, lcl_cl_sh_ddrb.rlast, lcl_cl_sh_ddra.rlast} = sh_cl_ddr_rlast_2d;
assign {lcl_cl_sh_ddrd.rvalid, lcl_cl_sh_ddrb.rvalid, lcl_cl_sh_ddra.rvalid} = sh_cl_ddr_rvalid_2d;
assign cl_sh_ddr_rready_2d = {lcl_cl_sh_ddrd.rready, lcl_cl_sh_ddrb.rready, lcl_cl_sh_ddra.rready};

(* dont_touch = "true" *) logic sh_ddr_sync_rst_n;
lib_pipe #(.WIDTH(1), .STAGES(4)) SH_DDR_SLC_RST_N (.clk(clk), .rst_n(1'b1), .in_bus(sync_rst_n), .out_bus(sh_ddr_sync_rst_n));
sh_ddr #(
         .DDR_A_PRESENT(`DDR_A_PRESENT),
         .DDR_B_PRESENT(`DDR_B_PRESENT),
         .DDR_D_PRESENT(`DDR_D_PRESENT)
   ) SH_DDR
   (
   .clk(clk),
   .rst_n(sh_ddr_sync_rst_n),

   .stat_clk(clk),
   .stat_rst_n(sh_ddr_sync_rst_n),


   .CLK_300M_DIMM0_DP(CLK_300M_DIMM0_DP),
   .CLK_300M_DIMM0_DN(CLK_300M_DIMM0_DN),
   .M_A_ACT_N(M_A_ACT_N),
   .M_A_MA(M_A_MA),
   .M_A_BA(M_A_BA),
   .M_A_BG(M_A_BG),
   .M_A_CKE(M_A_CKE),
   .M_A_ODT(M_A_ODT),
   .M_A_CS_N(M_A_CS_N),
   .M_A_CLK_DN(M_A_CLK_DN),
   .M_A_CLK_DP(M_A_CLK_DP),
   .M_A_PAR(M_A_PAR),
   .M_A_DQ(M_A_DQ),
   .M_A_ECC(M_A_ECC),
   .M_A_DQS_DP(M_A_DQS_DP),
   .M_A_DQS_DN(M_A_DQS_DN),
   .cl_RST_DIMM_A_N(cl_RST_DIMM_A_N),
   
   
   .CLK_300M_DIMM1_DP(CLK_300M_DIMM1_DP),
   .CLK_300M_DIMM1_DN(CLK_300M_DIMM1_DN),
   .M_B_ACT_N(M_B_ACT_N),
   .M_B_MA(M_B_MA),
   .M_B_BA(M_B_BA),
   .M_B_BG(M_B_BG),
   .M_B_CKE(M_B_CKE),
   .M_B_ODT(M_B_ODT),
   .M_B_CS_N(M_B_CS_N),
   .M_B_CLK_DN(M_B_CLK_DN),
   .M_B_CLK_DP(M_B_CLK_DP),
   .M_B_PAR(M_B_PAR),
   .M_B_DQ(M_B_DQ),
   .M_B_ECC(M_B_ECC),
   .M_B_DQS_DP(M_B_DQS_DP),
   .M_B_DQS_DN(M_B_DQS_DN),
   .cl_RST_DIMM_B_N(cl_RST_DIMM_B_N),

   .CLK_300M_DIMM3_DP(CLK_300M_DIMM3_DP),
   .CLK_300M_DIMM3_DN(CLK_300M_DIMM3_DN),
   .M_D_ACT_N(M_D_ACT_N),
   .M_D_MA(M_D_MA),
   .M_D_BA(M_D_BA),
   .M_D_BG(M_D_BG),
   .M_D_CKE(M_D_CKE),
   .M_D_ODT(M_D_ODT),
   .M_D_CS_N(M_D_CS_N),
   .M_D_CLK_DN(M_D_CLK_DN),
   .M_D_CLK_DP(M_D_CLK_DP),
   .M_D_PAR(M_D_PAR),
   .M_D_DQ(M_D_DQ),
   .M_D_ECC(M_D_ECC),
   .M_D_DQS_DP(M_D_DQS_DP),
   .M_D_DQS_DN(M_D_DQS_DN),
   .cl_RST_DIMM_D_N(cl_RST_DIMM_D_N),

   //------------------------------------------------------
   // DDR-4 Interface from CL (AXI-4)
   //------------------------------------------------------
   .cl_sh_ddr_awid({tie_zero_id,tie_zero_id,DDR_AXI4_awid}),
   .cl_sh_ddr_awaddr({tie_zero_addr,tie_zero_addr,DDR_AXI4_awaddr}),
   .cl_sh_ddr_awlen({tie_zero_len,tie_zero_len,DDR_AXI4_awlen}),
   .cl_sh_ddr_awsize({'b0,'b0,DDR_AXI4_awsize}),
   .cl_sh_ddr_awvalid({tie_zero,tie_zero,DDR_AXI4_awvalid}),
   .cl_sh_ddr_awburst({tie_zero_burst,tie_zero_burst,DDR_AXI4_awburst}),
   .sh_cl_ddr_awready({tie_zero_ready,tie_zero_ready,DDR_AXI4_awready}),

   .cl_sh_ddr_wid({tie_zero_id,tie_zero_id,tie_zero_id}),
   .cl_sh_ddr_wdata({tie_zero_data,tie_zero_data,DDR_AXI4_wdata}),
   .cl_sh_ddr_wstrb({tie_zero_strb,tie_zero_strb,DDR_AXI4_wstrb}),
   .cl_sh_ddr_wlast({'b0,'b0,DDR_AXI4_wlast}),
   .cl_sh_ddr_wvalid({'b0,'b0,DDR_AXI4_wvalid}),
   .sh_cl_ddr_wready({tie_zero_ready,tie_zero_ready,DDR_AXI4_wready}),

   .sh_cl_ddr_bid(DDR_AXI4_bid),
   .sh_cl_ddr_bresp(DDR_AXI4_bresp),
   .sh_cl_ddr_bvalid(DDR_AXI4_bvalid),
   .cl_sh_ddr_bready({'b0,'b0,DDR_AXI4_bready}),

   .cl_sh_ddr_arid({tie_zero_id,tie_zero_id,DDR_AXI4_arid}),
   .cl_sh_ddr_araddr({tie_zero_addr,tie_zero_addr,DDR_AXI4_araddr}),
   .cl_sh_ddr_arlen({tie_zero_len,tie_zero_len,DDR_AXI4_arlen}),
   .cl_sh_ddr_arsize({'b0,'b0,DDR_AXI4_arsize}),
   .cl_sh_ddr_arvalid({tie_zero,tie_zero,DDR_AXI4_arvalid}),
   .cl_sh_ddr_arburst({tie_zero_burst,tie_zero_burst,DDR_AXI4_arburst}),
   .sh_cl_ddr_arready(DDR_AXI4_arready),

   .sh_cl_ddr_rid(DDR_AXI4_rid),
   .sh_cl_ddr_rdata(DDR_AXI4_rdata),
   .sh_cl_ddr_rresp(DDR_AXI4_rresp),
   .sh_cl_ddr_rlast(DDR_AXI4_rlast),
   .sh_cl_ddr_rvalid(DDR_AXI4_rvalid),
   .cl_sh_ddr_rready({'b0,'b0,DDR_AXI4_rready}),

   .sh_cl_ddr_is_ready(lcl_sh_cl_ddr_is_ready),

   .sh_ddr_stat_addr0  (sh_ddr_stat_addr_q[0]) ,
   .sh_ddr_stat_wr0    (sh_ddr_stat_wr_q[0]     ) , 
   .sh_ddr_stat_rd0    (sh_ddr_stat_rd_q[0]     ) , 
   .sh_ddr_stat_wdata0 (sh_ddr_stat_wdata_q[0]  ) , 
   .ddr_sh_stat_ack0   (ddr_sh_stat_ack_q[0]    ) ,
   .ddr_sh_stat_rdata0 (ddr_sh_stat_rdata_q[0]  ),
   .ddr_sh_stat_int0   (ddr_sh_stat_int_q[0]    ),

   .sh_ddr_stat_addr1  (sh_ddr_stat_addr_q[1]) ,
   .sh_ddr_stat_wr1    (sh_ddr_stat_wr_q[1]     ) , 
   .sh_ddr_stat_rd1    (sh_ddr_stat_rd_q[1]     ) , 
   .sh_ddr_stat_wdata1 (sh_ddr_stat_wdata_q[1]  ) , 
   .ddr_sh_stat_ack1   (ddr_sh_stat_ack_q[1]    ) ,
   .ddr_sh_stat_rdata1 (ddr_sh_stat_rdata_q[1]  ),
   .ddr_sh_stat_int1   (ddr_sh_stat_int_q[1]    ),

   .sh_ddr_stat_addr2  (sh_ddr_stat_addr_q[2]) ,
   .sh_ddr_stat_wr2    (sh_ddr_stat_wr_q[2]     ) , 
   .sh_ddr_stat_rd2    (sh_ddr_stat_rd_q[2]     ) , 
   .sh_ddr_stat_wdata2 (sh_ddr_stat_wdata_q[2]  ) , 
   .ddr_sh_stat_ack2   (ddr_sh_stat_ack_q[2]    ) ,
   .ddr_sh_stat_rdata2 (ddr_sh_stat_rdata_q[2]  ),
   .ddr_sh_stat_int2   (ddr_sh_stat_int_q[2]    ) 
   );

  

logic pre_sync_rst_n0;
logic rst_main_n_sync;

always_ff @(negedge rst_main_n or posedge clk_main_a0)
   if (!rst_main_n)
   begin
      pre_sync_rst_n0  <= 0;
      rst_main_n_sync <= 0;
   end
   else
   begin
      pre_sync_rst_n0  <= 1;
      rst_main_n_sync <= pre_sync_rst_n0;
   end

   cl_test cl_nova_project(
   .s_axi_aclk_0      (clk),
   .arst_n            (sh_cl_status_vdip[0]), // su
   .arst_ndm_n        (sh_cl_status_vdip[0]), // su dbg
   .s_axi_aresetn_0   (sh_ddr_sync_rst_n), // xilinx

   
    // Slave
   .BAR1_AXIL_32_araddr  ({32'b0,sh_bar1_araddr}),
   .BAR1_AXIL_32_arprot  ('0),
   .BAR1_AXIL_32_arready (bar1_sh_arready),
   .BAR1_AXIL_32_arvalid (sh_bar1_arvalid),
   .BAR1_AXIL_32_awaddr  ({32'b0,sh_bar1_awaddr}),
   .BAR1_AXIL_32_awprot  ('0),
   .BAR1_AXIL_32_awready (bar1_sh_awready),
   .BAR1_AXIL_32_awvalid (sh_bar1_awvalid),
   .BAR1_AXIL_32_bready  (sh_bar1_bready),
   .BAR1_AXIL_32_bresp   (bar1_sh_bresp),
   .BAR1_AXIL_32_bvalid  (bar1_sh_bvalid),
   .BAR1_AXIL_32_rdata   (bar1_sh_rdata),
   .BAR1_AXIL_32_rready  (sh_bar1_rready),
   .BAR1_AXIL_32_rresp   (bar1_sh_rresp),
   .BAR1_AXIL_32_rvalid  (bar1_sh_rvalid),
   .BAR1_AXIL_32_wdata   (sh_bar1_wdata),
   .BAR1_AXIL_32_wready  (bar1_sh_wready),
   .BAR1_AXIL_32_wstrb   (sh_bar1_wstrb),
   .BAR1_AXIL_32_wvalid  (sh_bar1_wvalid),

    .DDR_AXI4_araddr  (DDR_AXI4_araddr),
    .DDR_AXI4_arburst (DDR_AXI4_arburst),
    //.DDR_AXI4_arcache(),
    .DDR_AXI4_arid    (DDR_AXI4_arid),
    .DDR_AXI4_arlen   (DDR_AXI4_arlen),
    //.DDR_AXI4_arlock(),
    //.DDR_AXI4_arprot(),
    //.DDR_AXI4_arqos(),
    .DDR_AXI4_arready (DDR_AXI4_arready[0]),
    //.DDR_AXI4_arregion(),
    .DDR_AXI4_arsize  (DDR_AXI4_arsize),     //not 
    .DDR_AXI4_arvalid (DDR_AXI4_arvalid),
    .DDR_AXI4_awaddr  (DDR_AXI4_awaddr),
    .DDR_AXI4_awburst (DDR_AXI4_awburst),
    //.DDR_AXI4_awcache(),
    .DDR_AXI4_awid    (DDR_AXI4_awid),
    .DDR_AXI4_awlen   (DDR_AXI4_awlen),
    //.DDR_AXI4_awlock(),
    //.DDR_AXI4_awprot(),
    //.DDR_AXI4_awqos(),
    .DDR_AXI4_awready (DDR_AXI4_awready),
    //.DDR_AXI4_awregion(),
    .DDR_AXI4_awsize  (DDR_AXI4_awsize),    //not
    .DDR_AXI4_awvalid (DDR_AXI4_awvalid),
    .DDR_AXI4_bid     (DDR_AXI4_bid[0]),
    .DDR_AXI4_bready  (DDR_AXI4_bready),
    .DDR_AXI4_bresp   (DDR_AXI4_bresp[0]),
    .DDR_AXI4_bvalid  (DDR_AXI4_bvalid[0]),
    .DDR_AXI4_rdata   (DDR_AXI4_rdata[0]),
    .DDR_AXI4_rid     (DDR_AXI4_rid[0]),
    .DDR_AXI4_rlast   (DDR_AXI4_rlast[0]),
    .DDR_AXI4_rready  (DDR_AXI4_rready),
    .DDR_AXI4_rresp   (DDR_AXI4_rresp[0]),
    .DDR_AXI4_rvalid  (DDR_AXI4_rvalid[0]),
    .DDR_AXI4_wdata   (DDR_AXI4_wdata),
    .DDR_AXI4_wlast   (DDR_AXI4_wlast),
    .DDR_AXI4_wready  (DDR_AXI4_wready),
    .DDR_AXI4_wstrb   (DDR_AXI4_wstrb),
    .DDR_AXI4_wvalid  (DDR_AXI4_wvalid),
    .interrupt        (cl_sh_status_vled[0]),
        .DMA_PCIS_AXI4_araddr   (cl_sh_ddr_araddr_2d[0]),
        .DMA_PCIS_AXI4_arburst  (cl_sh_ddr_arburst_2d[0]),
        .DMA_PCIS_AXI4_arcache  ('b0),
        .DMA_PCIS_AXI4_arid     (cl_sh_ddr_arid_2d[0]),
        .DMA_PCIS_AXI4_arlen    (cl_sh_ddr_arlen_2d[0]),
        .DMA_PCIS_AXI4_arlock   ('b0),
        .DMA_PCIS_AXI4_arprot   ('b0),
        .DMA_PCIS_AXI4_arqos    ('b0),
        .DMA_PCIS_AXI4_arready  (sh_cl_ddr_arready_2d[0]),
        .DMA_PCIS_AXI4_arsize   (cl_sh_ddr_arsize_2d[0]),
        .DMA_PCIS_AXI4_arvalid  (cl_sh_ddr_arvalid_2d[0]),
        .DMA_PCIS_AXI4_awaddr   (cl_sh_ddr_awaddr_2d[0]),
        .DMA_PCIS_AXI4_awburst  (cl_sh_ddr_awburst_2d[0]),
        .DMA_PCIS_AXI4_awcache  ('b0),
        .DMA_PCIS_AXI4_awid     (cl_sh_ddr_awid_2d[0]),
        .DMA_PCIS_AXI4_awlen    (cl_sh_ddr_awlen_2d[0]),
        .DMA_PCIS_AXI4_awlock   ('b0),
        .DMA_PCIS_AXI4_awprot   ('b0),
        .DMA_PCIS_AXI4_awqos    ('b0),
        .DMA_PCIS_AXI4_awready  (sh_cl_ddr_awready_2d[0]),
        .DMA_PCIS_AXI4_awsize   (cl_sh_ddr_awsize_2d[0]),
        .DMA_PCIS_AXI4_awvalid  (cl_sh_ddr_awvalid_2d[0]),
        .DMA_PCIS_AXI4_bid      (sh_cl_ddr_bid_2d[0]),
        .DMA_PCIS_AXI4_bready   (cl_sh_ddr_bready_2d[0]),
        .DMA_PCIS_AXI4_bresp    (sh_cl_ddr_bresp_2d[0]),
        .DMA_PCIS_AXI4_bvalid   (sh_cl_ddr_bvalid_2d[0]),
        .DMA_PCIS_AXI4_rdata    (sh_cl_ddr_rdata_2d[0]),
        .DMA_PCIS_AXI4_rid      (sh_cl_ddr_rid_2d[0]),
        .DMA_PCIS_AXI4_rlast    (sh_cl_ddr_rlast_2d[0]),
        .DMA_PCIS_AXI4_rready   (cl_sh_ddr_rready_2d[0]),
        .DMA_PCIS_AXI4_rresp    (sh_cl_ddr_rresp_2d[0]),
        .DMA_PCIS_AXI4_rvalid   (sh_cl_ddr_rvalid_2d[0]),
        .DMA_PCIS_AXI4_wdata    (cl_sh_ddr_wdata_2d[0]),
        .DMA_PCIS_AXI4_wlast    (cl_sh_ddr_wlast_2d[0]),
        .DMA_PCIS_AXI4_wready   (sh_cl_ddr_wready_2d[0]),
        .DMA_PCIS_AXI4_wstrb    (cl_sh_ddr_wstrb_2d[0]),
        .DMA_PCIS_AXI4_wvalid   (cl_sh_ddr_wvalid_2d[0]),

        .OCL_AXIL_32_araddr   ('b0),
        .OCL_AXIL_32_arprot   ('b0),
        .OCL_AXIL_32_arready  (),
        .OCL_AXIL_32_arvalid  ('b0),
        .OCL_AXIL_32_awaddr   ('b0),
        .OCL_AXIL_32_awprot   ('b0),
        .OCL_AXIL_32_awready  (),
        .OCL_AXIL_32_awvalid  ('b0),
        .OCL_AXIL_32_bready   ('b0),
        .OCL_AXIL_32_bresp    (),
        .OCL_AXIL_32_bvalid   (),
        .OCL_AXIL_32_rdata    (),
        .OCL_AXIL_32_rready   ('b0),
        .OCL_AXIL_32_rresp    (),
        .OCL_AXIL_32_rvalid   (),
        .OCL_AXIL_32_wdata    ('b0),
        .OCL_AXIL_32_wready   (),
        .OCL_AXIL_32_wstrb    ('b0),
        .OCL_AXIL_32_wvalid   ('b0)

   
 );

//----------------------------------------- 
// DDR controller instantiation   
//-----------------------------------------


//----------------------------------------- 
// Interrrupt example  
//-----------------------------------------

(* dont_touch = "true" *) logic int_slv_sync_rst_n;
lib_pipe #(.WIDTH(1), .STAGES(4)) INT_SLV_SLC_RST_N (.clk(clk), .rst_n(1'b1), .in_bus(sync_rst_n), .out_bus(int_slv_sync_rst_n));
cl_int_slv CL_INT_TST 
(
  .clk                 (clk),
  .rst_n               (int_slv_sync_rst_n),

  .cfg_bus             (int_tst_cfg_bus),

  .cl_sh_apppf_irq_req (cl_sh_apppf_irq_req),
  .sh_cl_apppf_irq_ack (sh_cl_apppf_irq_ack)
       
);

//----------------------------------------- 
// Interrrupt example  
//-----------------------------------------

//----------------------------------------- 
// SDA SLAVE module 
//-----------------------------------------


assign sda_cl_bus.awvalid = sda_cl_awvalid;
assign sda_cl_bus.awaddr[31:0] = sda_cl_awaddr;
assign cl_sda_awready = sda_cl_bus.awready;
assign sda_cl_bus.wvalid = sda_cl_wvalid;
assign sda_cl_bus.wdata[31:0] = sda_cl_wdata;
assign sda_cl_bus.wstrb[3:0] = sda_cl_wstrb;
assign cl_sda_wready = sda_cl_bus.wready;
assign cl_sda_bvalid = sda_cl_bus.bvalid;
assign cl_sda_bresp = sda_cl_bus.bresp;
assign sda_cl_bus.bready = sda_cl_bready;
assign sda_cl_bus.arvalid = sda_cl_arvalid;
assign sda_cl_bus.araddr[31:0] = sda_cl_araddr;
assign cl_sda_arready = sda_cl_bus.arready;
assign cl_sda_rvalid = sda_cl_bus.rvalid;
assign cl_sda_rresp = sda_cl_bus.rresp;
assign cl_sda_rdata = sda_cl_bus.rdata[31:0];
assign sda_cl_bus.rready = sda_cl_rready;

(* dont_touch = "true" *) logic sda_slv_sync_rst_n;
lib_pipe #(.WIDTH(1), .STAGES(4)) SDA_SLV_SLC_RST_N (.clk(clk), .rst_n(1'b1), .in_bus(sync_rst_n), .out_bus(sda_slv_sync_rst_n));
cl_sda_slv CL_SDA_SLV (

  .aclk(clk),
  .aresetn(sda_slv_sync_rst_n),
  
  .sda_cl_bus(sda_cl_bus)
);

//----------------------------------------- 
// SDA SLAVE module 
//-----------------------------------------


//----------------------------------------- 
// Virtual JTAG ILA Debug core example 
//-----------------------------------------


`ifndef DISABLE_VJTAG_DEBUG

   cl_ila #(.DDR_A_PRESENT(`DDR_A_PRESENT) ) CL_ILA   (

   .aclk(clk),
   .drck(drck),
   .shift(shift),
      .tdi(tdi),
   .update(update),
   .sel(sel),
   .tdo(tdo),
   .tms(tms),
   .tck(tck),
   .runtest(runtest),
   .reset(reset),
   .capture(capture),
   .bscanid_en(bscanid_en),
   .sh_cl_dma_pcis_q(sh_cl_dma_pcis_q),
`ifndef DDR_A_ABSENT   
   .lcl_cl_sh_ddra(lcl_cl_sh_ddra)
`else
   .lcl_cl_sh_ddra(axi_bus_tied)
`endif
);

cl_vio CL_VIO (

   .clk_extra_a1(clk_extra_a1)

);


`endif //  `ifndef DISABLE_VJTAG_DEBUG

//----------------------------------------- 
// Virtual JATG ILA Debug core example 
//-----------------------------------------
// tie off for ILA port when probing block not present
   assign axi_bus_tied.awvalid = 1'b0 ;
   assign axi_bus_tied.awaddr = 64'b0 ;
   assign axi_bus_tied.awready = 1'b0 ;
   assign axi_bus_tied.wvalid = 1'b0 ;
   assign axi_bus_tied.wstrb = 64'b0 ;
   assign axi_bus_tied.wlast = 1'b0 ;
   assign axi_bus_tied.wready = 1'b0 ;
   assign axi_bus_tied.wdata = 512'b0 ;
   assign axi_bus_tied.arready = 1'b0 ;
   assign axi_bus_tied.rdata = 512'b0 ;
   assign axi_bus_tied.araddr = 64'b0 ;
   assign axi_bus_tied.arvalid = 1'b0 ;
   assign axi_bus_tied.awid = 16'b0 ;
   assign axi_bus_tied.arid = 16'b0 ;
   assign axi_bus_tied.awlen = 8'b0 ;
   assign axi_bus_tied.rlast = 1'b0 ;
   assign axi_bus_tied.rresp = 2'b0 ;
   assign axi_bus_tied.rid = 16'b0 ;
   assign axi_bus_tied.rvalid = 1'b0 ;
   assign axi_bus_tied.arlen = 8'b0 ;
   assign axi_bus_tied.bresp = 2'b0 ;
   assign axi_bus_tied.rready = 1'b0 ;
   assign axi_bus_tied.bvalid = 1'b0 ;
   assign axi_bus_tied.bid = 16'b0 ;
   assign axi_bus_tied.bready = 1'b0 ;


// Temporal workaround until these signals removed from the shell

     assign cl_sh_pcim_awuser = 18'h0;
     assign cl_sh_pcim_aruser = 18'h0;


endmodule   
