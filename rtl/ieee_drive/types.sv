typedef struct packed {
   bit       atn;
   bit       eoi;
   bit       srq;
   bit       ren;
   bit       ifc;
   bit       dav;
   bit       ndac;
   bit       nrfd;

   bit [7:0] data;
} st_ieee_bus;
