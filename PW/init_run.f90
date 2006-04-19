!
! Copyright (C) 2001-2006 Quantum-ESPRESSO group
! This file is distributed under the terms of the
! GNU General Public License. See the file `License'
! in the root directory of the present distribution,
! or http://www.gnu.org/copyleft/gpl.txt .
!
!----------------------------------------------------------------------------
SUBROUTINE init_run()
  !----------------------------------------------------------------------------
  !
  USE ions_base,       ONLY : nat, tau, ityp
  USE klist,           ONLY : nkstot
  USE force_mod,       ONLY : force
  USE wvfct,           ONLY : gamma_only, nbnd, et, wg
  USE control_flags,   ONLY : lmd
  USE dynamics_module, ONLY : allocate_dyn_vars
  !
  IMPLICIT NONE
  !
  !
  CALL start_clock( 'init_run' )
  !
  CALL setup()
  !
  ! ... allocate memory for G- and R-space fft arrays
  !
  CALL allocate_fft()
  !
  ! ... generate reciprocal-lattice vectors and fft indices
  !
  CALL ggen()
  !
  CALL summary()
  !
  ! ... allocate memory for all other arrays (potentials, wavefunctions etc)
  !
  CALL allocate_nlpot()
  CALL allocate_locpot()
  CALL allocate_wfc()
  !
  ALLOCATE( et( nbnd, nkstot ) , wg( nbnd, nkstot ) )
  !
  et(:,:) = 0.D0
  wg(:,:) = 0.D0
  !
  CALL openfil()
  !
  CALL hinit0()
  CALL potinit()
  !
  CALL newd()
  !
  CALL wfcinit()
  !
  IF ( lmd ) CALL allocate_dyn_vars()
  !
  CALL stop_clock ( 'init_run' )
  !
  RETURN
  !
END SUBROUTINE init_run
