
module cl_nova #(parameter NUM_PCIE=1, parameter NUM_DDR=4, parameter NUM_HMC=4, parameter NUM_GTY = 4) 
(
   `include "cl_ports.vh" // Fixed port definition
);
  `include "cl_common_defines.vh"  // CL Defines for all examples
  `include "cl_id_defines.vh"      // Defines for ID0 and ID1 (PCI ID's)
  `include "nova_project_defines.vh"   // CL Defines for cl_nova1

  localparam NUM_CFG_STGS_INT_TST = 4;
  localparam NUM_CFG_STGS_HMC_ATG = 4;
  localparam NUM_CFG_STGS_CL_DDR_ATG = 4;
  localparam NUM_CFG_STGS_SH_DDR_ATG = 4;
  localparam NUM_CFG_STGS_PCIE_ATG = 4;
  localparam NUM_CFG_STGS_AURORA_ATG = 4;
  localparam NUM_CFG_STGS_XDCFG = 4;
  localparam NUM_CFG_STGS_XDMA = 4;
   
`ifdef SIM
  localparam DDR_SCRB_MAX_ADDR = 64'h1FFF;
  localparam HMC_SCRB_MAX_ADDR = 64'h7FF;
`else   
  localparam DDR_SCRB_MAX_ADDR = 64'h3FFFFFFFF; //16GB 
  localparam HMC_SCRB_MAX_ADDR = 64'h7FFFFFFF;  // 2GB
`endif
  localparam DDR_SCRB_BURST_LEN_MINUS1 = 15;
  localparam HMC_SCRB_BURST_LEN_MINUS1 = 3;

logic rst_main_n_sync;
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

logic [7:0] sh_ddr_stat_addr_q[2:0];
logic[2:0] sh_ddr_stat_wr_q;
logic[2:0] sh_ddr_stat_rd_q; 
logic[31:0] sh_ddr_stat_wdata_q[2:0];
logic[2:0] ddr_sh_stat_ack_q;
logic[31:0] ddr_sh_stat_rdata_q[2:0];
logic[7:0] ddr_sh_stat_int_q[2:0];

  logic         tie_zero;
  logic [  1:0] tie_zero_burst;
  logic [ 15:0] tie_zero_id;
  logic [ 63:0] tie_zero_addr;
  logic [  7:0] tie_zero_len;
  logic [511:0] tie_zero_data;
  logic [511:0] tie_zero_rdata;
  logic [ 63:0] tie_zero_strb;
  logic         tie_zero_ready;
  logic [ 15:0] tie_zero_bid;
  logic [  1:0] tie_zero_bresp;
  logic [  2:0] tie_zero_rlast;
  logic [  2:0] tie_zero_rlast;


  assign         tie_zero = 'b0;
  assign tie_zero_burst = 'b0;
  assign tie_zero_id = 'b0;
  assign tie_zero_addr = 'b0;
  assign tie_zero_len = 'b0;
  assign tie_zero_data = 'b0;
  assign tie_zero_rdata = 'b0;
  assign tie_zero_strb = 'b0;
  assign tie_zero_ready = 'b0;
  assign  tie_zero_bid = 'b0;
  assign  tie_zero_bresp = 'b0;
  assign  tie_zero_rlast = 'b0;

//--------------------------------------------0
// Start with Tie-Off of Unused Interfaces
//---------------------------------------------
// the developer should use the next set of `include
// to properly tie-off any unused interface
// The list is put in the top of the module
// to avoid cases where developer may forget to
// remove it from the end of the file

`include "unused_flr_template.inc"
//`include "unused_ddr_a_b_d_template.inc"
`include "unused_ddr_c_template.inc"
`include "unused_pcim_template.inc"
//`include "unused_dma_pcis_template.inc"
`include "unused_cl_sda_template.inc"
// `include "unused_sh_bar1_template.inc"
`include "unused_apppf_irq_template.inc"
//`include "unused_sh_ocl_template.inc"

//-------------------------------------------------
// ID Values (cl_nova1_defines.vh)
//-------------------------------------------------
  assign cl_sh_id0[31:0] = `CL_SH_ID0;
  assign cl_sh_id1[31:0] = `CL_SH_ID1;
  assign cl_sh_ddr_awburst = 2'b01;
  assign cl_sh_ddr_arburst = 2'b01;

//-------------------------------------------------
// Reset Synchronization
//-------------------------------------------------
logic pre_sync_rst_n;

always_ff @(negedge rst_main_n or posedge clk_main_a0)
   if (!rst_main_n)
   begin
      pre_sync_rst_n  <= 0;
      rst_main_n_sync <= 0;
   end
   else
   begin
      pre_sync_rst_n  <= 1;
      rst_main_n_sync <= pre_sync_rst_n;
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

 sh_ddr #(
         .DDR_A_PRESENT(1),
         .DDR_B_PRESENT(1),
         .DDR_D_PRESENT(1)
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

   .sh_cl_ddr_is_ready(is_ready),

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
    
endmodule


