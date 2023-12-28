`timescale 1ns/1ps

package abstract_if_pkg;

virtual class abstract_ifc #(int cwidth=2, int awidth=8, int dwidth=8);
    pure virtual task write (input logic [awidth-1:0] addr, input logic [dwidth-1:0] data);
    pure virtual task read (input logic [awidth-1:0] addr );
    pure virtual task rsp ();
endclass

endpackage

package cfg_pkg;

import abstract_if_pkg::*;

class cfg_driver;

    string name  = "";
    //logic [7:0] mem[int];
    //virtual intf v_intf;
    abstract_ifc #(2,8,8) if_ah;

    function new (string name);
        this.name = name;
    endfunction
    
    //The following tasks in the driver which addresses if cbs directly will be written in if itself

    virtual task write (int addr, int data);
        if_ah.write(addr,data);
    endtask

    virtual task read(int addr);
        if_ah.read(addr);
    endtask

    virtual task rsp();
        if_ah.rsp();
    endtask

endclass 

endpackage

//interface def


interface intf #(parameter CMD_WIDTH=2,ADDR_WIDTH=8,DATA_WIDTH=8) (input clk );

    logic [31:0] cfg = '0;
    logic cfg_val = '0;
    logic [1:0] cmd;
    logic [7:0] addr;
    wire  [7:0] data;
    logic [7:0] mem[int];

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

    import abstract_if_pkg::*;

    //creating the actual class
    class concrete_ifc #(int cwidth=2,int awidth=8,int dwidth=8) extends abstract_ifc #(2,8,8);
    //class concrete_ifc  extends abstract_ifc ;
    //class concrete_ifc #(int cwidth=2,int awidth=8,int dwidth=8) extends abstract_ifc ;
        task write (input logic [awidth-1:0] addr, input logic [dwidth-1:0] data);
            drv.cfg[31:24] <= addr;
            drv.cfg[23:16] <= data;
            drv.cfg[1:0]   <= 2;
            drv.cfg_val    <= 1;
            @(drv);
            drv.cfg_val    <= 0;
        endtask

        task read(input logic [awidth-1:0] addr);
            drv.cfg[31:24] <= addr;
            drv.cfg[1:0]   <= 1;
            drv.cfg_val    <= 1;
            @(drv);
            drv.cfg_val    <= 0;
        endtask

        task rsp();
        //While write put the address and data into mem
            forever begin
                @(drv);
                drv.data <= 'z; 
                if(drv.cmd == 2) begin
                    mem[drv.addr] = drv.data;
                    $display("updating the mem at addr %0x with %0x at time %0t",drv.addr,mem[drv.addr],$realtime);
                end
                if(drv.cmd == 1) begin
                    drv.data <= mem[drv.addr];
                    $display("driving out with data %0x at addr %0x at time %0t",drv.data,drv.addr,$realtime);
                end
            end
        endtask
    endclass

    concrete_ifc #(CMD_WIDTH,ADDR_WIDTH,DATA_WIDTH) if_ch = new();

    
endinterface

//dut def
module dut(

    input  logic clk,
    input  logic rst_n,
    intf.DUT dut_if 
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

//another dut instance which has another set of parameters


//tb_top def
module tb_top();

import cfg_pkg::*;

logic clk = 0;
logic rst_n = 1;

initial begin
    forever begin
        #5ns clk = ~clk;
    end
end

intf#(2,8,8)   i_intf1(clk);
intf#(2,16,16) i_intf2(clk);
intf#(3,32,32) i_intf3(clk);

cfg_driver drv;

initial begin
    //create the driver class
    drv = new("drv");
    drv.if_ah = i_intf1.if_ch;
    #10ns;
    //initiating the response
    fork
        drv.rsp();
    join_none
    rst_n = 0;
    #10ns;
    rst_n = 1;
    repeat(10)@ (i_intf1.drv);
    drv.write('haa,'h55);
    repeat(10)@ (i_intf1.drv);
    drv.write('hbb,'h66);
    repeat(10)@ (i_intf1.drv);
    drv.write('hcc,'h77);
    repeat(10)@ (i_intf1.drv);
    drv.read('haa);
    repeat(10)@ (i_intf1.drv);
    drv.write('hdd,'h99);
    repeat(10)@ (i_intf1.drv);
    drv.read('hbb);
    repeat(10)@ (i_intf1.drv);
    $finish();
end

dut dut_inst1 (clk, rst_n, i_intf1.DUT);
dut dut_inst2 (clk, rst_n, i_intf2.DUT);
dut dut_inst3 (clk, rst_n, i_intf3.DUT);

endmodule

