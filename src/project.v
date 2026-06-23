/*
 * Copyright (c) 2024 Your Name
 * SPDX-License-Identifier: Apache-2.0
 *
 * Tiny VGA Duck Hunt
 * Integrated into Tiny Tapeout project template
 */

`default_nettype none

module tt_um_Josue-Olivos-VGAExample (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path, active high
    input  wire       ena,      // always 1 when powered
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n, low to reset
);

  // ------------------------------------------------------------
  // VGA signals
  // ------------------------------------------------------------

  wire hsync;
  wire vsync;
  wire [1:0] R;
  wire [1:0] G;
  wire [1:0] B;
  wire video_active;
  wire [9:0] pix_x;
  wire [9:0] pix_y;

  // TinyVGA PMOD output mapping
  assign uo_out = {hsync, B[0], G[0], R[0], vsync, B[1], G[1], R[1]};

  // Unused bidirectional IOs
  assign uio_out = 8'b00000000;
  assign uio_oe  = 8'b00000000;

  // VGA timing generator
  // Make sure hvsync_generator.v is also included in src/
  hvsync_generator hvsync_gen (
    .clk(clk),
    .reset(~rst_n),
    .hsync(hsync),
    .vsync(vsync),
    .display_on(video_active),
    .hpos(pix_x),
    .vpos(pix_y)
  );

  // ------------------------------------------------------------
  // Input controls
  // ------------------------------------------------------------
  //
  // ui_in[0] = left
  // ui_in[1] = right
  // ui_in[2] = up
  // ui_in[3] = down
  // ui_in[4] = shoot
  // ui_in[5] = game reset
  // ui_in[6] = fast mode
  // ui_in[7] = unused
  //
  // Controls are hold-down style:
  // holding a direction moves that way;
  // releasing stops that movement.

  wire btn_left   = ui_in[0];
  wire btn_right  = ui_in[1];
  wire btn_up     = ui_in[2];
  wire btn_down   = ui_in[3];
  wire btn_shoot  = ui_in[4];
  wire game_reset = ui_in[5];
  wire fast_mode  = ui_in[6];

  // ------------------------------------------------------------
  // Frame tick detection
  // Game logic updates once per VGA frame
  // ------------------------------------------------------------

  reg vsync_prev;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      vsync_prev <= 1'b0;
    else
      vsync_prev <= vsync;
  end

  wire frame_tick = (vsync == 1'b1) && (vsync_prev == 1'b0);

  // ------------------------------------------------------------
  // Game registers
  // ------------------------------------------------------------

  reg [9:0] cross_x;
  reg [9:0] cross_y;

  reg [9:0] duck_x;
  reg [9:0] duck_y;
  reg [1:0] duck_dir;

  reg [3:0] score;
  reg [1:0] misses;

  reg [7:0] lfsr;
  reg [3:0] hit_flash;
  reg [5:0] turn_timer;

  reg shoot_prev;

  wire shoot_pressed = btn_shoot && !shoot_prev;

  // Duck dimensions
  localparam [9:0] DUCK_W = 10'd28;
  localparam [9:0] DUCK_H = 10'd18;

  // Duck directions
  localparam [1:0] DIR_UP       = 2'd0; // 90 degrees
  localparam [1:0] DIR_UP_RIGHT = 2'd1; // 45 degrees
  localparam [1:0] DIR_UP_LEFT  = 2'd2; // 135 degrees

  // Crosshair movement speed
  wire [2:0] cross_speed = fast_mode ? 3'd4 : 3'd2;

  // Duck movement speed increases slightly with score
  wire [2:0] duck_speed =
      fast_mode       ? 3'd4 :
      (score >= 4'd8) ? 3'd3 :
      (score >= 4'd4) ? 3'd2 :
                        3'd1;

  // Hit detection using simple bounding box
  wire cross_inside_duck =
      (cross_x >= duck_x) &&
      (cross_x <  duck_x + DUCK_W) &&
      (cross_y >= duck_y) &&
      (cross_y <  duck_y + DUCK_H);

  wire hit_now = shoot_pressed && cross_inside_duck;

  // Duck escapes if it leaves top, left, or right side
  wire duck_escaped =
      (duck_y <= 10'd4) ||
      ((duck_dir == DIR_UP_LEFT)  && (duck_x <= 10'd4)) ||
      ((duck_dir == DIR_UP_RIGHT) && (duck_x >= 10'd612));

  // ------------------------------------------------------------
  // Game update logic
  // ------------------------------------------------------------

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      cross_x    <= 10'd320;
      cross_y    <= 10'd240;

      duck_x     <= 10'd320;
      duck_y     <= 10'd400;
      duck_dir   <= DIR_UP;

      score      <= 4'd0;
      misses     <= 2'd0;

      lfsr       <= 8'b10101101;
      hit_flash  <= 4'd0;
      turn_timer <= 6'd30;

      shoot_prev <= 1'b0;
    end else begin

      // LFSR keeps running for pseudo-random duck positions and turns
      lfsr <= {lfsr[6:0], lfsr[7] ^ lfsr[5] ^ lfsr[4] ^ lfsr[3]};

      if (frame_tick) begin

        shoot_prev <= btn_shoot;

        // Manual game reset using ui_in[5]
        if (game_reset) begin
          cross_x    <= 10'd320;
          cross_y    <= 10'd240;

          duck_x     <= 10'd320;
          duck_y     <= 10'd400;
          duck_dir   <= DIR_UP;

          score      <= 4'd0;
          misses     <= 2'd0;

          hit_flash  <= 4'd0;
          turn_timer <= 6'd30;
        end else begin

          // Move crosshair
          if (btn_left && cross_x > 10'd14)
            cross_x <= cross_x - cross_speed;

          if (btn_right && cross_x < 10'd626)
            cross_x <= cross_x + cross_speed;

          if (btn_up && cross_y > 10'd14)
            cross_y <= cross_y - cross_speed;

          if (btn_down && cross_y < 10'd466)
            cross_y <= cross_y + cross_speed;

          // Hit flash countdown
          if (hit_flash != 4'd0)
            hit_flash <= hit_flash - 4'd1;

          // If player hits duck, score and respawn duck
          if (hit_now) begin
            if (score != 4'd15)
              score <= score + 4'd1;

            // Random-ish spawn position
            // X range: about 40 to 550
            // Y range: about 360 to 423, near bottom of screen
            duck_x <= 10'd40 + {1'b0, lfsr, 1'b0};
            duck_y <= 10'd360 + {4'b0000, lfsr[5:0]};

            // Random-ish direction: up, up-right, or up-left
            case (lfsr[1:0])
              2'b00: duck_dir <= DIR_UP;
              2'b01: duck_dir <= DIR_UP_RIGHT;
              2'b10: duck_dir <= DIR_UP_LEFT;
              default: duck_dir <= DIR_UP_RIGHT;
            endcase

            turn_timer <= 6'd20 + {2'b00, lfsr[3:0]};
            hit_flash  <= 4'd8;
          end

          // Duck escaped the screen
          else if (duck_escaped) begin
            duck_x <= 10'd40 + {1'b0, lfsr, 1'b0};
            duck_y <= 10'd360 + {4'b0000, lfsr[5:0]};

            case (lfsr[1:0])
              2'b00: duck_dir <= DIR_UP;
              2'b01: duck_dir <= DIR_UP_RIGHT;
              2'b10: duck_dir <= DIR_UP_LEFT;
              default: duck_dir <= DIR_UP_LEFT;
            endcase

            turn_timer <= 6'd20 + {2'b00, lfsr[3:0]};

            if (misses != 2'd3)
              misses <= misses + 2'd1;
          end

          // Otherwise duck moves according to direction
          else begin

            // Direction-change timer
            if (turn_timer == 6'd0) begin
              turn_timer <= 6'd20 + {2'b00, lfsr[3:0]};

              case (lfsr[1:0])
                2'b00: duck_dir <= DIR_UP;
                2'b01: duck_dir <= DIR_UP_RIGHT;
                2'b10: duck_dir <= DIR_UP_LEFT;
                default: duck_dir <= DIR_UP_RIGHT;
              endcase
            end else begin
              turn_timer <= turn_timer - 6'd1;
            end

            case (duck_dir)

              // 90 degrees: straight up
              DIR_UP: begin
                duck_y <= duck_y - duck_speed;
              end

              // 45 degrees: up-right
              DIR_UP_RIGHT: begin
                duck_x <= duck_x + duck_speed;
                duck_y <= duck_y - duck_speed;
              end

              // 135 degrees: up-left
              DIR_UP_LEFT: begin
                duck_x <= duck_x - duck_speed;
                duck_y <= duck_y - duck_speed;
              end

              default: begin
                duck_y <= duck_y - duck_speed;
              end

            endcase
          end
        end
      end
    end
  end

  // ------------------------------------------------------------
  // Simple blocky duck drawing
  // ------------------------------------------------------------

  wire duck_body =
      (pix_x >= duck_x + 10'd0)  &&
      (pix_x <  duck_x + 10'd18) &&
      (pix_y >= duck_y + 10'd7)  &&
      (pix_y <  duck_y + 10'd16);

  wire duck_head =
      (pix_x >= duck_x + 10'd16) &&
      (pix_x <  duck_x + 10'd24) &&
      (pix_y >= duck_y + 10'd2)  &&
      (pix_y <  duck_y + 10'd10);

  wire duck_beak =
      (pix_x >= duck_x + 10'd24) &&
      (pix_x <  duck_x + 10'd28) &&
      (pix_y >= duck_y + 10'd5)  &&
      (pix_y <  duck_y + 10'd8);

  wire duck_wing =
      (pix_x >= duck_x + 10'd5)  &&
      (pix_x <  duck_x + 10'd13) &&
      (pix_y >= duck_y + 10'd10) &&
      (pix_y <  duck_y + 10'd13);

  wire draw_duck = duck_body || duck_head || duck_beak || duck_wing;

  // ------------------------------------------------------------
  // Crosshair drawing
  // ------------------------------------------------------------

  wire cross_vertical =
      (pix_x >= cross_x - 10'd1)  &&
      (pix_x <= cross_x + 10'd1)  &&
      (pix_y >= cross_y - 10'd10) &&
      (pix_y <= cross_y + 10'd10);

  wire cross_horizontal =
      (pix_y >= cross_y - 10'd1)  &&
      (pix_y <= cross_y + 10'd1)  &&
      (pix_x >= cross_x - 10'd10) &&
      (pix_x <= cross_x + 10'd10);

  wire draw_crosshair = cross_vertical || cross_horizontal;

  // ------------------------------------------------------------
  // Basic scenery and score display
  // ------------------------------------------------------------

  wire draw_ground = pix_y >= 10'd420;

  // Tiny score bar in top-left corner
  wire draw_score_bar =
      (pix_x >= 10'd10) &&
      (pix_x <  10'd10 + {score, 3'b000}) &&
      (pix_y >= 10'd10) &&
      (pix_y <  10'd18);

  // Miss blocks in top-right corner
  wire draw_miss_0 =
      (misses >= 2'd1) &&
      (pix_x >= 10'd580) &&
      (pix_x <  10'd590) &&
      (pix_y >= 10'd10) &&
      (pix_y <  10'd20);

  wire draw_miss_1 =
      (misses >= 2'd2) &&
      (pix_x >= 10'd595) &&
      (pix_x <  10'd605) &&
      (pix_y >= 10'd10) &&
      (pix_y <  10'd20);

  wire draw_miss_2 =
      (misses >= 2'd3) &&
      (pix_x >= 10'd610) &&
      (pix_x <  10'd620) &&
      (pix_y >= 10'd10) &&
      (pix_y <  10'd20);

  wire draw_misses = draw_miss_0 || draw_miss_1 || draw_miss_2;

  // ------------------------------------------------------------
  // Pixel color priority
  // ------------------------------------------------------------

  reg [1:0] r_reg;
  reg [1:0] g_reg;
  reg [1:0] b_reg;

  always @(*) begin
    if (!video_active) begin
      r_reg = 2'b00;
      g_reg = 2'b00;
      b_reg = 2'b00;
    end

    // Hit flash background
    else if (hit_flash != 4'd0) begin
      r_reg = 2'b11;
      g_reg = 2'b11;
      b_reg = 2'b11;
    end

    // Crosshair: white
    else if (draw_crosshair) begin
      r_reg = 2'b11;
      g_reg = 2'b11;
      b_reg = 2'b11;
    end

    // Beak: red/orange-ish
    else if (duck_beak) begin
      r_reg = 2'b11;
      g_reg = 2'b01;
      b_reg = 2'b00;
    end

    // Wing: darker duck color
    else if (duck_wing) begin
      r_reg = 2'b10;
      g_reg = 2'b10;
      b_reg = 2'b00;
    end

    // Duck body/head: yellow
    else if (draw_duck) begin
      r_reg = 2'b11;
      g_reg = 2'b11;
      b_reg = 2'b00;
    end

    // Score bar: green
    else if (draw_score_bar) begin
      r_reg = 2'b00;
      g_reg = 2'b11;
      b_reg = 2'b00;
    end

    // Miss blocks: red
    else if (draw_misses) begin
      r_reg = 2'b11;
      g_reg = 2'b00;
      b_reg = 2'b00;
    end

    // Ground: green
    else if (draw_ground) begin
      r_reg = 2'b00;
      g_reg = 2'b10;
      b_reg = 2'b00;
    end

    // Sky background: blue
    else begin
      r_reg = 2'b00;
      g_reg = 2'b01;
      b_reg = 2'b11;
    end
  end

  assign R = r_reg;
  assign G = g_reg;
  assign B = b_reg;

  // Suppress unused warnings
  wire _unused_ok = &{ena, uio_in, ui_in[7], 1'b0};

endmodule
