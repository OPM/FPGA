// This is a generated file. Use and modify at your own risk.
//////////////////////////////////////////////////////////////////////////////// 

// default_nettype of none prevents implicit wire declaration.
`default_nettype none
`timescale 1 ns / 1 ps
// Top level of the kernel. Do not modify module name, parameters or ports.

// WARNING: kernel name is shortened and changed (removed "_solver", replaces '-'
// with '_') because of SDx/Vitis limitations in the kernel name length/allowed
// characters
module bicgstab_2r_3r3w_rtl_v1 #(
  parameter integer C_S_AXI_CONTROL_ADDR_WIDTH = 12 ,
  parameter integer C_S_AXI_CONTROL_DATA_WIDTH = 32 ,
  parameter integer C_M00_AXI_ADDR_WIDTH       = 64 ,
  parameter integer C_M00_AXI_DATA_WIDTH       = 512,
  parameter integer C_M01_AXI_ADDR_WIDTH       = 64 ,
  parameter integer C_M01_AXI_DATA_WIDTH       = 512,
  parameter integer C_M02_AXI_ADDR_WIDTH       = 64 ,
  parameter integer C_M02_AXI_DATA_WIDTH       = 512,
  parameter integer C_M03_AXI_ADDR_WIDTH       = 64 ,
  parameter integer C_M03_AXI_DATA_WIDTH       = 512,
  parameter integer C_M04_AXI_ADDR_WIDTH       = 64 ,
  parameter integer C_M04_AXI_DATA_WIDTH       = 512,
  parameter integer C_M05_AXI_ADDR_WIDTH       = 64 ,
  parameter integer C_M05_AXI_DATA_WIDTH       = 512,
  parameter integer C_M06_AXI_ADDR_WIDTH       = 64 ,
  parameter integer C_M06_AXI_DATA_WIDTH       = 512,
  parameter integer C_M07_AXI_ADDR_WIDTH       = 64 ,
  parameter integer C_M07_AXI_DATA_WIDTH       = 512,
  parameter integer C_M08_AXI_ADDR_WIDTH       = 64 ,
  parameter integer C_M08_AXI_DATA_WIDTH       = 512
)
(
  // System Signals
  input  wire                                    ap_clk               ,
  input  wire                                    ap_rst_n             ,
  //input  wire                                    ap_clk_2             ,
  //input  wire                                    ap_rst_n_2           ,
  //  Note: A minimum subset of AXI4 memory mapped signals are declared.  AXI
  // signals omitted from these interfaces are automatically inferred with the
  // optimal values for Xilinx accleration platforms.  This allows Xilinx AXI4 Interconnects
  // within the system to be optimized by removing logic for AXI4 protocol
  // features that are not necessary. When adapting AXI4 masters within the RTL
  // kernel that have signals not declared below, it is suitable to add the
  // signals to the declarations below to connect them to the AXI4 Master.
  // 
  // List of ommited signals - effect
  // -------------------------------
  // ID - Transaction ID are used for multithreading and out of order
  // transactions.  This increases complexity. This saves logic and increases Fmax
  // in the system when ommited.
  // SIZE - Default value is log2(data width in bytes). Needed for subsize bursts.
  // This saves logic and increases Fmax in the system when ommited.
  // BURST - Default value (0b01) is incremental.  Wrap and fixed bursts are not
  // recommended. This saves logic and increases Fmax in the system when ommited.
  // LOCK - Not supported in AXI4
  // CACHE - Default value (0b0011) allows modifiable transactions. No benefit to
  // changing this.
  // PROT - Has no effect in current acceleration platforms.
  // QOS - Has no effect in current acceleration platforms.
  // REGION - Has no effect in current acceleration platforms.
  // USER - Has no effect in current acceleration platforms.
  // RESP - Not useful in most acceleration platforms.
  // 
  // AXI4 master interface m00_axi
  output wire                                    m00_axi_awvalid      ,
  input  wire                                    m00_axi_awready      ,
  output wire [C_M00_AXI_ADDR_WIDTH-1:0]         m00_axi_awaddr       ,
  output wire [8-1:0]                            m00_axi_awlen        ,
  output wire                                    m00_axi_wvalid       ,
  input  wire                                    m00_axi_wready       ,
  output wire [C_M00_AXI_DATA_WIDTH-1:0]         m00_axi_wdata        ,
  output wire [C_M00_AXI_DATA_WIDTH/8-1:0]       m00_axi_wstrb        ,
  output wire                                    m00_axi_wlast        ,
  input  wire                                    m00_axi_bvalid       ,
  output wire                                    m00_axi_bready       ,
  output wire                                    m00_axi_arvalid      ,
  input  wire                                    m00_axi_arready      ,
  output wire [C_M00_AXI_ADDR_WIDTH-1:0]         m00_axi_araddr       ,
  output wire [8-1:0]                            m00_axi_arlen        ,
  input  wire                                    m00_axi_rvalid       ,
  output wire                                    m00_axi_rready       ,
  input  wire [C_M00_AXI_DATA_WIDTH-1:0]         m00_axi_rdata        ,
  input  wire                                    m00_axi_rlast        ,
  // AXI4 master interface m01_axi
  output wire                                    m01_axi_awvalid      ,
  input  wire                                    m01_axi_awready      ,
  output wire [C_M01_AXI_ADDR_WIDTH-1:0]         m01_axi_awaddr       ,
  output wire [8-1:0]                            m01_axi_awlen        ,
  output wire                                    m01_axi_wvalid       ,
  input  wire                                    m01_axi_wready       ,
  output wire [C_M01_AXI_DATA_WIDTH-1:0]         m01_axi_wdata        ,
  output wire [C_M01_AXI_DATA_WIDTH/8-1:0]       m01_axi_wstrb        ,
  output wire                                    m01_axi_wlast        ,
  input  wire                                    m01_axi_bvalid       ,
  output wire                                    m01_axi_bready       ,
  output wire                                    m01_axi_arvalid      ,
  input  wire                                    m01_axi_arready      ,
  output wire [C_M01_AXI_ADDR_WIDTH-1:0]         m01_axi_araddr       ,
  output wire [8-1:0]                            m01_axi_arlen        ,
  input  wire                                    m01_axi_rvalid       ,
  output wire                                    m01_axi_rready       ,
  input  wire [C_M01_AXI_DATA_WIDTH-1:0]         m01_axi_rdata        ,
  input  wire                                    m01_axi_rlast        ,
  // AXI4 master interface m02_axi
  output wire                                    m02_axi_awvalid      ,
  input  wire                                    m02_axi_awready      ,
  output wire [C_M02_AXI_ADDR_WIDTH-1:0]         m02_axi_awaddr       ,
  output wire [8-1:0]                            m02_axi_awlen        ,
  output wire                                    m02_axi_wvalid       ,
  input  wire                                    m02_axi_wready       ,
  output wire [C_M02_AXI_DATA_WIDTH-1:0]         m02_axi_wdata        ,
  output wire [C_M02_AXI_DATA_WIDTH/8-1:0]       m02_axi_wstrb        ,
  output wire                                    m02_axi_wlast        ,
  input  wire                                    m02_axi_bvalid       ,
  output wire                                    m02_axi_bready       ,
  output wire                                    m02_axi_arvalid      ,
  input  wire                                    m02_axi_arready      ,
  output wire [C_M02_AXI_ADDR_WIDTH-1:0]         m02_axi_araddr       ,
  output wire [8-1:0]                            m02_axi_arlen        ,
  input  wire                                    m02_axi_rvalid       ,
  output wire                                    m02_axi_rready       ,
  input  wire [C_M02_AXI_DATA_WIDTH-1:0]         m02_axi_rdata        ,
  input  wire                                    m02_axi_rlast        ,
  // AXI4 master interface m03_axi
  output wire                                    m03_axi_awvalid      ,
  input  wire                                    m03_axi_awready      ,
  output wire [C_M03_AXI_ADDR_WIDTH-1:0]         m03_axi_awaddr       ,
  output wire [8-1:0]                            m03_axi_awlen        ,
  output wire                                    m03_axi_wvalid       ,
  input  wire                                    m03_axi_wready       ,
  output wire [C_M03_AXI_DATA_WIDTH-1:0]         m03_axi_wdata        ,
  output wire [C_M03_AXI_DATA_WIDTH/8-1:0]       m03_axi_wstrb        ,
  output wire                                    m03_axi_wlast        ,
  input  wire                                    m03_axi_bvalid       ,
  output wire                                    m03_axi_bready       ,
  output wire                                    m03_axi_arvalid      ,
  input  wire                                    m03_axi_arready      ,
  output wire [C_M03_AXI_ADDR_WIDTH-1:0]         m03_axi_araddr       ,
  output wire [8-1:0]                            m03_axi_arlen        ,
  input  wire                                    m03_axi_rvalid       ,
  output wire                                    m03_axi_rready       ,
  input  wire [C_M03_AXI_DATA_WIDTH-1:0]         m03_axi_rdata        ,
  input  wire                                    m03_axi_rlast        ,
  // AXI4 master interface m04_axi
  output wire                                    m04_axi_awvalid      ,
  input  wire                                    m04_axi_awready      ,
  output wire [C_M04_AXI_ADDR_WIDTH-1:0]         m04_axi_awaddr       ,
  output wire [8-1:0]                            m04_axi_awlen        ,
  output wire                                    m04_axi_wvalid       ,
  input  wire                                    m04_axi_wready       ,
  output wire [C_M04_AXI_DATA_WIDTH-1:0]         m04_axi_wdata        ,
  output wire [C_M04_AXI_DATA_WIDTH/8-1:0]       m04_axi_wstrb        ,
  output wire                                    m04_axi_wlast        ,
  input  wire                                    m04_axi_bvalid       ,
  output wire                                    m04_axi_bready       ,
  output wire                                    m04_axi_arvalid      ,
  input  wire                                    m04_axi_arready      ,
  output wire [C_M04_AXI_ADDR_WIDTH-1:0]         m04_axi_araddr       ,
  output wire [8-1:0]                            m04_axi_arlen        ,
  input  wire                                    m04_axi_rvalid       ,
  output wire                                    m04_axi_rready       ,
  input  wire [C_M04_AXI_DATA_WIDTH-1:0]         m04_axi_rdata        ,
  input  wire                                    m04_axi_rlast        ,
  // AXI4 master interface m05_axi
  output wire                                    m05_axi_awvalid      ,
  input  wire                                    m05_axi_awready      ,
  output wire [C_M05_AXI_ADDR_WIDTH-1:0]         m05_axi_awaddr       ,
  output wire [8-1:0]                            m05_axi_awlen        ,
  output wire                                    m05_axi_wvalid       ,
  input  wire                                    m05_axi_wready       ,
  output wire [C_M05_AXI_DATA_WIDTH-1:0]         m05_axi_wdata        ,
  output wire [C_M05_AXI_DATA_WIDTH/8-1:0]       m05_axi_wstrb        ,
  output wire                                    m05_axi_wlast        ,
  input  wire                                    m05_axi_bvalid       ,
  output wire                                    m05_axi_bready       ,
  output wire                                    m05_axi_arvalid      ,
  input  wire                                    m05_axi_arready      ,
  output wire [C_M05_AXI_ADDR_WIDTH-1:0]         m05_axi_araddr       ,
  output wire [8-1:0]                            m05_axi_arlen        ,
  input  wire                                    m05_axi_rvalid       ,
  output wire                                    m05_axi_rready       ,
  input  wire [C_M05_AXI_DATA_WIDTH-1:0]         m05_axi_rdata        ,
  input  wire                                    m05_axi_rlast        ,
  // AXI4 master interface m06_axi
  output wire                                    m06_axi_awvalid      ,
  input  wire                                    m06_axi_awready      ,
  output wire [C_M06_AXI_ADDR_WIDTH-1:0]         m06_axi_awaddr       ,
  output wire [8-1:0]                            m06_axi_awlen        ,
  output wire                                    m06_axi_wvalid       ,
  input  wire                                    m06_axi_wready       ,
  output wire [C_M06_AXI_DATA_WIDTH-1:0]         m06_axi_wdata        ,
  output wire [C_M06_AXI_DATA_WIDTH/8-1:0]       m06_axi_wstrb        ,
  output wire                                    m06_axi_wlast        ,
  input  wire                                    m06_axi_bvalid       ,
  output wire                                    m06_axi_bready       ,
  output wire                                    m06_axi_arvalid      ,
  input  wire                                    m06_axi_arready      ,
  output wire [C_M06_AXI_ADDR_WIDTH-1:0]         m06_axi_araddr       ,
  output wire [8-1:0]                            m06_axi_arlen        ,
  input  wire                                    m06_axi_rvalid       ,
  output wire                                    m06_axi_rready       ,
  input  wire [C_M06_AXI_DATA_WIDTH-1:0]         m06_axi_rdata        ,
  input  wire                                    m06_axi_rlast        ,
  // AXI4 master interface m07_axi
  output wire                                    m07_axi_awvalid      ,
  input  wire                                    m07_axi_awready      ,
  output wire [C_M07_AXI_ADDR_WIDTH-1:0]         m07_axi_awaddr       ,
  output wire [8-1:0]                            m07_axi_awlen        ,
  output wire                                    m07_axi_wvalid       ,
  input  wire                                    m07_axi_wready       ,
  output wire [C_M07_AXI_DATA_WIDTH-1:0]         m07_axi_wdata        ,
  output wire [C_M07_AXI_DATA_WIDTH/8-1:0]       m07_axi_wstrb        ,
  output wire                                    m07_axi_wlast        ,
  input  wire                                    m07_axi_bvalid       ,
  output wire                                    m07_axi_bready       ,
  output wire                                    m07_axi_arvalid      ,
  input  wire                                    m07_axi_arready      ,
  output wire [C_M07_AXI_ADDR_WIDTH-1:0]         m07_axi_araddr       ,
  output wire [8-1:0]                            m07_axi_arlen        ,
  input  wire                                    m07_axi_rvalid       ,
  output wire                                    m07_axi_rready       ,
  input  wire [C_M07_AXI_DATA_WIDTH-1:0]         m07_axi_rdata        ,
  input  wire                                    m07_axi_rlast        ,
  // AXI4 master interface m08_axi
  output wire                                    m08_axi_awvalid      ,
  input  wire                                    m08_axi_awready      ,
  output wire [C_M08_AXI_ADDR_WIDTH-1:0]         m08_axi_awaddr       ,
  output wire [8-1:0]                            m08_axi_awlen        ,
  output wire                                    m08_axi_wvalid       ,
  input  wire                                    m08_axi_wready       ,
  output wire [C_M08_AXI_DATA_WIDTH-1:0]         m08_axi_wdata        ,
  output wire [C_M08_AXI_DATA_WIDTH/8-1:0]       m08_axi_wstrb        ,
  output wire                                    m08_axi_wlast        ,
  input  wire                                    m08_axi_bvalid       ,
  output wire                                    m08_axi_bready       ,
  output wire                                    m08_axi_arvalid      ,
  input  wire                                    m08_axi_arready      ,
  output wire [C_M08_AXI_ADDR_WIDTH-1:0]         m08_axi_araddr       ,
  output wire [8-1:0]                            m08_axi_arlen        ,
  input  wire                                    m08_axi_rvalid       ,
  output wire                                    m08_axi_rready       ,
  input  wire [C_M08_AXI_DATA_WIDTH-1:0]         m08_axi_rdata        ,
  input  wire                                    m08_axi_rlast        ,
  // AXI4-Lite slave interface
  input  wire                                    s_axi_control_awvalid,
  output wire                                    s_axi_control_awready,
  input  wire [C_S_AXI_CONTROL_ADDR_WIDTH-1:0]   s_axi_control_awaddr ,
  input  wire                                    s_axi_control_wvalid ,
  output wire                                    s_axi_control_wready ,
  input  wire [C_S_AXI_CONTROL_DATA_WIDTH-1:0]   s_axi_control_wdata  ,
  input  wire [C_S_AXI_CONTROL_DATA_WIDTH/8-1:0] s_axi_control_wstrb  ,
  input  wire                                    s_axi_control_arvalid,
  output wire                                    s_axi_control_arready,
  input  wire [C_S_AXI_CONTROL_ADDR_WIDTH-1:0]   s_axi_control_araddr ,
  output wire                                    s_axi_control_rvalid ,
  input  wire                                    s_axi_control_rready ,
  output wire [C_S_AXI_CONTROL_DATA_WIDTH-1:0]   s_axi_control_rdata  ,
  output wire [2-1:0]                            s_axi_control_rresp  ,
  output wire                                    s_axi_control_bvalid ,
  input  wire                                    s_axi_control_bready ,
  output wire [2-1:0]                            s_axi_control_bresp  ,
  output wire                                    interrupt            
);

///////////////////////////////////////////////////////////////////////////////
// Local Parameters
///////////////////////////////////////////////////////////////////////////////

///////////////////////////////////////////////////////////////////////////////
// Wires and Variables
///////////////////////////////////////////////////////////////////////////////
(* DONT_TOUCH = "yes" *)
reg                                 areset                         = 1'b0;
reg                                 areset_2                       = 1'b0;
wire                                ap_start                      ;
wire                                ap_idle                       ;
wire                                ap_done                       ;
wire                                ap_ready                      ;
wire [64-1:0]                       param0                        ;
wire [64-1:0]                       param1                        ;
wire [64-1:0]                       param2                        ;
wire [64-1:0]                       axi00_read                    ;
wire [64-1:0]                       axi01_read                    ;
wire [64-1:0]                       axi02_read                    ;
wire [64-1:0]                       axi03_read                    ;
wire [64-1:0]                       axi04_read                    ;
wire [64-1:0]                       axi05_write                   ;
wire [64-1:0]                       axi06_write                   ;
wire [64-1:0]                       axi07_write                   ;
wire [64-1:0]                       axi08_debug_write             ;

// Register and invert reset signal.
always @(posedge ap_clk) begin
  areset <= ~ap_rst_n;
end

// Register and invert reset signal.
/*
always @(posedge ap_clk_2) begin
  areset_2 <= ~ap_rst_n_2;
end
*/

// FIXME: when RTL is generated WITH second clock, remove this:
reg ap_clk_2 = 1'b0;

///////////////////////////////////////////////////////////////////////////////
// Begin control interface RTL.  Modifying not recommended.
///////////////////////////////////////////////////////////////////////////////


// AXI4-Lite slave interface
bicgstab_2r_3r3w_rtl_v1_control_s_axi #(
  .C_S_AXI_ADDR_WIDTH ( C_S_AXI_CONTROL_ADDR_WIDTH ),
  .C_S_AXI_DATA_WIDTH ( C_S_AXI_CONTROL_DATA_WIDTH )
)
inst_control_s_axi (
  .ACLK              ( ap_clk                ),
  .ARESET            ( areset                ),
  .ACLK_EN           ( 1'b1                  ),
  .AWVALID           ( s_axi_control_awvalid ),
  .AWREADY           ( s_axi_control_awready ),
  .AWADDR            ( s_axi_control_awaddr  ),
  .WVALID            ( s_axi_control_wvalid  ),
  .WREADY            ( s_axi_control_wready  ),
  .WDATA             ( s_axi_control_wdata   ),
  .WSTRB             ( s_axi_control_wstrb   ),
  .ARVALID           ( s_axi_control_arvalid ),
  .ARREADY           ( s_axi_control_arready ),
  .ARADDR            ( s_axi_control_araddr  ),
  .RVALID            ( s_axi_control_rvalid  ),
  .RREADY            ( s_axi_control_rready  ),
  .RDATA             ( s_axi_control_rdata   ),
  .RRESP             ( s_axi_control_rresp   ),
  .BVALID            ( s_axi_control_bvalid  ),
  .BREADY            ( s_axi_control_bready  ),
  .BRESP             ( s_axi_control_bresp   ),
  .interrupt         ( interrupt             ),
  .ap_start          ( ap_start              ),
  .ap_done           ( ap_done               ),
  .ap_ready          ( ap_ready              ),
  .ap_idle           ( ap_idle               ),
  .param0            ( param0                ),
  .param1            ( param1                ),
  .param2            ( param2                ),
  .axi00_read        ( axi00_read            ),
  .axi01_read        ( axi01_read            ),
  .axi02_read        ( axi02_read            ),
  .axi03_read        ( axi03_read            ),
  .axi04_read        ( axi04_read            ),
  .axi05_write       ( axi05_write           ),
  .axi06_write       ( axi06_write           ),
  .axi07_write       ( axi07_write           ),
  .axi08_debug_write ( axi08_debug_write     )
);

///////////////////////////////////////////////////////////////////////////////
// Add kernel logic here.  Modify/remove example code as necessary.
///////////////////////////////////////////////////////////////////////////////

bicgstab_solver_wrapper_2r_3r3w_v1
inst_bicgstab_solver_wrapper_2r_3r3w_v1 (
  .ap_clk_2              ( ap_clk_2          ),
  .ap_rst_2              ( areset_2          ),
  .ap_clk                ( ap_clk            ),
  .ap_rst                ( areset            ),
  .ap_start              ( ap_start          ),
  .ap_done               ( ap_done           ),
  .ap_idle               ( ap_idle           ),
  .ap_ready              ( ap_ready          ),
  .param0                ( param0            ),
  .param1                ( param1            ),
  .param2                ( param2            ),
  .m_axi_gmem0_offset    ( axi00_read        ),
  .m_axi_gmem1_offset    ( axi01_read        ),
  .m_axi_gmem2_offset    ( axi02_read        ),
  .m_axi_gmem3_offset    ( axi03_read        ),
  .m_axi_gmem4_offset    ( axi04_read        ),
  .m_axi_gmem5_offset    ( axi05_write       ),
  .m_axi_gmem6_offset    ( axi06_write       ),
  .m_axi_gmem7_offset    ( axi07_write       ),
  .m_axi_gmem8_offset    ( axi08_debug_write ),
  .m_axi_gmem0_awvalid   ( m00_axi_awvalid   ),
  .m_axi_gmem0_awready   ( m00_axi_awready   ),
  .m_axi_gmem0_awaddr    ( m00_axi_awaddr    ),
  .m_axi_gmem0_awlen     ( m00_axi_awlen     ),
  .m_axi_gmem0_wvalid    ( m00_axi_wvalid    ),
  .m_axi_gmem0_wready    ( m00_axi_wready    ),
  .m_axi_gmem0_wdata     ( m00_axi_wdata     ),
  .m_axi_gmem0_wstrb     ( m00_axi_wstrb     ),
  .m_axi_gmem0_wlast     ( m00_axi_wlast     ),
  .m_axi_gmem0_bvalid    ( m00_axi_bvalid    ),
  .m_axi_gmem0_bready    ( m00_axi_bready    ),
  .m_axi_gmem0_arvalid   ( m00_axi_arvalid   ),
  .m_axi_gmem0_arready   ( m00_axi_arready   ),
  .m_axi_gmem0_araddr    ( m00_axi_araddr    ),
  .m_axi_gmem0_arlen     ( m00_axi_arlen     ),
  .m_axi_gmem0_rvalid    ( m00_axi_rvalid    ),
  .m_axi_gmem0_rready    ( m00_axi_rready    ),
  .m_axi_gmem0_rdata     ( m00_axi_rdata     ),
  .m_axi_gmem0_rlast     ( m00_axi_rlast     ),
  .m_axi_gmem1_awvalid   ( m01_axi_awvalid   ),
  .m_axi_gmem1_awready   ( m01_axi_awready   ),
  .m_axi_gmem1_awaddr    ( m01_axi_awaddr    ),
  .m_axi_gmem1_awlen     ( m01_axi_awlen     ),
  .m_axi_gmem1_wvalid    ( m01_axi_wvalid    ),
  .m_axi_gmem1_wready    ( m01_axi_wready    ),
  .m_axi_gmem1_wdata     ( m01_axi_wdata     ),
  .m_axi_gmem1_wstrb     ( m01_axi_wstrb     ),
  .m_axi_gmem1_wlast     ( m01_axi_wlast     ),
  .m_axi_gmem1_bvalid    ( m01_axi_bvalid    ),
  .m_axi_gmem1_bready    ( m01_axi_bready    ),
  .m_axi_gmem1_arvalid   ( m01_axi_arvalid   ),
  .m_axi_gmem1_arready   ( m01_axi_arready   ),
  .m_axi_gmem1_araddr    ( m01_axi_araddr    ),
  .m_axi_gmem1_arlen     ( m01_axi_arlen     ),
  .m_axi_gmem1_rvalid    ( m01_axi_rvalid    ),
  .m_axi_gmem1_rready    ( m01_axi_rready    ),
  .m_axi_gmem1_rdata     ( m01_axi_rdata     ),
  .m_axi_gmem1_rlast     ( m01_axi_rlast     ),
  .m_axi_gmem2_awvalid   ( m02_axi_awvalid   ),
  .m_axi_gmem2_awready   ( m02_axi_awready   ),
  .m_axi_gmem2_awaddr    ( m02_axi_awaddr    ),
  .m_axi_gmem2_awlen     ( m02_axi_awlen     ),
  .m_axi_gmem2_wvalid    ( m02_axi_wvalid    ),
  .m_axi_gmem2_wready    ( m02_axi_wready    ),
  .m_axi_gmem2_wdata     ( m02_axi_wdata     ),
  .m_axi_gmem2_wstrb     ( m02_axi_wstrb     ),
  .m_axi_gmem2_wlast     ( m02_axi_wlast     ),
  .m_axi_gmem2_bvalid    ( m02_axi_bvalid    ),
  .m_axi_gmem2_bready    ( m02_axi_bready    ),
  .m_axi_gmem2_arvalid   ( m02_axi_arvalid   ),
  .m_axi_gmem2_arready   ( m02_axi_arready   ),
  .m_axi_gmem2_araddr    ( m02_axi_araddr    ),
  .m_axi_gmem2_arlen     ( m02_axi_arlen     ),
  .m_axi_gmem2_rvalid    ( m02_axi_rvalid    ),
  .m_axi_gmem2_rready    ( m02_axi_rready    ),
  .m_axi_gmem2_rdata     ( m02_axi_rdata     ),
  .m_axi_gmem2_rlast     ( m02_axi_rlast     ),
  .m_axi_gmem3_awvalid   ( m03_axi_awvalid   ),
  .m_axi_gmem3_awready   ( m03_axi_awready   ),
  .m_axi_gmem3_awaddr    ( m03_axi_awaddr    ),
  .m_axi_gmem3_awlen     ( m03_axi_awlen     ),
  .m_axi_gmem3_wvalid    ( m03_axi_wvalid    ),
  .m_axi_gmem3_wready    ( m03_axi_wready    ),
  .m_axi_gmem3_wdata     ( m03_axi_wdata     ),
  .m_axi_gmem3_wstrb     ( m03_axi_wstrb     ),
  .m_axi_gmem3_wlast     ( m03_axi_wlast     ),
  .m_axi_gmem3_bvalid    ( m03_axi_bvalid    ),
  .m_axi_gmem3_bready    ( m03_axi_bready    ),
  .m_axi_gmem3_arvalid   ( m03_axi_arvalid   ),
  .m_axi_gmem3_arready   ( m03_axi_arready   ),
  .m_axi_gmem3_araddr    ( m03_axi_araddr    ),
  .m_axi_gmem3_arlen     ( m03_axi_arlen     ),
  .m_axi_gmem3_rvalid    ( m03_axi_rvalid    ),
  .m_axi_gmem3_rready    ( m03_axi_rready    ),
  .m_axi_gmem3_rdata     ( m03_axi_rdata     ),
  .m_axi_gmem3_rlast     ( m03_axi_rlast     ),
  .m_axi_gmem4_awvalid   ( m04_axi_awvalid   ),
  .m_axi_gmem4_awready   ( m04_axi_awready   ),
  .m_axi_gmem4_awaddr    ( m04_axi_awaddr    ),
  .m_axi_gmem4_awlen     ( m04_axi_awlen     ),
  .m_axi_gmem4_wvalid    ( m04_axi_wvalid    ),
  .m_axi_gmem4_wready    ( m04_axi_wready    ),
  .m_axi_gmem4_wdata     ( m04_axi_wdata     ),
  .m_axi_gmem4_wstrb     ( m04_axi_wstrb     ),
  .m_axi_gmem4_wlast     ( m04_axi_wlast     ),
  .m_axi_gmem4_bvalid    ( m04_axi_bvalid    ),
  .m_axi_gmem4_bready    ( m04_axi_bready    ),
  .m_axi_gmem4_arvalid   ( m04_axi_arvalid   ),
  .m_axi_gmem4_arready   ( m04_axi_arready   ),
  .m_axi_gmem4_araddr    ( m04_axi_araddr    ),
  .m_axi_gmem4_arlen     ( m04_axi_arlen     ),
  .m_axi_gmem4_rvalid    ( m04_axi_rvalid    ),
  .m_axi_gmem4_rready    ( m04_axi_rready    ),
  .m_axi_gmem4_rdata     ( m04_axi_rdata     ),
  .m_axi_gmem4_rlast     ( m04_axi_rlast     ),
  .m_axi_gmem5_awvalid   ( m05_axi_awvalid   ),
  .m_axi_gmem5_awready   ( m05_axi_awready   ),
  .m_axi_gmem5_awaddr    ( m05_axi_awaddr    ),
  .m_axi_gmem5_awlen     ( m05_axi_awlen     ),
  .m_axi_gmem5_wvalid    ( m05_axi_wvalid    ),
  .m_axi_gmem5_wready    ( m05_axi_wready    ),
  .m_axi_gmem5_wdata     ( m05_axi_wdata     ),
  .m_axi_gmem5_wstrb     ( m05_axi_wstrb     ),
  .m_axi_gmem5_wlast     ( m05_axi_wlast     ),
  .m_axi_gmem5_bvalid    ( m05_axi_bvalid    ),
  .m_axi_gmem5_bready    ( m05_axi_bready    ),
  .m_axi_gmem5_arvalid   ( m05_axi_arvalid   ),
  .m_axi_gmem5_arready   ( m05_axi_arready   ),
  .m_axi_gmem5_araddr    ( m05_axi_araddr    ),
  .m_axi_gmem5_arlen     ( m05_axi_arlen     ),
  .m_axi_gmem5_rvalid    ( m05_axi_rvalid    ),
  .m_axi_gmem5_rready    ( m05_axi_rready    ),
  .m_axi_gmem5_rdata     ( m05_axi_rdata     ),
  .m_axi_gmem5_rlast     ( m05_axi_rlast     ),
  .m_axi_gmem6_awvalid   ( m06_axi_awvalid   ),
  .m_axi_gmem6_awready   ( m06_axi_awready   ),
  .m_axi_gmem6_awaddr    ( m06_axi_awaddr    ),
  .m_axi_gmem6_awlen     ( m06_axi_awlen     ),
  .m_axi_gmem6_wvalid    ( m06_axi_wvalid    ),
  .m_axi_gmem6_wready    ( m06_axi_wready    ),
  .m_axi_gmem6_wdata     ( m06_axi_wdata     ),
  .m_axi_gmem6_wstrb     ( m06_axi_wstrb     ),
  .m_axi_gmem6_wlast     ( m06_axi_wlast     ),
  .m_axi_gmem6_bvalid    ( m06_axi_bvalid    ),
  .m_axi_gmem6_bready    ( m06_axi_bready    ),
  .m_axi_gmem6_arvalid   ( m06_axi_arvalid   ),
  .m_axi_gmem6_arready   ( m06_axi_arready   ),
  .m_axi_gmem6_araddr    ( m06_axi_araddr    ),
  .m_axi_gmem6_arlen     ( m06_axi_arlen     ),
  .m_axi_gmem6_rvalid    ( m06_axi_rvalid    ),
  .m_axi_gmem6_rready    ( m06_axi_rready    ),
  .m_axi_gmem6_rdata     ( m06_axi_rdata     ),
  .m_axi_gmem6_rlast     ( m06_axi_rlast     ),
  .m_axi_gmem7_awvalid   ( m07_axi_awvalid   ),
  .m_axi_gmem7_awready   ( m07_axi_awready   ),
  .m_axi_gmem7_awaddr    ( m07_axi_awaddr    ),
  .m_axi_gmem7_awlen     ( m07_axi_awlen     ),
  .m_axi_gmem7_wvalid    ( m07_axi_wvalid    ),
  .m_axi_gmem7_wready    ( m07_axi_wready    ),
  .m_axi_gmem7_wdata     ( m07_axi_wdata     ),
  .m_axi_gmem7_wstrb     ( m07_axi_wstrb     ),
  .m_axi_gmem7_wlast     ( m07_axi_wlast     ),
  .m_axi_gmem7_bvalid    ( m07_axi_bvalid    ),
  .m_axi_gmem7_bready    ( m07_axi_bready    ),
  .m_axi_gmem7_arvalid   ( m07_axi_arvalid   ),
  .m_axi_gmem7_arready   ( m07_axi_arready   ),
  .m_axi_gmem7_araddr    ( m07_axi_araddr    ),
  .m_axi_gmem7_arlen     ( m07_axi_arlen     ),
  .m_axi_gmem7_rvalid    ( m07_axi_rvalid    ),
  .m_axi_gmem7_rready    ( m07_axi_rready    ),
  .m_axi_gmem7_rdata     ( m07_axi_rdata     ),
  .m_axi_gmem7_rlast     ( m07_axi_rlast     ),
  .m_axi_gmem8_awvalid   ( m08_axi_awvalid   ),
  .m_axi_gmem8_awready   ( m08_axi_awready   ),
  .m_axi_gmem8_awaddr    ( m08_axi_awaddr    ),
  .m_axi_gmem8_awlen     ( m08_axi_awlen     ),
  .m_axi_gmem8_wvalid    ( m08_axi_wvalid    ),
  .m_axi_gmem8_wready    ( m08_axi_wready    ),
  .m_axi_gmem8_wdata     ( m08_axi_wdata     ),
  .m_axi_gmem8_wstrb     ( m08_axi_wstrb     ),
  .m_axi_gmem8_wlast     ( m08_axi_wlast     ),
  .m_axi_gmem8_bvalid    ( m08_axi_bvalid    ),
  .m_axi_gmem8_bready    ( m08_axi_bready    ),
  .m_axi_gmem8_arvalid   ( m08_axi_arvalid   ),
  .m_axi_gmem8_arready   ( m08_axi_arready   ),
  .m_axi_gmem8_araddr    ( m08_axi_araddr    ),
  .m_axi_gmem8_arlen     ( m08_axi_arlen     ),
  .m_axi_gmem8_rvalid    ( m08_axi_rvalid    ),
  .m_axi_gmem8_rready    ( m08_axi_rready    ),
  .m_axi_gmem8_rdata     ( m08_axi_rdata     ),
  .m_axi_gmem8_rlast     ( m08_axi_rlast     )
);

endmodule
`default_nettype wire
