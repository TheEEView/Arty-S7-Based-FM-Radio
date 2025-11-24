module derivative_sv #(
    parameter int DATA_WIDTH = 16
) (
    input  logic                     i_sysclk_40,
    input  logic                     i_rst,
    input  logic [DATA_WIDTH-1:0]    i_data,
    output logic [DATA_WIDTH-1:0]    o_derivative_data
);

    logic [DATA_WIDTH-1:0] data_buffered1;
    logic [DATA_WIDTH-1:0] data_buffered2;
    logic [DATA_WIDTH-1:0] derivative_data;

    // Derivative process.
    always_ff @(posedge i_sysclk_40) begin
        if (i_rst) begin
            data_buffered2  <= '0;
            data_buffered1  <= '0;
            derivative_data <= '0;
        end else begin
            // Calculate di(t-1)/dt.
            data_buffered2  <= data_buffered1;
            data_buffered1  <= i_data;
            derivative_data <= i_data - data_buffered2;
        end
    end

    assign o_derivative_data = derivative_data;

endmodule