`timescale 1ns/1ps

class cfg_driver;

    string name  = "";
    logic [7:0] mem[int];
    virtual intf v_intf;

    function new (string name, virtual intf vif);
        this.name = name;
        this.v_intf = vif;
    endfunction

    virtual task write (bit[7:0] addr, bit [7:0] data);
        v_intf.drv.cfg[31:24] <= addr;
        v_intf.drv.cfg[23:16] <= data;
        v_intf.drv.cfg[1:0]   <= 2;
        v_intf.drv.cfg_val    <= 1;
        @(v_intf.drv);
        v_intf.drv.cfg_val    <= 0;
    endtask

    virtual task read(bit[7:0] addr);
        v_intf.drv.cfg[31:24] <= addr;
        v_intf.drv.cfg[1:0]   <= 1;
        v_intf.drv.cfg_val    <= 1;
        @(v_intf.drv);
        v_intf.drv.cfg_val    <= 0;
    endtask

    virtual task rsp();
    //While write put the address and data into mem
        forever begin
            @(v_intf.drv);
            v_intf.drv.data <= 'z; 
            if(v_intf.drv.cmd == 2) begin
                mem[v_intf.drv.addr] = v_intf.drv.data;
                $display("updating the mem at addr %0x with %0x at time %0t",v_intf.drv.addr,mem[v_intf.drv.addr],$realtime);
            end
            if(v_intf.drv.cmd == 1) begin
                v_intf.drv.data <= mem[v_intf.drv.addr];
                $display("driving out with data %0x at addr %0x at time %0t",v_intf.drv.data,v_intf.drv.addr,$realtime);
            end
        end
    endtask

endclass 

//interface def
interface intf (input clk );

    logic [31:0] cfg = '0;
    logic cfg_val = '0;
    logic [1:0] cmd;
    logic [7:0] addr;
    wire  [7:0] data;

    modport DUT (input cfg, cfg_val, output cmd, addr, inout data); 
    modport TB  (output cfg, cfg_val, input cmd, addr, inout data); 
    modport MON (input cfg, cfg_val, cmd, addr, data); 

    clocking drv @(posedge clk);
        default input #10ps output #20ps ;
        output cfg, cfg_val;
        input cmd, addr;
        inout data;
    endclocking

    clocking mon @(posedge clk);
        default input #10ps output #20ps ;
        input cfg, cfg_val;
        input cmd, addr;
        input data;
    endclocking
    
endinterface

//dut def
module dut(

    input  logic clk,
    input  logic rst_n,
    intf.DUT dut_if 
    //input  logic [31:0] cfg;
    //input  logic cfg_val;
    //output logic cmd,
    //output logic [7:0] addr,
    //inout  wire  [7:0] data
);

logic rd_cyc ;
logic [7:0] rd_data, wdata;

assign dut_if.data  = wdata;

always @(posedge clk, negedge rst_n)
begin
    if (~rst_n) begin
        dut_if.cmd  <= '0;
        dut_if.addr <= '0;
        rd_cyc <= 0;
        rd_data <= '0;
        wdata <= 'z;
    end
    else begin
        wdata <= 'z; //by default no drive
        dut_if.cmd  <= '0; 
        if(rd_cyc) begin
            //latch the read data
            rd_data <= dut_if.data;
            rd_cyc <= '0;
        end
        if(dut_if.cfg_val) begin
            //decode cfg
            dut_if.cmd  <= dut_if.cfg[1:0]; //1 for read 2 for write
            dut_if.addr <= dut_if.cfg[31:24];
            if(dut_if.cfg[1:0] == 2) 
                wdata <=  dut_if.cfg[23:16];
            else
                rd_cyc <= 1;
            
        end
    end

end

endmodule

//tb_top def
module tb_top();

logic clk = 0;
logic rst_n = 1;

initial begin
    forever begin
        #5ns clk = ~clk;
    end
end
intf i_intf(clk);
cfg_driver drv;
initial begin
    //create the driver class
    drv = new("drv",i_intf);
    #10ns;
    //initiating the response
    fork
        drv.rsp();
    join_none
    rst_n = 0;
    #10ns;
    rst_n = 1;
    repeat(10)@ (i_intf.drv);
    drv.write('haa,'h55);
    repeat(10)@ (i_intf.drv);
    drv.write('hbb,'h66);
    repeat(10)@ (i_intf.drv);
    drv.write('hcc,'h77);
    repeat(10)@ (i_intf.drv);
    drv.read('haa);
    repeat(10)@ (i_intf.drv);
    drv.write('hdd,'h99);
    repeat(10)@ (i_intf.drv);
    drv.read('hbb);
    repeat(10)@ (i_intf.drv);
    $finish();
end

dut dut_inst (clk, rst_n, i_intf.DUT);

endmodule

