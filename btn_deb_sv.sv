// Simple debounce component with parameters to control the debounce count and button active level
module btn_deb_sv #(
    parameter int DEB_CNT         = 1000000,  // Number of clock cycles the button needs to remain stable for without switch bouncing
    parameter bit ACTIVE_HIGH_BTN = 1'b1      // Button logic state to check for, high meaning a logic high refers to the button being stable once bouncing has finished
) (
    input  logic i_sysclk_40,  // Clock input
    input  logic i_rst,        // Synchronous active high reset
    input  logic i_btn,        // Asynchronous button input
    output logic o_pulse       // Single clock cycle output pulse indicating a single button press after debouncing/filtering
);

logic [$clog2(DEB_CNT+1)-1:0] db_cnt;

always_ff @(posedge i_sysclk_40) begin
    // Clear counter and hold pulse low during reset
    if (i_rst) begin
        db_cnt  <= '0;
        o_pulse <= '0;
    end else begin
        if (ACTIVE_HIGH_BTN) begin
            // While the button is '1' we increment a counter until we hit the debounce count
            // at that point we send a one clock cycle active high output pulse
            if (i_btn) begin
                if (db_cnt < DEB_CNT) begin
                    db_cnt <= db_cnt + 1'b1;
                end
            end else begin
                // Reset the count if the button status toggles due to switch bouncing
                db_cnt <= '0;
            end
        end else begin
            // While the button is '0' we increment a counter until we hit the debounce count
            // at that point we send a one clock cycle active high output pulse
            if (!i_btn) begin
                if (db_cnt < DEB_CNT) begin
                    db_cnt <= db_cnt + 1'b1;
                end
            end else begin
                // Reset the count if the button status toggles due to switch bouncing
                db_cnt <= '0;
            end
        end
            
        // Single clock cycle active high output pulse
        if (db_cnt == DEB_CNT - 1) begin
            o_pulse <= 1'b1;
        end else begin
            o_pulse <= 1'b0;
        end
    end
end

endmodule
