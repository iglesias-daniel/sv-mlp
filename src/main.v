/* -- By Daniel Iglesias & Claude AI (2025) -- */

//==============================================================================
// UART Receiver Module
//==============================================================================
module uart_rx #(
    parameter CLK_FREQ = 12_000_000,  // iCEBreaker default clock
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
                    if (rx == 0) begin  // Start bit detected
                        state <= START;
                    end
                end
                
                START: begin
                    if (clk_count == HALF_BIT) begin
                        if (rx == 0) begin  // Confirm start bit
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
                    tx <= 0;  // Start bit
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
                    tx <= 1;  // Stop bit
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
// Top Module - Simple Echo/Loopback Example
//==============================================================================
module uart_top (
    input wire CLK,          // 12 MHz clock from iCEBreaker
    input wire RX,           // UART RX pin
    output wire TX,          // UART TX pin
    output wire LEDR_N,      // Red LED (active low)
    output wire LEDG_N       // Green LED (active low)
);
    // Internal signals
    reg rst = 0;
    wire [7:0] rx_data;
    wire rx_valid;
    reg [7:0] tx_data;
    reg tx_start;
    wire tx_busy;
    
    // LED indicators
    reg led_rx = 0;
    reg led_tx = 0;
    assign LEDR_N = ~led_rx;  // Red LED shows RX activity
    assign LEDG_N = ~led_tx;  // Green LED shows TX activity
    
    // UART instances
    uart_rx #(
        .CLK_FREQ(12_000_000),
        .BAUD_RATE(115200)
    ) rx_inst (
        .clk(CLK),
        .rst(rst),
        .rx(RX),
        .data(rx_data),
        .valid(rx_valid)
    );
    
    uart_tx #(
        .CLK_FREQ(12_000_000),
        .BAUD_RATE(115200)
    ) tx_inst (
        .clk(CLK),
        .rst(rst),
        .data(tx_data),
        .start(tx_start),
        .tx(TX),
        .busy(tx_busy)
    );
    
    // Echo logic - send back received data
    always @(posedge CLK) begin
        tx_start <= 0;
        
        if (rx_valid) begin
            tx_data <= rx_data;
            tx_start <= 1;
            led_rx <= 1;
        end
        
        if (tx_busy) begin
            led_tx <= 1;
        end else begin
            led_tx <= 0;
            led_rx <= 0;
        end
    end
endmodule