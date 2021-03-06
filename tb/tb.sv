`include "config.sv"
`include "tb_jtag_pkg.sv"

`define REF_CLK_PERIOD   (2*15.25us)  // 32.786 kHz --> FLL reset value --> 50 MHz
`define CLK_PERIOD       20.00ns      // 25 MHz

module tb;
  timeunit      1ns;
  timeprecision 1ps;

  // +MEMLOAD= valid values are "SPI", "STANDALONE" "PRELOAD", "" (no load of L2)
  parameter  SPI           = "QUAD";    // valid values are "SINGLE", "QUAD"
  parameter  ENABLE_VPI    = 0;
  parameter  BAUDRATE      = 781250; // 1562500
  parameter  CLK_USE_FLL   = 0;  // 0 or 1

  string        memload;
  logic         s_clk   = 1'b0;
  logic         s_rst_n = 1'b0;

  logic         fetch_enable = 1'b0;

  logic [1:0]   padmode_spi_master;
  logic         spi_sck   = 1'b0;
  logic         spi_csn   = 1'b1;
  logic [1:0]   spi_mode;
  logic         spi_sdo0;
  logic         spi_sdo1;
  logic         spi_sdo2;
  logic         spi_sdo3;
  logic         spi_sdi0;
  logic         spi_sdi1;
  logic         spi_sdi2;
  logic         spi_sdi3;

  logic         uart_tx;
  logic         uart_rx;
  logic         s_uart_dtr;
  logic         s_uart_rts;

  logic [31:0]  gpio_out;

  logic [31:0]  recv_data;

  jtag_i jtag_if();

  adv_dbg_if_t adv_dbg_if = new(jtag_if);

  generate if(ENABLE_VPI == 1)
  begin
    // jtag dpi module
    jtag_dpi
    #(
      .TIMEOUT_COUNT ( 6'd10 )
    )
    i_jtag
    (
      .clk_i    ( s_clk   ),
      .enable_i ( s_rst_n ),

      .tms_o    ( jtag_if.tms     ),
      .tck_o    ( jtag_if.tck     ),
      .trst_o   ( jtag_if.trstn   ),
      .tdi_o    ( jtag_if.tdi     ),
      .tdo_i    ( jtag_if.tdo     )
     );
  end
  endgenerate

  // use 8N1
  uart_tb_rx
  #(
    .BAUD_RATE(BAUDRATE),
    .PARITY_EN(0)
  )
  uart_tb_rx_i
  (
    .rx(uart_rx),
    .rx_en(1'b1),
    .word_done()
  );


  pulpino_top top_i
  (
    .clk               ( s_clk        ),
    .rst_n             ( s_rst_n      ),

    .clk_sel_i         ( 1'b0         ),
    .testmode_i        ( 1'b0         ),
    .fetch_enable_i    ( fetch_enable ),

    .spi_clk_i         ( spi_sck      ),
    .spi_cs_i          ( spi_csn      ),
    .spi_mode_o        ( spi_mode     ),
    .spi_sdo0_o        ( spi_sdi0     ),
    .spi_sdo1_o        ( spi_sdi1     ),
    .spi_sdo2_o        ( spi_sdi2     ),
    .spi_sdo3_o        ( spi_sdi3     ),
    .spi_sdi0_i        ( spi_sdo0     ),
    .spi_sdi1_i        ( spi_sdo1     ),
    .spi_sdi2_i        ( spi_sdo2     ),
    .spi_sdi3_i        ( spi_sdo3     ),

    .spi_master_clk_o  (              ),
    .spi_master_csn0_o (              ),
    .spi_master_csn1_o (              ),
    .spi_master_csn2_o (              ),
    .spi_master_csn3_o (              ),
    .spi_master_mode_o (              ),
    .spi_master_sdo0_o (              ),
    .spi_master_sdo1_o (              ),
    .spi_master_sdo2_o (              ),
    .spi_master_sdo3_o (              ),
    .spi_master_sdi0_i (              ),
    .spi_master_sdi1_i (              ),
    .spi_master_sdi2_i (              ),
    .spi_master_sdi3_i (              ),

    .scl_pad_i         (              ),
    .scl_pad_o         (              ),
    .scl_padoen_o      (              ),
    .sda_pad_i         (              ),
    .sda_pad_o         (              ),
    .sda_padoen_o      (              ),


    .uart_tx           ( uart_rx      ),
    .uart_rx           ( uart_rx      ),
    .uart_rts          ( s_uart_rts   ),
    .uart_dtr          ( s_uart_dtr   ),
    .uart_cts          ( 1'b0         ),
    .uart_dsr          ( 1'b0         ),

    .gpio_in           (              ),
    .gpio_out          ( gpio_out     ),
    .gpio_dir          (              ),
    .gpio_padcfg       (              ),

    .tck_i             ( jtag_if.tck     ),
    .trstn_i           ( jtag_if.trstn   ),
    .tms_i             ( jtag_if.tms     ),
    .tdi_i             ( jtag_if.tdi     ),
    .tdo_o             ( jtag_if.tdo     )
  );

  generate
    if (CLK_USE_FLL) begin
      initial
      begin
        #(`REF_CLK_PERIOD/2);
        s_clk = 1'b1;
        forever s_clk = #(`REF_CLK_PERIOD/2) ~s_clk;
      end
    end else begin
      initial
      begin
        #(`CLK_PERIOD);
        s_clk = 1'b1;
        forever s_clk = #(`CLK_PERIOD) ~s_clk;
      end
    end
  endgenerate

  logic use_qspi;

  initial
  begin

    if(!$value$plusargs("MEMLOAD=%s", memload))
      memload = "PRELOAD";

    $display("Using MEMLOAD method: %s", memload);

    use_qspi = SPI == "QUAD" ? 1'b1 : 1'b0;

    s_rst_n      = 1'b0;
    fetch_enable = 1'b0;

    #500ns;

    s_rst_n = 1'b1;

    #500ns;

    if (memload != "STANDALONE")
    begin
      /* Configure JTAG and set boot address */
      adv_dbg_if.jtag_reset();
      adv_dbg_if.jtag_softreset();
      adv_dbg_if.init();
      adv_dbg_if.axi4_write32(32'h1A10_7008, 1, 32'h0000_0000);
    end

    if (memload == "PRELOAD")
    begin
      // preload memories
      mem_preload();
    end
    else if (memload == "SPI")
    begin
      if (use_qspi)
        spi_enable_qpi();

      spi_load(use_qspi);
      spi_check(use_qspi);
    end

    #200000
    fetch_enable = 1'b1;

    // end of computation
    wait(top_i.gpio_out[8]);
    $fflush();
    $stop();

    spi_read_word(use_qspi, 8'hB, 32'h0000_0000, recv_data);
    $display("[SPI] Received %X", recv_data);
    $stop();
  end

  // TODO: this is a hack, do it properly!
  `include "tb_spi_pkg.sv"
  `include "tb_mem_pkg.sv"

endmodule
