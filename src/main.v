//==============================================================================
// UART Receiver Module
//==============================================================================
module uart_rx #(
    parameter CLK_FREQ = 12_000_000,
    parameter BAUD_RATE = 115200
)(
    input wire clk,
    input wire rst,
    input wire rx,
    output reg [7:0] data,
    output reg valid
);
    localparam CLKS_PER_BIT = CLK_FREQ / BAUD_RATE;
    localparam HALF_BIT = CLKS_PER_BIT / 2;
    
    reg [15:0] clk_count;
    reg [2:0] bit_index;
    reg [7:0] rx_byte;
    reg [2:0] state;
    
    localparam IDLE  = 3'd0;
    localparam START = 3'd1;
    localparam DATA  = 3'd2;
    localparam STOP  = 3'd3;
    
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= IDLE;
            clk_count <= 0;
            bit_index <= 0;
            data <= 0;
            valid <= 0;
            rx_byte <= 0;
        end else begin
            valid <= 0;
            
            case (state)
                IDLE: begin
                    clk_count <= 0;
                    bit_index <= 0;
                    if (rx == 0) begin
                        state <= START;
                    end
                end
                
                START: begin
                    if (clk_count == HALF_BIT) begin
                        if (rx == 0) begin
                            clk_count <= 0;
                            state <= DATA;
                        end else begin
                            state <= IDLE;
                        end
                    end else begin
                        clk_count <= clk_count + 1;
                    end
                end
                
                DATA: begin
                    if (clk_count == CLKS_PER_BIT - 1) begin
                        clk_count <= 0;
                        rx_byte[bit_index] <= rx;
                        if (bit_index == 7) begin
                            state <= STOP;
                        end else begin
                            bit_index <= bit_index + 1;
                        end
                    end else begin
                        clk_count <= clk_count + 1;
                    end
                end
                
                STOP: begin
                    if (clk_count == CLKS_PER_BIT - 1) begin
                        data <= rx_byte;
                        valid <= 1;
                        state <= IDLE;
                    end else begin
                        clk_count <= clk_count + 1;
                    end
                end
                
                default: state <= IDLE;
            endcase
        end
    end
endmodule

//==============================================================================
// UART Transmitter Module
//==============================================================================
module uart_tx #(
    parameter CLK_FREQ = 12_000_000,
    parameter BAUD_RATE = 115200
)(
    input wire clk,
    input wire rst,
    input wire [7:0] data,
    input wire start,
    output reg tx,
    output reg busy
);
    localparam CLKS_PER_BIT = CLK_FREQ / BAUD_RATE;
    
    reg [15:0] clk_count;
    reg [2:0] bit_index;
    reg [7:0] tx_byte;
    reg [2:0] state;
    
    localparam IDLE  = 3'd0;
    localparam START = 3'd1;
    localparam DATA  = 3'd2;
    localparam STOP  = 3'd3;
    
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= IDLE;
            clk_count <= 0;
            bit_index <= 0;
            tx <= 1;
            busy <= 0;
            tx_byte <= 0;
        end else begin
            case (state)
                IDLE: begin
                    tx <= 1;
                    clk_count <= 0;
                    bit_index <= 0;
                    if (start) begin
                        tx_byte <= data;
                        busy <= 1;
                        state <= START;
                    end else begin
                        busy <= 0;
                    end
                end
                
                START: begin
                    tx <= 0;
                    if (clk_count == CLKS_PER_BIT - 1) begin
                        clk_count <= 0;
                        state <= DATA;
                    end else begin
                        clk_count <= clk_count + 1;
                    end
                end
                
                DATA: begin
                    tx <= tx_byte[bit_index];
                    if (clk_count == CLKS_PER_BIT - 1) begin
                        clk_count <= 0;
                        if (bit_index == 7) begin
                            state <= STOP;
                        end else begin
                            bit_index <= bit_index + 1;
                        end
                    end else begin
                        clk_count <= clk_count + 1;
                    end
                end
                
                STOP: begin
                    tx <= 1;
                    if (clk_count == CLKS_PER_BIT - 1) begin
                        state <= IDLE;
                    end else begin
                        clk_count <= clk_count + 1;
                    end
                end
                
                default: state <= IDLE;
            endcase
        end
    end
endmodule

//==============================================================================
// Simple MLP Core - 4 inputs, 4 hidden (ReLU), 2 outputs
// Using 8-bit values (0-255) for simplicity
//==============================================================================
module mlp_core (
    input wire clk,
    input wire rst,
    input wire [7:0] in0, in1, in2, in3,
    input wire compute,
    output reg [7:0] out0, out1,
    output reg done
);
    // Fixed weights (you can modify these for your application)
    // Hidden layer weights (4 inputs × 4 neurons = 16 weights)
    // Using 8-bit signed weights (-128 to 127)
    reg signed [7:0] w_h [0:15];
    reg signed [7:0] b_h [0:3];
    
    // Output layer weights (4 hidden × 2 outputs = 8 weights)
    reg signed [7:0] w_o [0:7];
    reg signed [7:0] b_o [0:1];
    
    // Hidden layer activations
    reg signed [15:0] h_sum [0:3];
    reg [7:0] h_act [0:3];
    
    // Output layer sums
    reg signed [15:0] o_sum [0:1];
    
    reg [3:0] state;
    integer i;
    
    localparam IDLE = 0, HIDDEN = 1, RELU = 2, OUTPUT = 3, DONE = 4;
    
    initial begin
        // Example weights - XOR-like pattern
        // You should replace these with trained weights
        w_h[0] = 8'sd32;   w_h[1] = 8'sd16;   w_h[2] = -8'sd24;  w_h[3] = 8'sd8;
        w_h[4] = -8'sd28;  w_h[5] = 8'sd20;   w_h[6] = 8'sd12;   w_h[7] = -8'sd16;
        w_h[8] = 8'sd24;   w_h[9] = -8'sd18;  w_h[10] = 8'sd14;  w_h[11] = 8'sd22;
        w_h[12] = -8'sd20; w_h[13] = 8'sd26;  w_h[14] = -8'sd10; w_h[15] = 8'sd30;
        
        b_h[0] = 8'sd10; b_h[1] = -8'sd5; b_h[2] = 8'sd8; b_h[3] = -8'sd12;
        
        w_o[0] = 8'sd40;  w_o[1] = -8'sd35; w_o[2] = 8'sd30;  w_o[3] = 8'sd25;
        w_o[4] = -8'sd38; w_o[5] = 8'sd42;  w_o[6] = -8'sd28; w_o[7] = 8'sd32;
        
        b_o[0] = 8'sd15; b_o[1] = -8'sd18;
    end
    
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= IDLE;
            done <= 0;
            out0 <= 0;
            out1 <= 0;
        end else begin
            case (state)
                IDLE: begin
                    done <= 0;
                    if (compute) begin
                        // Compute hidden layer
                        h_sum[0] <= ($signed({1'b0, in0}) * w_h[0]) + 
                                    ($signed({1'b0, in1}) * w_h[1]) + 
                                    ($signed({1'b0, in2}) * w_h[2]) + 
                                    ($signed({1'b0, in3}) * w_h[3]) + 
                                    ($signed(b_h[0]) << 6);
                        h_sum[1] <= ($signed({1'b0, in0}) * w_h[4]) + 
                                    ($signed({1'b0, in1}) * w_h[5]) + 
                                    ($signed({1'b0, in2}) * w_h[6]) + 
                                    ($signed({1'b0, in3}) * w_h[7]) + 
                                    ($signed(b_h[1]) << 6);
                        h_sum[2] <= ($signed({1'b0, in0}) * w_h[8]) + 
                                    ($signed({1'b0, in1}) * w_h[9]) + 
                                    ($signed({1'b0, in2}) * w_h[10]) + 
                                    ($signed({1'b0, in3}) * w_h[11]) + 
                                    ($signed(b_h[2]) << 6);
                        h_sum[3] <= ($signed({1'b0, in0}) * w_h[12]) + 
                                    ($signed({1'b0, in1}) * w_h[13]) + 
                                    ($signed({1'b0, in2}) * w_h[14]) + 
                                    ($signed({1'b0, in3}) * w_h[15]) + 
                                    ($signed(b_h[3]) << 6);
                        state <= RELU;
                    end
                end
                
                RELU: begin
                    // ReLU activation and scale back
                    for (i = 0; i < 4; i = i + 1) begin
                        if (h_sum[i][15]) begin  // Negative
                            h_act[i] <= 0;
                        end else begin
                            h_act[i] <= (h_sum[i] > 16'sd16320) ? 8'd255 : h_sum[i][13:6];
                        end
                    end
                    state <= OUTPUT;
                end
                
                OUTPUT: begin
                    // Compute output layer
                    o_sum[0] <= ($signed({1'b0, h_act[0]}) * w_o[0]) + 
                                ($signed({1'b0, h_act[1]}) * w_o[1]) + 
                                ($signed({1'b0, h_act[2]}) * w_o[2]) + 
                                ($signed({1'b0, h_act[3]}) * w_o[3]) + 
                                ($signed(b_o[0]) << 6);
                    o_sum[1] <= ($signed({1'b0, h_act[0]}) * w_o[4]) + 
                                ($signed({1'b0, h_act[1]}) * w_o[5]) + 
                                ($signed({1'b0, h_act[2]}) * w_o[6]) + 
                                ($signed({1'b0, h_act[3]}) * w_o[7]) + 
                                ($signed(b_o[1]) << 6);
                    state <= DONE;
                end
                
                DONE: begin
                    // Scale and clamp outputs
                    out0 <= (o_sum[0][15]) ? 8'd0 : 
                            (o_sum[0] > 16'sd16320) ? 8'd255 : o_sum[0][13:6];
                    out1 <= (o_sum[1][15]) ? 8'd0 : 
                            (o_sum[1] > 16'sd16320) ? 8'd255 : o_sum[1][13:6];
                    done <= 1;
                    state <= IDLE;
                end
                
                default: state <= IDLE;
            endcase
        end
    end
endmodule

//==============================================================================
// Top Module - MLP with UART Interface
//==============================================================================
module top (
    input wire CLK,
    input wire RX,
    output wire TX,
    output wire LEDR_N,
    output wire LEDG_N
);
    reg rst = 0;
    wire [7:0] rx_data;
    wire rx_valid;
    reg [7:0] tx_data;
    reg tx_start;
    wire tx_busy;
    
    // MLP signals
    reg [7:0] inputs [0:3];
    reg [1:0] input_count;
    wire [7:0] mlp_out0, mlp_out1;
    reg mlp_compute;
    wire mlp_done;
    
    // State machine
    reg [2:0] state;
    localparam WAIT_INPUT = 0, WAIT_CMD = 1, COMPUTE = 2, SEND_OUT0 = 3, SEND_OUT1 = 4;
    
    // LED indicators
    reg led_rx = 0;
    reg led_tx = 0;
    assign LEDR_N = ~led_rx;
    assign LEDG_N = ~led_tx;
    
    // UART instances
    uart_rx #(.CLK_FREQ(12_000_000), .BAUD_RATE(115200)) 
    rx_inst (.clk(CLK), .rst(rst), .rx(RX), .data(rx_data), .valid(rx_valid));
    
    uart_tx #(.CLK_FREQ(12_000_000), .BAUD_RATE(115200))
    tx_inst (.clk(CLK), .rst(rst), .data(tx_data), .start(tx_start), .tx(TX), .busy(tx_busy));
    
    // MLP instance
    mlp_core mlp (
        .clk(CLK), .rst(rst),
        .in0(inputs[0]), .in1(inputs[1]), .in2(inputs[2]), .in3(inputs[3]),
        .compute(mlp_compute), .out0(mlp_out0), .out1(mlp_out1), .done(mlp_done)
    );
    
    // Main control logic
    always @(posedge clk) begin
        tx_start <= 0;
        mlp_compute <= 0;
        
        if (rx_valid) begin
            led_rx <= 1;
            
            case (state)
                WAIT_INPUT: begin
                    inputs[input_count] <= rx_data;
                    if (input_count == 3) begin
                        input_count <= 0;
                        state <= WAIT_CMD;
                    end else begin
                        input_count <= input_count + 1;
                    end
                end
                
                WAIT_CMD: begin
                    if (rx_data == 8'h49) begin  // 'I' command for inference
                        mlp_compute <= 1;
                        state <= COMPUTE;
                    end else begin
                        state <= WAIT_INPUT;  // Reset if bad command
                        input_count <= 0;
                    end
                end
                
                default: begin
                    state <= WAIT_INPUT;
                    input_count <= 0;
                end
            endcase
        end else begin
            led_rx <= 0;
        end
        
        case (state)
            COMPUTE: begin
                if (mlp_done) begin
                    tx_data <= mlp_out0;
                    tx_start <= 1;
                    state <= SEND_OUT0;
                end
            end
            
            SEND_OUT0: begin
                if (!tx_busy && !tx_start) begin
                    tx_data <= mlp_out1;
                    tx_start <= 1;
                    state <= SEND_OUT1;
                end
            end
            
            SEND_OUT1: begin
                if (!tx_busy && !tx_start) begin
                    state <= WAIT_INPUT;
                    input_count <= 0;
                end
            end
        endcase
        
        led_tx <= tx_busy;
    end
endmodule