ccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc      
      
      subroutine energy

      include "size.inc"
      include "mpif.h"
      include "mpi.inc"
      include "metric.inc"
      include "cavity.inc"
      include "para.inc"
      include "eddy.inc"
      INCLUDE "ns.inc"

      double precision rho_local(nni*nnj*nnk)
      double precision volume_local(nni*nnj*nnk)
      double precision lp_local(nni*nnj*nnk)
      double precision wksp_local(nni*nnj*nnk)
      double precision samples_local(px*py*pz)
      double precision samples_global(px*px*py*py*pz*pz)
      double precision pivots(px*py*pz-1)
      double precision, allocatable :: rho_sorted(:)
      double precision, allocatable :: volume_sorted(:)
      double precision, allocatable :: lp_sorted(:)
      double precision, allocatable :: wksp_sorted(:)
      double precision Ep, Eb, phi_d 
      double precision cell_bottom, cell_height, z_star
      double precision slope, yend, Lflat, xlb, xlt, cell_area
c     double precision area, xl

      integer i, j, k, m, N_local, N_global, Np, indx
      integer local_sorted_array_size
      integer iwksp_local(nni*nnj*nnk)
      integer, allocatable :: iwksp_sorted(:)
      integer sorted_array_part_sizes_send(px*py*pz)
      integer sorted_array_part_sizes_recv(px*py*pz)
      integer send_displacements(px*py*pz)
      integer recv_displacements(px*py*pz)

      character*4 :: ID

C.....Rearrange density and corresponding values into 1D array 
C     on each proc and calculate Ep
      m = 0
      Ep = 0.D0
      do k = 1, nnk
      do j = 1, nnj
      do i = 1, nni
         m = m + 1
         rho_local(m) = phi(i,j,k)
         volume_local(m) = 1/jac(i,j,k)
         lp_local(m) = jac(i,j,k) *
     <	 (g11(i,  j,  k  ) * ( phi(i+1,j,  k  ) - phi(i,j,k) )  
     <        + 
     <		g11(i-1,j,  k  ) * ( phi(i-1,j,  k  ) - phi(i,j,k) )   
     <        + 
     <		g22(i,  j,  k  ) * ( phi(i,  j+1,k  ) - phi(i,j,k) )   
     <        + 
     <		g22(i,  j-1,k  ) * ( phi(i,  j-1,k  ) - phi(i,j,k) )  
     <        + 
     <		g33(i,  j,  k  ) * ( phi(i,  j,  k+1) - phi(i,j,k) )  
     <        + 
     <		g33(i,  j,  k-1) * ( phi(i,  j,  k-1) - phi(i,j,k) ) 
     <        + 
     <		( g12(i,  j,k) * ( phi(i,  j+1,k) - phi(i,  j-1,k) 
     <		                 + phi(i+1,j+1,k) - phi(i+1,j-1,k) )
     <		+ g13(i,  j,k) * ( phi(i,  j,k+1) - phi(i,  j,k-1)
     <		                 + phi(i+1,j,k+1) - phi(i+1,j,k-1) ) ) 
     <        - 
     <		( g12(i-1,j,k) * ( phi(i,  j+1,k) - phi(i,  j-1,k)
     <		                 + phi(i-1,j+1,k) - phi(i-1,j-1,k) )
     <		+ g13(i-1,j,k) * ( phi(i,  j,k+1) - phi(i,  j,k-1)
     <		                 + phi(i-1,j,k+1) - phi(i-1,j,k-1) ) )
     <        + 
     <		( g23(i,j,  k) * ( phi(i,j,  k+1) - phi(i,j,  k-1)
     <		                 + phi(i,j+1,k+1) - phi(i,j+1,k-1) )
     <		+ g21(i,j,  k) * ( phi(i+1,j,  k) - phi(i-1,j,  k)
     <		                 + phi(i+1,j+1,k) - phi(i-1,j+1,k) ) ) 
     <        - 
     <		( g23(i,j-1,k) * ( phi(i,j,  k+1) - phi(i,j,  k-1)
     <		                 + phi(i,j-1,k+1) - phi(i,j-1,k-1) ) 
     <		+ g21(i,j-1,k) * ( phi(i+1,j,  k) - phi(i-1,j,  k)
     <		                 + phi(i+1,j-1,k) - phi(i-1,j-1,k) ) )
     <        + 
     <		( g31(i,j,k  ) * ( phi(i+1,j,k  ) - phi(i-1,j,k  )
     <		                 + phi(i+1,j,k+1) - phi(i-1,j,k+1) )
     <		+ g32(i,j,k  ) * ( phi(i,j+1,k  ) - phi(i,j-1,k  )
     <		                 + phi(i,j+1,k+1) - phi(i,j-1,k+1) ) ) 
     <        - 
     <		( g31(i,j,k-1) * ( phi(i+1,j,k  ) - phi(i-1,j,k  )
     <		                 + phi(i+1,j,k-1) - phi(i-1,j,k-1) )
     <		+ g32(i,j,k-1) * ( phi(i,j+1,k  ) - phi(i,j-1,k  )
     <		                 + phi(i,j+1,k-1) - phi(i,j-1,k-1) ) ) )

         Ep = Ep + phi(i,j,k)*(xp(i,j,k,2)+by)*(1/jac(i,j,k))
      enddo
      enddo
      enddo
      N_local = m
      N_global = ni*nj*nk
      Np = px*py*pz

      Ep = g*Ep
      call global_sum(Ep)

C.....Sort initial arrays on each proc
      call sort3(N_local,rho_local,volume_local,lp_local,
     <           wksp_local,iwksp_local)

      if (Np .gt. 1) then
c        Aggregate samples of local arrays on root
         do i = 0, Np-1
            indx = i*N_global/(Np*Np)
            samples_local(i+1) = rho_local(indx+1)
         enddo

         call MPI_GATHER( samples_local, Np,MPI_DOUBLE_PRECISION,
     <                    samples_global,Np,MPI_DOUBLE_PRECISION,
     <                    0,MPI_COMM_WORLD,ierr )
         call MPI_BARRIER( MPI_COMM_WORLD,ierr )

c        Select pivots from global samples on root and broadcast them
         if ( MYID .EQ. 0) then
            call sort(Np*Np,samples_global)
            do i = 0, Np-2
               pivots(i+1) = samples_global((i+1)*Np+(Np/2))
            enddo
         endif
               
         call MPI_BCAST( pivots,Np-1,MPI_DOUBLE_PRECISION,0,
     <                   MPI_COMM_WORLD,ierr )
         call MPI_BARRIER( MPI_COMM_WORLD,ierr )

c        Split local arrays into Np parts using pivots
c        Alltoall exchange of array_part sizes from and to each node
         do i = 1, Np
            sorted_array_part_sizes_send(i) = 0
         enddo

         i = 1
         m = 1
         do while (m .le. N_local .and. i .le. Np-1)
            if (rho_local(m) .le. pivots(i)) then
               sorted_array_part_sizes_send(i) =
     <                            sorted_array_part_sizes_send(i) + 1
            else
               i = i+1
               m = m-1
            endif
            m = m+1
         enddo

         sorted_array_part_sizes_send(Np) = N_local - (m-1)

         call MPI_ALLTOALL(sorted_array_part_sizes_send, 1, MPI_INTEGER,
     <                     sorted_array_part_sizes_recv, 1, MPI_INTEGER,
     <                     MPI_COMM_WORLD, ierr )
         call MPI_BARRIER( MPI_COMM_WORLD,ierr )

c        Calculate size for new local array
c        Alltoall exchange of sub-array parts with known 
c        sizes/displacements
         local_sorted_array_size = 0
         do i = 1, Np
            local_sorted_array_size = local_sorted_array_size +
     <                                sorted_array_part_sizes_recv(i)
         enddo

         allocate( rho_sorted(local_sorted_array_size),
     <             volume_sorted(local_sorted_array_size),
     <             lp_sorted(local_sorted_array_size),
     <             wksp_sorted(local_sorted_array_size),
     <             iwksp_sorted(local_sorted_array_size) )

         send_displacements(1) = 0
         recv_displacements(1) = 0
         do i = 2, Np
            send_displacements(i) = send_displacements(i-1) +
     <                              sorted_array_part_sizes_send(i-1)
            recv_displacements(i) = recv_displacements(i-1) +
     <                              sorted_array_part_sizes_recv(i-1)
         enddo

         call MPI_ALLTOALLV( rho_local,sorted_array_part_sizes_send,
     <                       send_displacements,MPI_DOUBLE_PRECISION,
     <                       rho_sorted,sorted_array_part_sizes_recv,
     <                       recv_displacements,MPI_DOUBLE_PRECISION,
     <                       MPI_COMM_WORLD,ierr )
         call MPI_ALLTOALLV( volume_local,sorted_array_part_sizes_send,
     <                       send_displacements,MPI_DOUBLE_PRECISION,
     <                       volume_sorted,sorted_array_part_sizes_recv,
     <                       recv_displacements,MPI_DOUBLE_PRECISION,
     <                       MPI_COMM_WORLD,ierr )
         call MPI_ALLTOALLV( lp_local,sorted_array_part_sizes_send,
     <                       send_displacements,MPI_DOUBLE_PRECISION,
     <                       lp_sorted,sorted_array_part_sizes_recv,
     <                       recv_displacements,MPI_DOUBLE_PRECISION,
     <                       MPI_COMM_WORLD,ierr )
         call MPI_BARRIER( MPI_COMM_WORLD,ierr )
     
c        sort the distributed global density array with corresponding 
c        variables (volume)
         call sort3(local_sorted_array_size,rho_sorted,volume_sorted,
     <              lp_sorted,wksp_sorted,iwksp_sorted)
      else
         local_sorted_array_size = N_local
         allocate( rho_sorted(local_sorted_array_size),
     <             volume_sorted(local_sorted_array_size),
     <             lp_sorted(local_sorted_array_size) ) 
         rho_sorted = rho_local
         volume_sorted = volume_local
         lp_sorted = lp_local
      endif

C.....Now density (and corresponding values) are sorted in ascending
C     order on ascending proc IDs. To get Eb and phi_d, we need to go
C     backwards through these arrays. i.e., myid Np-1 to myid 0 and
C     local_sorted_array_size to 1 on each proc. 
      Eb = 0.D0
      phi_d = 0.D0
      slope = 0.218D0
      yend = -0.123609D0 + by 
      Lflat = 3.D0

      call receive_initial_local_height(cell_bottom)
      do i = local_sorted_array_size, 1, -1
c        call calculate_xl(xl,cell_bottom)
c        area = bz*xl
c        cell_height = volume_sorted(i)/area
c        z_star = cell_bottom + cell_height/2
c        call calculate_cell_height(cell_height,z_star,cell_bottom,
c    <                              volume_sorted(i)/bz)
         cell_area = volume_sorted(i)/bz
         if (cell_bottom .lt. yend) then
            xlb = Lflat + cell_bottom/slope
            cell_height = slope*(-xlb + 
     <                                sqrt(xlb**2 + 2*cell_area/slope))
            xlt = xlb + cell_height/slope
            z_star = cell_bottom + (cell_height/3)*(xlb+2*xlt)/(xlb+xlt)
         else 
            cell_height = cell_area/bx
            z_star = cell_bottom + cell_height/2
         endif

         Eb = Eb + rho_sorted(i)*volume_sorted(i)*z_star
         phi_d = phi_d + z_star*lp_sorted(i)*volume_sorted(i)
         cell_bottom = cell_bottom + cell_height
c        write(*,*) volume_sorted(i)/bz
      enddo
      call send_final_local_height(cell_bottom)

c     write(*,*) cell_bottom
      
      Eb = g*Eb
      call global_sum(Eb)
      phi_d = g*phi_d
      call global_sum(phi_d)
      
C.....Print to screen and write to binary file
      if (MYID .EQ. 0) then
         write(*,*) 'Ep = ', Ep, ' Eb = ', Eb
         write(ID, fmt='(I4)') 2000+myid
         if (istep.gt.1) then
           open(2000+myid, file='output_energy.'//ID,form='unformatted',
     <          status='old',position='append')
         else
           open(2000+myid, file='output_energy.'//ID,form='unformatted',
     <          status='unknown')
         endif
         write(2000+myid) Ep, Eb, phi_d
         close(unit = 2000+myid)
      endif

      return
      end

ccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc

      subroutine global_sum(a)

      include "mpif.h"
      include "mpi.inc"

      double precision a, total

      call MPI_REDUCE( a, total, 1, MPI_DOUBLE_PRECISION, MPI_SUM, 0, 
     <                 MPI_COMM_WORLD, ierr )
      call MPI_BCAST( total, 1, MPI_DOUBLE_PRECISION, 0,
     <                 MPI_COMM_WORLD, ierr )
      a = total

      return
      end
     
ccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc

      subroutine receive_initial_local_height(hh)
      
      include "size.inc"
      include "mpif.h"
      include "mpi.inc"

      integer status(MPI_STATUS_SIZE)
      double precision hh

      if (MYID .EQ. px*py*pz-1) then
         hh = 0.D0
      else
         call MPI_RECV( hh,1,MPI_DOUBLE_PRECISION,myid+1,0,
     <                  MPI_COMM_WORLD,status,ierr )
      endif

      return
      end

cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc

      subroutine send_final_local_height(hh)
      
      include "mpif.h"
      include "mpi.inc"

      double precision hh

      if (MYID .GT. 0) then
         call MPI_SEND( hh,1,MPI_DOUBLE_PRECISION,myid-1,0,
     <                  MPI_COMM_WORLD,ierr )
      endif

      return
      end

cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc

      subroutine calculate_xl(xl,cell_bottom)
      
      include "cavity.inc"

      double precision cell_height, z_star, cell_bottom, cell_volume
      double precision slope, xcend, ycend, yend, xl, xln
      double precision Lflat, radius

      slope = 0.218D0
      ycend = -0.491158D0 + by
      yend = -0.123609D0 + by 
      Lflat = 2.675D0
      xcend = Lflat + 0.638992D0
      radius = 3.D0
      if (cell_bottom .gt. ycend .and. cell_bottom .lt. yend) then
         xl = xcend + (cell_bottom - ycend)/slope 
      elseif (cell_bottom .ge. yend) then
         xl = bx
      else
         xl = Lflat + (radius**2-(cell_bottom-radius)**2)**0.5D0
      endif

      return
      end

cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc

      subroutine calculate_cell_height(cell_height,z_star,cell_bottom
     <                                 cell_area)
      
      include "cavity.inc"

      double precision cell_height, z_star, cell_bottom, cell_area
      double precision slope, yend, Lflat, xlb, xlt 

      slope = 0.218D0
      yend = -0.123609D0 + by 
      Lflat = 3.D0
      if (cell_bottom .lt. yend) then
         xlb = Lflat + cell_bottom/slope
         cell_height = slope*(-xlb + sqrt(xlb**2 + 2*cell_area/slope))
         write(*,*) cell_height
         xlt = xlb + cell_height/slope
         z_star = cell_bottom + (cell_height/3)*(xlb+2*xlt)/(xlb+xlt)
      else 
         cell_height = cell_area/bx
         z_star = cell_bottom + cell_height/2
      endif

      return
      end
