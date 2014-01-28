pcui_alicia
===========

Hi Alicia,
This is the fortran version of the code you have been using. It is called PCUI, named after the author of the code.
There are several things you will need to do to get started:

1) Modify size.inc with the number of processors and grid points in x,y,z
   NOTE: Y is the vertical coordinate in this code!!!!!! not Z as in CNS. 
   
2) Modify cavity.f variables bx,by,bz at the top of the file. These are the dimensions of your grid in x,y,z

3) Modify io.f dtime (time step), nsave (how often to save data), ncont (how often to save restart data),
   maxstep (number of time steps), vis (viscosity), ak (diffusivity)

4) Use initialize_pcui.m to create grid files, which will be read into the code in cavity.f. On line 57 in the mfile,
   write the name of a .mat file that contains 3D matrices x,y,z (as output by the CNS code). Note how I am accounting
   for the change from y to z and vice versa.
   
5) Modify your stratification in init.f (phi at line 140)

6) This is the hardest step. You will need to add your density inflow. I need to think about how to do this a 
   little more, so we can talk about it when you get there. For now try to run a simple flow in a simple domain
   and see if it works.
   
Good luck! Using git should help us be able to look at the same code, instead of emailing code back and forth as 
we have been doing.
-Bobby
