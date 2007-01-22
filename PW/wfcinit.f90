!
! Copyright (C) 2001-2006 Quantum-ESPRESSO group
! This file is distributed under the terms of the
! GNU General Public License. See the file `License'
! in the root directory of the present distribution,
! or http://www.gnu.org/copyleft/gpl.txt .
!
#include "f_defs.h"
! 
!----------------------------------------------------------------------------
SUBROUTINE wfcinit()
  !----------------------------------------------------------------------------
  !
  ! ... This routine computes an estimate of the starting wavefunctions
  ! ... from superposition of atomic wavefunctions.
  !
  USE io_global,            ONLY : stdout
  USE basis,                ONLY : natomwfc, startingwfc
  USE klist,                ONLY : nks
  USE control_flags,        ONLY : reduce_io, lscf
  USE ldaU,                 ONLY : lda_plus_u
  USE io_files,             ONLY : nwordwfc, iunwfc, iunigk
  USE wavefunctions_module, ONLY : evc
  USE wvfct,                ONLY : nbnd
  !
  IMPLICIT NONE
  !
  INTEGER :: ik
  !
  !
  CALL start_clock( 'wfcinit' )
  !
  ! ... Needed for LDA+U
  !
  IF ( lda_plus_u ) CALL orthoatwfc()
  !
  ! ... state what is going to happen
  !
  IF ( startingwfc == 'file' ) THEN
     !
     WRITE( stdout, '(5X,"Starting wfc from file")' )
     !
     ! ... read the wavefunction into memory (if it is not done in c_bands)
     !
     IF ( nks == 1 .AND. reduce_io ) &
        CALL davcio( evc, nwordwfc, iunwfc, 1, -1 )
     !
     RETURN
     !
  ELSE IF ( startingwfc == 'atomic' ) THEN
     !
     IF ( natomwfc >= nbnd ) THEN
        !
        WRITE( stdout, '(5X,"Starting wfc are atomic")' ) 
        !
     ELSE
        !
        WRITE( stdout, '(5X,"Starting wfc are atomic + ",I3," random wfc")' ) &
              nbnd-natomwfc
        !
     END IF
     !
  ELSE
     !
     WRITE( stdout, '(5X,"Starting wfc are random")' )
     !
  END IF
  !
  !!! ... TODO: for non-scf calculations, the starting wavefunctions are
  !!! ... not written to file but calculated just before diagonalization
  !
  !!! IF ( .NOT. lscf ) RETURN
  !
  IF ( nks > 1 ) REWIND( iunigk )
  !
  ! ... calculate and write all starting wavefunctions to file
  !
  DO ik = 1, nks
     !
     CALL init_wfc ( ik )
     !
     IF ( nks > 1 .OR. .NOT. reduce_io ) &
         CALL davcio( evc, nwordwfc, iunwfc, ik, 1 )
     !
  END DO
  !
  CALL stop_clock( 'wfcinit' )  
  !
  RETURN
  !
END SUBROUTINE wfcinit
! 
!----------------------------------------------------------------------------
SUBROUTINE init_wfc ( ik )
  !----------------------------------------------------------------------------
  !
  ! ... This routine computes an estimate of the starting wavefunctions
  ! ... from superposition of atomic wavefunctions.
  !
  USE kinds,                ONLY : DP
  USE wvfct,                ONLY : gamma_only
  USE constants,            ONLY : tpi
  USE cell_base,            ONLY : tpiba2
  USE basis,                ONLY : natomwfc, startingwfc
  USE gvect,                ONLY : g, ecfixed, qcutz, q2sigma
  USE klist,                ONLY : xk, nks, ngk
  USE lsda_mod,             ONLY : lsda, current_spin, isk
  USE wvfct,                ONLY : nbnd, npw, npwx, igk, g2kin, et,&
                                   wg, current_k
  USE uspp,                 ONLY : nkb, vkb
  USE ldaU,                 ONLY : swfcatom, lda_plus_u
  USE noncollin_module,     ONLY : noncolin, npol
  USE io_files,             ONLY : iunsat, nwordwfc, iunwfc, iunigk, nwordatwfc
  USE wavefunctions_module, ONLY : evc
  USE random_numbers,       ONLY : rndm
  !
  IMPLICIT NONE
  !
  INTEGER :: ik
  !
  INTEGER :: is, ibnd, ig, ipol, ig2, n_starting_wfc, n_starting_atomic_wfc
  !
  REAL(DP) :: rr, arg
  !
  COMPLEX(DP), ALLOCATABLE :: wfcatom(:,:) ! atomic wfcs for initialization
  !
  !
  IF ( startingwfc == 'atomic' ) THEN
     !
     n_starting_wfc = MAX( natomwfc, nbnd )
     n_starting_atomic_wfc = natomwfc
     !
  ELSE IF ( startingwfc == 'random' ) THEN
     !
     n_starting_wfc = nbnd
     n_starting_atomic_wfc = 0
     !
  ELSE
     !
     !!! CALL davcio( evc, nwordwfc, iunwfc, ik, -1 )
     CALL errore ( 'init_wfc', &
          'invalid value for startingwfc: ' // TRIM ( startingwfc ) , 1 )
     !
  END IF
  !
  current_k = ik
  !
  IF ( lsda ) current_spin = isk(ik)
  !
  npw = ngk (ik)
  IF ( nks > 1 ) READ( iunigk ) igk
  !
  ! ... here we compute the kinetic energy
  !
  DO ig = 1, npw
     !
     g2kin(ig) = ( ( xk(1,ik) + g(1,igk(ig)) )**2 + &
                   ( xk(2,ik) + g(2,igk(ig)) )**2 + &
                   ( xk(3,ik) + g(3,igk(ig)) )**2 ) * tpiba2
     !
  END DO
  !
  IF ( qcutz > 0.D0 ) THEN
     !
     DO ig = 1, npw
        !
        g2kin(ig) = g2kin(ig) + qcutz * &
             ( 1.D0 + erf( ( g2kin(ig) - ecfixed ) / q2sigma ) )
        !
     END DO
     !
  END IF
  !
  ALLOCATE( wfcatom( npwx*npol, n_starting_wfc ) )
  !
  wfcatom (:,:) = (0.d0, 0.d0)
  !
  IF ( startingwfc == 'atomic' ) THEN
     !
     IF ( noncolin ) THEN
        !
        CALL atomic_wfc_nc( ik, wfcatom )
        !
     ELSE
        !
        CALL atomic_wfc( ik, wfcatom )
        !
     END IF
     !
  END IF
  !
  ! ... if not enough atomic wfc are available, 
  ! ... fill missing wfcs with random numbers
  !
  DO ibnd = n_starting_atomic_wfc + 1, n_starting_wfc
     !
     DO ipol = 1, npol
        !
        DO ig = 1, npw
           !
           ig2 = ig + (ipol-1)*npwx
           rr  = rndm()
           arg = tpi * rndm()
           !
           wfcatom(ig2,ibnd) = &
                CMPLX( rr*COS( arg ), rr*SIN( arg ) ) / &
                       ( ( xk(1,ik) + g(1,igk(ig)) )**2 + &
                         ( xk(2,ik) + g(2,igk(ig)) )**2 + &
                         ( xk(3,ik) + g(3,igk(ig)) )**2 + 1.D0 )
        END DO
        !
     END DO
     !
  END DO
  !
  ! ... Calculate nonlocal pseudopotential projectors |beta>
  !
  IF ( nkb > 0 ) CALL init_us_2( npw, igk, xk(1,ik), vkb )
  !
  ! ... LDA+U: read atomic wavefunctions for U term in Hamiltonian
  !
  IF ( lda_plus_u ) &
       CALL davcio( swfcatom, nwordatwfc, iunsat, ik, - 1 )
  !
  ! ... Diagonalize the Hamiltonian on the basis of atomic wfcs
  !
  IF ( gamma_only ) THEN
     !
     CALL wfcinit_gamma()
     !
  ELSE
     !
     CALL wfcinit_k()
     !
  END IF
  !
  DEALLOCATE( wfcatom )
  !
  RETURN
  !
CONTAINS
  !
  !-----------------------------------------------------------------------
  SUBROUTINE wfcinit_gamma()
    !-----------------------------------------------------------------------
    ! 
    ! ... gamma version       
    !
    USE gvect,  ONLY : gstart
    USE becmod, ONLY : rbecp
    USE control_flags, ONLY : isolve
    USE uspp, ONLY: okvan
    !
    IMPLICIT NONE
    !       
    REAL(DP), ALLOCATABLE :: etatom(:)
    ! atomic eigenvalues
    !
    ! ... rbecp contains <beta|psi> - used in h_psi and s_psi
    !
    ALLOCATE( rbecp( nkb, n_starting_wfc ) )
    ALLOCATE( etatom( n_starting_wfc ) )
    !
    IF ( isolve == 1 ) THEN
       !
       CALL rinitcgg( npwx, npw, n_starting_wfc, &
            nbnd, wfcatom, evc, etatom )
       !
    ELSE
       !
       CALL rotate_wfc_gamma( npwx, npw, n_starting_wfc, gstart, &
            nbnd, wfcatom, okvan, evc, etatom )
    END IF
    !
    ! ... copy the first nbnd eigenvalues
    ! ... eigenvectors are already copied inside routines
    ! ... rinitcgg, rotate_wfc_gamma above
    !
    et(1:nbnd,ik) = etatom(1:nbnd)
    !
    DEALLOCATE( rbecp )
    DEALLOCATE( etatom )
    !
    RETURN
    !
  END SUBROUTINE wfcinit_gamma
  !
  !-----------------------------------------------------------------------
  SUBROUTINE wfcinit_k()
    !-----------------------------------------------------------------------
    !
    ! ... k-points version       
    !
    USE becmod, ONLY : becp, becp_nc
    USE control_flags,  ONLY : isolve
    USE uspp, ONLY: okvan
    !
    IMPLICIT NONE
    !
    REAL(DP), ALLOCATABLE :: etatom(:)
    ! atomic eigenvalues
    !
    ! ... becp contains <beta|psi> - used in h_psi and s_psi
    !
    IF ( noncolin ) THEN
       !
       ALLOCATE( becp_nc( nkb, npol, n_starting_wfc ) )
       !
    ELSE
       !
       ALLOCATE( becp( nkb, n_starting_wfc ) )
       !
    END IF
    !
    ALLOCATE( etatom( n_starting_wfc ) )
    !
    IF ( isolve == 1 ) THEN
       !
       CALL cinitcgg( npwx, npw, n_starting_wfc, &
            nbnd, wfcatom, evc, etatom, .true. )
       !
    ELSE
       !
       IF ( noncolin ) THEN
          !
          CALL rotate_wfc_nc( npwx, npw, n_starting_wfc, nbnd, &
               wfcatom, npol, okvan, evc, etatom )
          !
       ELSE
          !
          CALL rotate_wfc( npwx, npw, n_starting_wfc, &
               nbnd, wfcatom, okvan, evc, etatom )
          !
       END IF
       !
    END IF
    !
    ! ... copy the first nbnd eigenvalues are copied
    ! ... eigenvectors are already copied inside routines
    ! ... cinitcgg, rotate_wfc, rotate_wfc_nc above
    !
    et(1:nbnd,ik) = etatom(1:nbnd)
    !
    IF ( noncolin ) THEN
       !
       DEALLOCATE( becp_nc )
       !
    ELSE
       !
       DEALLOCATE( becp )
       !
    END IF
    !
    DEALLOCATE( etatom )
    !
    RETURN
    !
  END SUBROUTINE wfcinit_k
  !
END SUBROUTINE init_wfc
