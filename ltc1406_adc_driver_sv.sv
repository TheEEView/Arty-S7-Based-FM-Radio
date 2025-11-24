module ltc1406_adc_driver_sv #(
    parameter int ENOB = 7  // ADC effective number of bits
) (
    input  logic             i_sysclk_40,
    input  logic             i_rst,
    output logic             o_ltc1406_nshutdown,  // ADC Power Down
    output logic             o_ltc1406_clk_20,     // ADC 20 MHz clk
    input  logic             i_ltc1406_d7,         // ADC data bit 7
    input  logic             i_ltc1406_d6,         // ADC data bit 6
    input  logic             i_ltc1406_d5,         // ADC data bit 5
    input  logic             i_ltc1406_d4,         // ADC data bit 4
    input  logic             i_ltc1406_d3,         // ADC data bit 3
    input  logic             i_ltc1406_d2,         // ADC data bit 2
    input  logic             i_ltc1406_d1,         // ADC data bit 1
    output logic [ENOB-1:0]  o_parallel_adc_data,  // Serial->Parallel converted ADC data
    output logic             o_adc_dv              // Active when new parallel data is ready
);

    logic adc_clk;

    always_ff @(posedge i_sysclk_40) begin
        if (i_rst) begin
            o_adc_dv            <= '0;
            o_ltc1406_nshutdown <= 1'b1;  // Hold ADC off during reset
            adc_clk             <= '0;
        end else begin
            o_ltc1406_nshutdown <= '0;    // Enable outputs
            // Generate free running ADC clock
            adc_clk             <= ~adc_clk;

            // Sample data, toggle validity and perform parallel->serial conversion on the negative adc clock edge
            if (adc_clk) begin
                o_adc_dv            <= '0;
                o_parallel_adc_data <= {i_ltc1406_d7, i_ltc1406_d6, i_ltc1406_d5, i_ltc1406_d4, 
                                        i_ltc1406_d3, i_ltc1406_d2, i_ltc1406_d1};
            end else begin
                o_adc_dv            <= 1'b1;
            end
        end
    end

    assign o_ltc1406_clk_20 = adc_clk;

endmodule