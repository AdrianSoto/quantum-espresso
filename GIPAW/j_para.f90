! Copyright (C) 2001-2005 Quantum ESPRESSO group
! This file is distributed under the terms of the
! GNU General Public License. See the file `License'
! in the root directory of the present distribution,
! or http://www.gnu.org/copyleft/gpl.txt .
!
!-----------------------------------------------------------------------
SUBROUTINE j_para(fact, psi_n, psi_m, ik, q, j)
  !-----------------------------------------------------------------------
  !
  ! ... Compute the paramgnetic current between two states:
  ! ... j_para(r') = (1/2) fact <psi_n| { p_k|r'><r'| + |r'><r'|p_{k+q} } |psi_m>
  ! ... the result is added to j and is returned in real space
  !
  USE kinds,                ONLY : DP
  USE klist,                ONLY : xk
  USE wvfct,                ONLY : nbnd, npwx, npw, igk, wg
  USE pwcom,                ONLY : g, tpiba, nls
  USE fft_base,             ONLY : dffts
  USE fft_interfaces,       ONLY : invfft
  USE gipaw_module,         ONLY : nbnd_occ

  !-- parameters ---------------------------------------------------------
  IMPLICIT none
  INTEGER, INTENT(IN) :: ik               ! k-point
  REAL(DP), INTENT(IN) :: fact            ! multiplication factor
  REAL(DP), INTENT(IN) :: q(3)
  COMPLEX(DP), INTENT(IN) :: psi_n(npwx,nbnd), psi_m(npwx,nbnd)
  REAL(DP), INTENT(INOUT) :: j(dffts%nnr,3)

  !-- local variables ----------------------------------------------------
  COMPLEX(DP), allocatable :: p_psic(:), psic(:), aux(:)
  REAL(DP) :: gk
  INTEGER :: ig, ipol, ibnd

  call start_clock('j_para')

  ! allocate real space wavefunctions
  allocate(p_psic(dffts%nnr), psic(dffts%nnr), aux(npwx))

  ! loop over cartesian components
  do ipol = 1, 3

    ! loop over bands
    do ibnd = 1, nbnd_occ(ik)

      ! apply p_k on the left
      do ig = 1, npw
        gk = xk(ipol,ik) + g(ipol,igk(ig))
        aux(ig) = gk * tpiba * psi_n(ig,ibnd)
      enddo

      ! transform to real space
      p_psic(:) = (0.d0,0.d0)
      p_psic(nls(igk(1:npw))) = aux(1:npw)
      CALL invfft ('Wave', p_psic, dffts)

      psic(:) = (0.d0,0.d0)
      psic(nls(igk(1:npw))) = psi_m(1:npw,ibnd)
      CALL invfft ('Wave', psic, dffts)

      ! add to the current
      j(1:dffts%nnr,ipol) = j(1:dffts%nnr,ipol) + 0.5d0 * fact * wg(ibnd,ik) * &
                        aimag(conjg(p_psic(1:dffts%nnr)) * psic(1:dffts%nnr))

      ! apply p_{k+q} on the right
      do ig = 1, npw
        gk = xk(ipol,ik) + g(ipol,igk(ig)) + q(ipol)
        aux(ig) = gk * tpiba * psi_m(ig,ibnd)
      enddo

      ! transform to real space
      p_psic(:) = (0.d0,0.d0)
      p_psic(nls(igk(1:npw))) = aux(1:npw)
      CALL invfft ('Wave', p_psic, dffts)

      psic(:) = (0.d0,0.d0)
      psic(nls(igk(1:npw))) = psi_n(1:npw,ibnd)
      CALL invfft ('Wave', psic, dffts)

      ! add to the current
      j(1:dffts%nnr,ipol) = j(1:dffts%nnr,ipol) + 0.5d0 * fact * wg(ibnd,ik) * &
                        aimag(conjg(psic(1:dffts%nnr)) * p_psic(1:dffts%nnr))

    enddo ! ibnd
  enddo ! ipol

  ! free memory
  deallocate(p_psic, psic, aux)

  call stop_clock('j_para')

END SUBROUTINE j_para


