//============================================================================
//  SNES top-level for MiST
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//
//  This program is distributed in the hope that it will be useful, but WITHOUT
//  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
//  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
//  more details.
//
//  You should have received a copy of the GNU General Public License along
//  with this program; if not, write to the Free Software Foundation, Inc.,
//  51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
//============================================================================

module SNES_MIST_TOP
(
   input         CLOCK_27[0],   // Input clock 27 MHz

   output  [5:0] VGA_R,
   output  [5:0] VGA_G,
   output  [5:0] VGA_B,
   output        VGA_HS,
   output        VGA_VS,

   output        LED,

   output        AUDIO_L,
   output        AUDIO_R,

   input         UART_RX,

   input         SPI_SCK,
   output        SPI_DO,
   input         SPI_DI,
   input         SPI_SS2,
   input         SPI_SS3,
   input         CONF_DATA0,

   output [12:0] SDRAM_A,
   inout  [15:0] SDRAM_DQ,
   output        SDRAM_DQML,
   output        SDRAM_DQMH,
   output        SDRAM_nWE,
   output        SDRAM_nCAS,
   output        SDRAM_nRAS,
   output        SDRAM_nCS,
   output  [1:0] SDRAM_BA,
   output        SDRAM_CLK,
   output        SDRAM_CKE
);

assign LED  = ~ioctl_download;

`include "build_id.v"
parameter CONF_STR = {
	"SNES;;",
	"F,SFCBIN,Load;",
	"OE,Video Region,NTSC,PAL;",
	"OAB,Scandoubler Fx,None,CRT 25%,CRT 50%,CRT 75%;",
	"OG,Blend,On,Off;",
	"O12,ROM Type,LoROM,HiROM,ExHiROM;",
	"O56,Mouse,None,Port1,Port2;",
	"O7,Swap Joysticks,No,Yes;",
	"OH,Multitap,Disabled,Port2;",
	"T0,Reset;",
	"V,v1.0.",`BUILD_DATE
};

wire [1:0] LHRom_type = status[2:1];
wire [1:0] scanlines = status[11:10];
wire       video_region = status[14];
wire [1:0] mouse_mode = status[6:5];
wire       joy_swap = status[7];
wire       multitap = status[17];
wire       BLEND = ~status[16];

////////////////////   CLOCKS   ///////////////////

wire locked;
wire clk_sys, clk_mem;

pll pll
(
	.inclk0(CLOCK_27[0]),
	.c0(SDRAM_CLK),
	.c1(clk_mem),
	.c2(clk_sys),
	.locked(locked)
);

reg reset;
always @(posedge clk_sys) begin
	reset <= buttons[1] | status[0] | ioctl_download;
end

//////////////////   MiST I/O   ///////////////////
wire [31:0] joystick0;
wire [31:0] joystick1;
wire [31:0] joystick2;
wire [31:0] joystick3;
wire [31:0] joystick4;

wire  [1:0] buttons;
wire [31:0] status;
wire        ypbpr;
wire        scandoubler_disable;

reg         ioctl_wrD;
wire        ioctl_wr;
wire [24:0] ioctl_addr;
wire [15:0] ioctl_dout;
wire        ioctl_download;
wire  [7:0] ioctl_index;
wire        ioctl_wait;

wire  [8:0] mouse_x;
wire  [8:0] mouse_y;
wire  [7:0] mouse_flags;  // YOvfl, XOvfl, dy8, dx8, 1, mbtn, rbtn, lbtn
wire        mouse_strobe;

reg  [31:0] sd_lba;
reg         sd_rd = 0;
reg         sd_wr = 0;
wire        sd_ack;
wire  [8:0] sd_buff_addr;
wire  [7:0] sd_buff_dout;
wire  [7:0] sd_buff_din;
wire        sd_buff_wr;
wire        img_mounted;
wire [31:0] img_size;

user_io #(.STRLEN($size(CONF_STR)>>3)) user_io
(
	.clk_sys(clk_sys),
	.clk_sd(clk_sys),
	.SPI_SS_IO(CONF_DATA0),
	.SPI_CLK(SPI_SCK),
	.SPI_MOSI(SPI_DI),
	.SPI_MISO(SPI_DO),

	.conf_str(CONF_STR),

	.status(status),
	.scandoubler_disable(scandoubler_disable),
//	.ypbpr(ypbpr),
	.buttons(buttons),
	.joystick_0(joystick0),
	.joystick_1(joystick1),
	.joystick_2(joystick2),
	.joystick_3(joystick3),
	.joystick_4(joystick4),

	.mouse_x(mouse_x),
	.mouse_y(mouse_y),
	.mouse_flags(mouse_flags),
	.mouse_strobe(mouse_strobe),

	.sd_conf(0),
	.sd_sdhc(1),
	.sd_lba(sd_lba),
	.sd_rd(sd_rd),
	.sd_wr(sd_wr),
	.sd_ack(sd_ack),
	.sd_buff_addr(sd_buff_addr),
	.sd_dout(sd_buff_dout),
	.sd_din(sd_buff_din),
	.sd_dout_strobe(sd_buff_wr),
	.img_mounted(img_mounted),
	.img_size(img_size)
);

reg [24:0] ps2_mouse;
always @(posedge clk_sys) begin
	if (mouse_strobe) begin
		ps2_mouse[24] <= ~ps2_mouse[24];
		ps2_mouse[23:0] <= { mouse_y[7:0], mouse_x[7:0], mouse_flags };
	end
end

data_io data_io
(
	.clk_sys(clk_sys),
	.SPI_SCK(SPI_SCK),
	.SPI_DI(SPI_DI),
	.SPI_SS2(SPI_SS2),

	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_dout),
	.ioctl_download(ioctl_download),
	.ioctl_index(ioctl_index)
);

always @(posedge clk_sys) ioctl_wrD <= ioctl_wr;

////////////////////////////  SDRAM  ///////////////////////////////////

wire [23:0] ROM_ADDR;
wire [23:1] rom_addr_sd = cart_download ? ioctl_addr[23:1] : ROM_ADDR[23:1];
reg  [23:1] rom_addr_sd_last;
wire        ROM_CE_N;
wire        ROM_OE_N;
wire        ROM_WORD;
wire [15:0] ROM_Q = (ROM_WORD || ~ROM_ADDR[0]) ? rom_dout : { rom_dout[7:0], rom_dout[15:8] };
wire [15:0] rom_dout;
wire        rom_req;
reg         rom_req_reg;

wire [16:0] WRAM_ADDR;
wire [16:0] wram_addr_last;
wire        WRAM_CE_N;
wire        WRAM_OE_N;
wire        WRAM_RD_N;
wire        WRAM_WE_N;
wire  [7:0] WRAM_Q, WRAM_D;
wire        wram_rd = ~WRAM_CE_N & ~WRAM_RD_N;
reg         wram_rdD;
wire        wram_wr = ~WRAM_CE_N & ~WRAM_WE_N;
reg         wram_wrD;
wire        wram_req;
reg         wram_req_reg;

wire [19:0] BSRAM_ADDR;
wire        BSRAM_CE_N;
wire        BSRAM_OE_N;
wire        BSRAM_WE_N;
wire  [7:0] BSRAM_Q, BSRAM_D;
wire        bsram_rd = ~BSRAM_CE_N & ~BSRAM_OE_N;
reg         bsram_rdD;
wire        bsram_wr = ~BSRAM_CE_N & ~BSRAM_WE_N;
reg         bsram_wrD;
wire        bsram_req;
reg         bsram_req_reg;

wire        VRAM_OE_N;

wire [15:0] VRAM1_ADDR;
reg  [14:0] vram1_addr_last;
wire        VRAM1_WE_N;
wire  [7:0] VRAM1_D, VRAM1_Q;
wire        vram1_req;
reg         vram1_req_reg;
reg         vram1_we_nD;

wire [15:0] VRAM2_ADDR;
reg  [14:0] vram2_addr_last;
wire        VRAM2_WE_N;
wire  [7:0] VRAM2_D, VRAM2_Q;
wire        vram2_req;
reg         vram2_req_reg;
reg         vram2_we_nD;

wire [15:0] ARAM_ADDR;
reg  [15:0] aram_addr_last;
wire        ARAM_CE_N;
wire        ARAM_OE_N;
wire        ARAM_WE_N;
wire  [7:0] ARAM_Q, ARAM_D;
wire        aram_rd = ~ARAM_CE_N & ~ARAM_OE_N;
reg         aram_rd_last;
wire        aram_wr = ~ARAM_CE_N & ~ARAM_WE_N;
reg         aram_wr_last;
wire        aram_req;
wire        aram_req_reg;

reg  [14:0] vram_rst_addr;
reg         vram_rst_req;
reg   [2:0] vram_rst_cnt;

always @(posedge clk_sys) begin
	if (reset) begin
		vram_rst_cnt <= vram_rst_cnt + 1'd1;
		if (vram_rst_cnt == 0) begin
			vram_rst_addr <= vram_rst_addr + 1'd1;
			vram_rst_req <= ~vram_rst_req;
		end
	end
end

always @(posedge clk_sys) begin

	rom_req_reg <= rom_req;

	if (reset) begin
		rom_addr_sd_last <= 0;
		vram1_addr_last <= 15'h7fff;
		vram2_addr_last <= 15'h7fff;
		aram_addr_last <= 16'haaaa;
		wram_addr_last <= 17'h1aaaa;
	end else begin
		rom_addr_sd_last <= rom_addr_sd;

		wram_req_reg <= wram_req;
		wram_rdD <= wram_rd;
		wram_wrD <= wram_wr;
		wram_addr_last <= WRAM_ADDR;

		bsram_req_reg <= bsram_req;
		bsram_rdD <= bsram_rd;
		bsram_wrD <= bsram_wr;

		aram_req_reg <= aram_req;
		if (aram_req ^ aram_req_reg) begin
			aram_addr_last <= ARAM_ADDR;
			aram_wr_last <= aram_wr;
			aram_rd_last <= aram_rd;
		end

		vram1_req_reg <= vram1_req;
		vram1_we_nD <= VRAM1_WE_N;
		vram1_addr_last <= VRAM1_ADDR[14:0];

		vram2_req_reg <= vram2_req;
		vram2_we_nD <= VRAM2_WE_N;
		vram2_addr_last <= VRAM2_ADDR[14:0];
	end
end

always @(*) begin
	rom_req = rom_req_reg;
	if ((~cart_download && ~ROM_CE_N && ~ROM_OE_N && rom_addr_sd != rom_addr_sd_last) || ((ioctl_wrD ^ ioctl_wr) & cart_download))
		rom_req = ~rom_req;

	wram_req = wram_req_reg;
	if ((wram_rd && WRAM_ADDR != wram_addr_last) || (~wram_wrD & wram_wr) || (~wram_rdD & wram_rd)) wram_req = ~wram_req;

	bsram_req = bsram_req_reg;
	if ((~bsram_wrD & bsram_wr) || (~bsram_rdD & bsram_rd)) bsram_req = ~bsram_req;

	aram_req = aram_req_reg;
	if (((aram_rd || aram_wr) && (ARAM_ADDR != aram_addr_last)) || (aram_rd & ~aram_rd_last) || (aram_wr & ~aram_wr_last)) aram_req = ~aram_req;

	vram1_req = vram1_req_reg;
	if ((vram1_we_nD & ~VRAM1_WE_N) || (VRAM1_ADDR[14:0] != vram1_addr_last && ~VRAM_OE_N))
		vram1_req = ~vram1_req;

	vram2_req = vram2_req_reg;
	if ((vram2_we_nD & ~VRAM2_WE_N) || (VRAM2_ADDR[14:0] != vram2_addr_last && ~VRAM_OE_N))
		vram2_req = ~vram2_req;
end

sdram sdram
(
	.*,
	.init_n(locked),
	.clk(clk_mem),

	.rom_addr(rom_addr_sd),
	.rom_din(ioctl_dout),
	.rom_dout(rom_dout),
	.rom_req(rom_req),
	.rom_req_ack(),
	.rom_we(cart_download),

	.wram_addr(WRAM_ADDR),
	.wram_din(WRAM_D),
	.wram_dout(WRAM_Q),
	.wram_req(wram_req),
	.wram_req_ack(),
	.wram_we(~WRAM_WE_N),

	.bsram_addr(BSRAM_ADDR),
	.bsram_din(BSRAM_D),
	.bsram_dout(BSRAM_Q),
	.bsram_req(bsram_req),
	.bsram_req_ack(),
	.bsram_we(~BSRAM_WE_N),

	.vram1_req(reset ? vram_rst_req : vram1_req),
	.vram1_ack(),
	.vram1_addr(reset ? vram_rst_addr : VRAM1_ADDR[14:0]),
	.vram1_din(reset ? 8'd0 : VRAM1_D),
	.vram1_dout(VRAM1_Q),
	.vram1_we(reset | ~VRAM1_WE_N),

	.vram2_req(reset ? vram_rst_req : vram2_req),
	.vram2_ack(),
	.vram2_addr(reset ? vram_rst_addr : VRAM2_ADDR[14:0]),
	.vram2_din(reset ? 8'd0 : VRAM2_D),
	.vram2_dout(VRAM2_Q),
	.vram2_we(reset | ~VRAM2_WE_N),

	.aram_addr(ARAM_ADDR),
	.aram_din(ARAM_D),
	.aram_dout(ARAM_Q),
	.aram_req(aram_req),
	.aram_req_ack(),
	.aram_we(~ARAM_WE_N)
);

assign SDRAM_CKE = 1'b1;

//////////////////////////  ROM DETECT  /////////////////////////////////

wire cart_download = ioctl_download;

reg        PAL;
reg  [7:0] rom_type;
reg  [7:0] rom_type_header;
reg  [7:0] mapper_header;
reg  [3:0] rom_size;
reg [23:0] rom_mask, ram_mask;

wire [8:0] hdr_prefix = LHRom_type == 2 ? { 8'h40, 1'b1 } : // ExHiROM
                        LHRom_type == 1 ? { 8'h00, 1'b1 } : // HiROM
						9'd0; // LoROM

always @(posedge clk_sys) begin
	reg [3:0] ram_size;

	if (cart_download) begin
		if(ioctl_wrD ^ ioctl_wr) begin
			if (ioctl_addr == 0) begin
				ram_size <= 4'h0;
				rom_type <= { 6'd0, LHRom_type };
			end

			if(ioctl_addr == { hdr_prefix, 15'h7FD4 }) mapper_header <= ioctl_dout[15:8];
			if(ioctl_addr == { hdr_prefix, 15'h7FD6 }) { rom_size, rom_type_header } <= ioctl_dout[11:0];
			if(ioctl_addr == { hdr_prefix, 15'h7FD8 }) ram_size <= ioctl_dout[3:0];

			rom_mask <= (24'd1024 << ((rom_size < 4'd7) ? 4'hC : rom_size)) - 1'd1;
			ram_mask <= ram_size ? (24'd1024 << ram_size) - 1'd1 : 24'd0;

			//DSP1
			if (((mapper_header == 8'h20 || mapper_header == 8'h21) && rom_type_header == 8'd3) ||
			    (mapper_header == 8'h30 && rom_type_header == 8'd5) || 
			    (mapper_header == 8'h31 && (rom_type_header == 8'd3 || rom_type_header == 8'd5))) rom_type[7] <= 1'b1;
			//DSP2
			else if (mapper_header == 8'h20 && rom_type_header == 8'd5) rom_type[7:4] <= 4'h9;
			//DSP4
			else if (mapper_header == 8'h30 && rom_type_header == 8'd3) rom_type[7:4] <= 4'hB;
			//OBC1
			//else if (mapper_header == 8'h30 && rom_type_header == 8'h25) rom_type[7:4] <= 4'hC;
		end
	end
	else begin
		PAL <= video_region;
	end
end

////////////////////////////  SYSTEM  ///////////////////////////////////

main #(.USE_DSPn(1'b1), .USE_CX4(1'b0), .USE_SDD1(1'b0), .USE_SA1(1'b0), .USE_GSU(1'b0), .USE_DLH(1'b1)) main
(
	.RESET_N(~reset),

	.MCLK(clk_sys), // 21.47727 / 21.28137
	.ACLK(clk_sys),

	.GSU_ACTIVE(),
	.GSU_TURBO(1'b0),

	.ROM_TYPE(rom_type),
	.ROM_MASK(rom_mask),
	.RAM_MASK(ram_mask),
	.PAL(PAL),
	.BLEND(BLEND),

	.ROM_ADDR(ROM_ADDR),
	.ROM_Q(ROM_Q),
	.ROM_CE_N(ROM_CE_N),
	.ROM_OE_N(ROM_OE_N),
	.ROM_WORD(ROM_WORD),

	.BSRAM_ADDR(BSRAM_ADDR),
	.BSRAM_D(BSRAM_D),
	.BSRAM_Q(BSRAM_Q),
	.BSRAM_CE_N(BSRAM_CE_N),
	.BSRAM_OE_N(BSRAM_OE_N),
	.BSRAM_WE_N(BSRAM_WE_N),

	.WRAM_ADDR(WRAM_ADDR),
	.WRAM_D(WRAM_D),
	.WRAM_Q(WRAM_Q),
	.WRAM_CE_N(WRAM_CE_N),
	.WRAM_OE_N(WRAM_OE_N),
	.WRAM_WE_N(WRAM_WE_N),
	.WRAM_RD_N(WRAM_RD_N),

	.VRAM_OE_N(VRAM_OE_N),

	.VRAM1_ADDR(VRAM1_ADDR),
	.VRAM1_DI(VRAM1_Q),
	.VRAM1_DO(VRAM1_D),
	.VRAM1_WE_N(VRAM1_WE_N),

	.VRAM2_ADDR(VRAM2_ADDR),
	.VRAM2_DI(VRAM2_Q),
	.VRAM2_DO(VRAM2_D),
	.VRAM2_WE_N(VRAM2_WE_N),

	.ARAM_ADDR(ARAM_ADDR),
	.ARAM_D(ARAM_D),
	.ARAM_Q(ARAM_Q),
	.ARAM_CE_N(ARAM_CE_N),
	.ARAM_OE_N(ARAM_OE_N),
	.ARAM_WE_N(ARAM_WE_N),

	.R(R),
	.G(G),
	.B(B),

	.FIELD(),
	.INTERLACE(),
	.HIGH_RES(),
	.DOTCLK(),

	.HBLANKn(HBLANKn),
	.VBLANKn(VBLANKn),
	.HSYNC(HSYNC),
	.VSYNC(VSYNC),

	.JOY1_DI(JOY1_DO),
	.JOY2_DI(JOY2_DO),
	.JOY_STRB(JOY_STRB),
	.JOY1_CLK(JOY1_CLK),
	.JOY2_CLK(JOY2_CLK),
	.JOY1_P6(JOY1_P6),
	.JOY2_P6(JOY2_P6),
	.JOY2_P6_in(1'b1),

	.GG_EN(0),
	.GG_CODE(),
	.GG_RESET(),
	.GG_AVAILABLE(0),

	.TURBO(0),
	.TURBO_ALLOW(),

	.AUDIO_L(audioL),
	.AUDIO_R(audioR)
);

//////////////////   VIDEO   //////////////////
wire [7:0] R,G,B;
wire       HSYNC,VSYNC;
wire       HBLANKn,VBLANKn;
wire       BLANK = ~(HBLANKn & VBLANKn);

mist_video #(.SD_HCNT_WIDTH(10), .COLOR_DEPTH(6), .OSD_AUTO_CE(1'b0)) mist_video
(
	.clk_sys(clk_sys),
	.scanlines(scanlines),
	.scandoubler_disable(scandoubler_disable),
	.ypbpr(ypbpr),
	.rotate(2'b00),
	.ce_divider(1'b0),
	.SPI_DI(SPI_DI),
	.SPI_SCK(SPI_SCK),
	.SPI_SS3(SPI_SS3),
	.HSync(~HSYNC),
	.VSync(~VSYNC),
	.R(BLANK ? 6'd0 : R[7:2]),
	.G(BLANK ? 6'd0 : G[7:2]),
	.B(BLANK ? 6'd0 : B[7:2]),
	.VGA_HS(VGA_HS),
	.VGA_VS(VGA_VS),
	.VGA_R(VGA_R),
	.VGA_G(VGA_G),
	.VGA_B(VGA_B)
);

//////////////////   AUDIO   //////////////////
wire [15:0] audioL, audioR;

jt12_dac2 #(16) dacl
(
	.clk(clk_sys),
	.rst(reset),
	.din(audioL),
	.dout(AUDIO_L)
);

jt12_dac2 #(16) dacr
(
	.clk(clk_sys),
	.rst(reset),
	.din(audioR),
	.dout(AUDIO_R)
);

////////////////////////////  I/O PORTS  ////////////////////////////////
wire [11:0] joy0 = { joystick0[7:6], joystick0[11:8], joystick0[5:0] };
wire [11:0] joy1 = { joystick1[7:6], joystick1[11:8], joystick1[5:0] };
wire [11:0] joy2 = { joystick2[7:6], joystick2[11:8], joystick2[5:0] };
wire [11:0] joy3 = { joystick3[7:6], joystick3[11:8], joystick3[5:0] };
wire [11:0] joy4 = { joystick4[7:6], joystick4[11:8], joystick4[5:0] };

wire       JOY_STRB;

wire [1:0] JOY1_DO;
wire       JOY1_CLK;
wire       JOY1_P6;
ioport port1
(
	.CLK(clk_sys),

	.PORT_LATCH(JOY_STRB),
	.PORT_CLK(JOY1_CLK),
	.PORT_P6(JOY1_P6),
	.PORT_DO(JOY1_DO),

	.JOYSTICK1(joy_swap ? joy1 : joy0),

	.MOUSE(ps2_mouse),
	.MOUSE_EN(mouse_mode[0])
);

wire [1:0] JOY2_DO;
wire       JOY2_CLK;
wire       JOY2_P6;
ioport port2
(
	.CLK(clk_sys),

	.MULTITAP(multitap),

	.PORT_LATCH(JOY_STRB),
	.PORT_CLK(JOY2_CLK),
	.PORT_P6(JOY2_P6),
	.PORT_DO(JOY2_DO),

	.JOYSTICK1(joy_swap ? joy0 : joy1),
	.JOYSTICK2(joy2),
	.JOYSTICK3(joy3),
	.JOYSTICK4(joy4),

	.MOUSE(ps2_mouse),
	.MOUSE_EN(mouse_mode[1])
);

endmodule