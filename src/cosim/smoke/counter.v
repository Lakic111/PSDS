// Listing 2.1 iz Mesovita.pdf (str. 100-101) -- prepisano doslovno.
// Poznat-dobar primer; ne menjati. Sluzi samo da potvrdi da xmsc_run radi.
module counter (
        dout,
        clk, rst, load, din
        );
   input clk;
   input rst;
   input load;
   input [7:0] din;
   output [7:0] dout;

   reg [7:0] cnt;

   always @ ( posedge clk )
     begin
        if (rst)
          cnt <= 8'd0;
        else
          if (load)
            cnt <= din;
          else
            cnt <= cnt + 1'b1;
     end

   assign dout = cnt;
endmodule
