!
! Copyright (C) 2001-2003 PWSCF group
! This file is distributed under the terms of the
! GNU General Public License. See the file `License'
! in the root directory of the present distribution,
! or http://www.gnu.org/copyleft/gpl.txt .
!
!
!--------------------------------------------------------------------------
SUBROUTINE make_pointlists
  !--------------------------------------------------------------------------
  !
  ! This initialization is needed in order to integrate charge (or
  ! magnetic moment) in a sphere around the atomic positions.
  ! This can be used to simply monitor these quantities during the scf
  ! cycles or in order to calculate constrains on these quantities.
  !
  ! In the integration radius r_m is calculated here. The integration 
  ! is a sum over all points in real
  ! space with the weight 1, if they are closer than r_m to an atom
  ! and 1 - (distance-r_m)/(0.2*r_m) if r_m<distance<1.2*r_m            
  !

  USE kinds,      ONLY : dp
  USE io_global,  ONLY : stdout
  USE ions_base,  ONLY : nat, tau, ntyp => nsp, ityp
  USE cell_base,  ONLY : at, bg
  USE mp_global,  ONLY : me_pool
  USE fft_base,   ONLY : dfftp

  USE noncollin_module, ONLY : factlist, pointlist, r_m
  !
  IMPLICIT NONE
  !
  INTEGER idx0,idx,indproc,iat,ir,iat1
  INTEGER i,j,k,i0,j0,k0,ipol,nt,nt1

  REAL(DP) :: posi(3),distance
  REAL(DP), ALLOCATABLE :: tau0(:,:), distmin(:)

  WRITE( stdout,'(5x,"Generating pointlists ...")')
  ALLOCATE(tau0(3,nat))
  ALLOCATE( distmin(ntyp) )

  ! First, the real-space position of every point ir is needed ...

  ! In the parallel case, find the index-offset to account for the planes
  ! treated by other procs

  idx0 = 0
#ifdef __PARA
  DO indproc=1,me_pool
     idx0 = idx0 + dfftp%nr1x*dfftp%nr2x*dfftp%npp(indproc)
  ENDDO

#endif
  ! Bring all the atomic positions on the first unit cell

  tau0=tau
  CALL cryst_to_cart(nat,tau0,bg,-1)
  DO iat=1,nat
     DO ipol=1,3
        tau0(ipol,iat)=tau0(ipol,iat)-NINT(tau0(ipol,iat))
     ENDDO
  ENDDO
  CALL cryst_to_cart(nat,tau0,at,1)

  ! Check the minimum distance between two atoms in the system


  distmin(:) = 1.d0


  DO iat = 1,nat
     nt = ityp(iat)
     DO iat1 = 1,nat
        nt1 = ityp(iat1)

        ! posi is the position of a second atom
        DO i = -1,1
           DO j = -1,1
              DO k = -1,1

                 distance = 0.d0
                 DO ipol = 1,3
                    posi(ipol) = tau0(ipol,iat1) + DBLE(i)*at(ipol,1) &
                                                 + DBLE(j)*at(ipol,2) &
                                                 + DBLE(k)*at(ipol,3)
                    distance = distance + (posi(ipol)-tau0(ipol,iat))**2
                 ENDDO

                 distance = SQRT(distance)
                 IF ((distance.LT.distmin(nt)).AND.(distance.GT.1.d-8)) &
                      &                    distmin(nt) = distance
                 IF ((distance.LT.distmin(nt1)).AND.(distance.GT.1.d-8)) &
                      &                    distmin(nt1) = distance

              ENDDO ! k
           ENDDO ! j
        ENDDO ! i

     ENDDO                  ! iat1
  ENDDO                     ! iat

  DO nt = 1, ntyp
     IF ((distmin(nt).LT.(2.d0*r_m(nt)*1.2d0)).OR.(r_m(nt).LT.1.d-8)) THEN
     ! Set the radius r_m to a value a little smaller than the minimum
     ! distance divided by 2*1.2 (so no point in space can belong to more
     ! than one atom)
        r_m(nt) = 0.5d0*distmin(nt)/1.2d0 * 0.99d0
        WRITE( stdout,'(5x,"new r_m : ",f8.4," for type",i5)') r_m(nt), nt
     ENDIF
  ENDDO

  ! Now, set for every point in the fft grid an index corresponding
  ! to the atom whose integration sphere the grid point belong to.
  ! if the point is outside of all spherical regions set the index to 0.
  ! Set as well the integration weight
  ! This also works in the parallel case.

  pointlist(:) = 0
  factlist(:) = 0.d0

  DO iat = 1,nat
     nt=ityp(iat)
     DO ir=1,dfftp%nnr
        idx = idx0 + ir - 1

        k0  = idx/(dfftp%nr1x*dfftp%nr2x)
        idx = idx - (dfftp%nr1x*dfftp%nr2x) * k0
        j0  = idx / dfftp%nr1x
        idx = idx - dfftp%nr1x*j0
        i0  = idx

        DO i = i0-dfftp%nr1,i0+dfftp%nr1, dfftp%nr1
           DO j = j0-dfftp%nr2, j0+dfftp%nr2, dfftp%nr2
              DO k = k0-dfftp%nr3, k0+dfftp%nr3, dfftp%nr3

                 DO ipol=1,3
                    posi(ipol) =  DBLE(i)/DBLE(dfftp%nr1) * at(ipol,1) &
                                + DBLE(j)/DBLE(dfftp%nr2) * at(ipol,2) &
                                + DBLE(k)/DBLE(dfftp%nr3) * at(ipol,3)

                    posi(ipol) = posi(ipol) - tau0(ipol,iat)
                 ENDDO

                 distance = SQRT(posi(1)**2+posi(2)**2+posi(3)**2)

                 IF (distance.LE.r_m(nt)) THEN
                    factlist(ir) = 1.d0
                    pointlist(ir) = iat
                 ELSE IF (distance.LE.1.2*r_m(nt)) THEN
                    factlist(ir) = 1.d0 - (distance -r_m(nt))/(0.2d0*r_m(nt))
                    pointlist(ir) = iat
                 ENDIF

              ENDDO         ! k
           ENDDO            ! j
        ENDDO               ! i

     ENDDO                  ! ir

  ENDDO                     ! ipol
  DEALLOCATE(tau0)
  DEALLOCATE(distmin)
 
END SUBROUTINE make_pointlists

