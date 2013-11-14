MODULE modpk_odeint
  use modpkparams, only : dp
  use camb_interface, only : pk_bad
  use modpk_icsampling, only : sampling_techn, reg_samp, bad_ic
  IMPLICIT NONE

  INTERFACE odeint
     module procedure odeint_r
     module procedure odeint_c
  END INTERFACE

  PUBLIC odeint

CONTAINS

  SUBROUTINE odeint_r(ystart,x1,x2,eps,h1,hmin,derivs,rkqs_r)
    USE ode_path
    USE internals
    USE powersp
    USE modpkparams
    USE potential
    USE modpk_utils, ONLY : reallocate_rv, reallocate_rm

    IMPLICIT NONE
    real(dp), DIMENSION(:), INTENT(INOUT) :: ystart
    real(dp), INTENT(IN) :: x1,x2,eps,h1,hmin
    !MULTIFIELD
    real(dp), DIMENSION(num_inflaton) :: p, delp
    !END MULTIFIELD

    INTERFACE
       SUBROUTINE derivs(x,y,dydx)
         use modpkparams
         IMPLICIT NONE
         real(dp), INTENT(IN) :: x
         real(dp), DIMENSION(:), INTENT(IN) :: y
         real(dp), DIMENSION(:), INTENT(OUT) :: dydx
       END SUBROUTINE derivs

       SUBROUTINE rkqs_r(y,dydx,x,htry,eps,yscal,hdid,hnext,derivs)
         use modpkparams
         IMPLICIT NONE
         real(dp), DIMENSION(:), INTENT(INOUT) :: y
         real(dp), DIMENSION(:), INTENT(IN) :: dydx,yscal
         real(dp), INTENT(INOUT) :: x
         real(dp), INTENT(IN) :: htry,eps
         real(dp), INTENT(OUT) :: hdid,hnext
         INTERFACE
            SUBROUTINE derivs(x,y,dydx)
              use modpkparams
              IMPLICIT NONE
              real(dp), INTENT(IN) :: x
              real(dp), DIMENSION(:), INTENT(IN) :: y
              real(dp), DIMENSION(:), INTENT(OUT) :: dydx
            END SUBROUTINE derivs
         END INTERFACE
       END SUBROUTINE rkqs_r
    END INTERFACE

    real(dp), PARAMETER :: TINY=1.0d-30
    INTEGER, PARAMETER :: MAXSTP=nsteps
    INTEGER*4 :: nstp,i
    real(dp) :: h,hdid,hnext,x,xsav
    real(dp), DIMENSION(SIZE(ystart)) :: dydx, y, yscal
    real(dp) :: z, scalefac

    real(dp) :: infl_efolds, infl_efolds_start
    logical :: infl_checking


    !Inits for checking whether in
    !extended inflation period (for IC scan)
    infl_checking = .false.
    infl_efolds_start = 0e0_dp

    ode_underflow=.FALSE.
    infl_ended=.FALSE.
    x=x1
    h=SIGN(h1,x2-x1)
    nok=0
    nbad=0
    kount=0
    y(:)=ystart(:)
    NULLIFY(xp,yp)
    IF (save_steps) THEN
       xsav=x-2.d0*dxsav
       ALLOCATE(xp(256))
       ALLOCATE(yp(SIZE(ystart),SIZE(xp)))
    END IF

    DO nstp=1,MAXSTP


       if (any(isnan(y))) then
         print*, "ERROR in odeint_r"
         print*, "ERROR: y has a NaN value."
         print*, "E-fold",x
         print*, "nstp",nstp
         print*, "y", y
         stop
       end if

       !Calc bundle exp_scalar by integrating tr(d2Vdphi2)
       if (nstp==1) then
         !Initialize
         field_bundle%N=0e0_dp
         field_bundle%dlogThetadN=0e0_dp
         field_bundle%exp_scalar=1e0_dp
       end if
       call field_bundle%calc_exp_scalar(y(1:num_inflaton),x)

       !Uncomment to write the trajectories...
       !write(1,'(12E18.10)') x, y(:)
       !record trajectory
       !print*, "writing trajectory"
       !write(1,'(12E18.10)') x, y(1:num_inflaton)
       !write(1,'(12E18.10)') x, y(1:2*num_inflaton), getEps(y(1:num_inflaton),y(num_inflaton+1:2*num_inflaton))

       CALL derivs(x,y,dydx)

       !If get bad deriv, then override this error when IC sampling
       if (pk_bad==bad_ic) then
         return
       end if

       yscal(:)=ABS(y(:))+ABS(h*dydx(:))+TINY

       IF (save_steps .AND. (ABS(x-xsav) > ABS(dxsav))) &
            CALL save_a_step
       IF ((x+h-x2)*(x+h-x1) > 0.0) h = x2 - x

       CALL rkqs_r(y,dydx,x,h,eps,yscal,hdid,hnext,derivs)

       IF (hdid == h) THEN
          nok=nok+1
       ELSE
          nbad=nbad+1
       END IF

       IF ((x-x2)*(x2-x1) > 0.0d0) THEN

          PRINT*,'MODPK: This could be a model for which inflation does not end.'
          PRINT*,'MODPK: Either adjust phi_init or use slowroll_infl_end for a potential'
          PRINT*,'MODPK: for which inflation does not end by breakdown of slowroll.'
          PRINT*,'MODPK: QUITTING'
          WRITE(*,*) 'vparams: ', (vparams(i,:),i=1,size(vparams,1))
          IF (.NOT.instreheat) WRITE(*,*) 'N_pivot: ', N_pivot
          STOP
          RETURN
       END IF

       !MULTIFIELD
       p = y(1:num_inflaton)
       delp = y(num_inflaton+1 : 2*num_inflaton)

       IF(getEps(p,delp) .LT. 1 .AND. .NOT.(slowroll_start)) then
         if (sampling_techn==reg_samp) then
           slowroll_start=.true.
         else
           !If scan ICs, say inflating iff eps<1 for "extended" period,
           !3 efolds - protects against transient inflation epochs, i.e.,
           !at traj turn-around or chance starting with dphi=0

           if (.not. infl_checking) then
             infl_checking = .true.
             infl_efolds_start = x
           else

             infl_efolds = x - infl_efolds_start
             if (infl_efolds > 3.0) then
               slowroll_start=.true.
             end if

           end if
         end if
       else if (infl_checking) then
         infl_checking=.false.
       endif
       !END MULTIFIELD


       IF(ode_infl_end) THEN 
          IF (slowroll_infl_end) THEN
             IF(getEps(p, delp) .GT. 1 .AND. slowroll_start) THEN 
                infl_ended = .TRUE.
                ystart(:) = y(:)
                IF (save_steps) CALL save_a_step
                RETURN
             ENDIF
          ELSE
             IF(getEps(p, delp) .GT. 1 .AND. slowroll_start) THEN
                PRINT*,'MODPK: You asked for a no-slowroll-breakdown model, but inflation'
                PRINT*,'MODPK: already ended via slowroll violation before your phi_end was'
                PRINT*,'MODPK: reached. Please take another look at your inputs.'
                PRINT*,'MODPK: QUITTING'
                PRINT*,'EPSILON =', getEps(p, delp)
                STOP
             ENDIF

             !MULTIFIELD
             IF (size(p) .eq. 1) THEN
                IF (phidot_sign(1).GT.0..AND.(p(1).GT.(phi_infl_end(1)+0.1))) THEN
                   infl_ended=.TRUE.
                   ystart(:)=y(:)
                   IF (save_steps) CALL save_a_step
                   RETURN
                ENDIF
                IF (phidot_sign(1).LT.0..AND.(p(1).LT.(phi_infl_end(1)-0.1))) THEN
                   infl_ended=.TRUE.
                   ystart(:)=y(:)
                   IF (save_steps) CALL save_a_step
                   RETURN
                ENDIF
             ELSE ! for multifield, determine the total field distance travelled
                IF (sqrt(dot_product(p-phi_init, p-phi_init)) .gt. (delsigma+0.1)) THEN
                   infl_ended = .true.
                   ystart(:) = y(:)
                   IF (save_steps) CALL save_a_step
                   RETURN
                END IF
             END IF
             !END MULTIFIELD
          ENDIF
       ENDIF

       IF (ode_underflow) RETURN
       IF (ABS(hnext) < hmin) THEN
          write(*,*) 'stepsize smaller than minimum in odeint'
          STOP
       END IF
       h=hnext
    END DO
    PRINT*,'too many steps in odeint_r', nstp
    PRINT*,"E-fold", x, "Step size", h
    ode_underflow=.TRUE.

  CONTAINS

    SUBROUTINE save_a_step
      kount=kount+1
      IF (kount > SIZE(xp)) THEN
         xp=>reallocate_rv(xp,2*SIZE(xp))
         yp=>reallocate_rm(yp,SIZE(yp,1), SIZE(xp))  
      END IF
      xp(kount)=x
      yp(:,kount)=y(:)
      xsav=x
    END SUBROUTINE save_a_step
    !  (C) Copr. 1986-92 Numerical Recipes Software, adapted.
  END SUBROUTINE odeint_r

  ! Only called for ptb mode eqns
  SUBROUTINE odeint_c(ystart, x1, x2, eps, h1, hmin, derivs, qderivs, rkqs_c)
    USE ode_path
    USE internals
    USE powersp
    USE modpkparams
    USE potential, only : tensorpower, getH, getEps, zpower,&
      powerspectrum
    USE modpk_utils, only : reallocate_rv, reallocate_rm

    IMPLICIT NONE
    COMPLEX(KIND=DP), DIMENSION(:), INTENT(INOUT) :: ystart
    real(dp), INTENT(IN) :: x1,x2,eps,h1,hmin
    real(dp) :: eps_adjust

    real(dp), DIMENSION(num_inflaton) :: phi, delphi  ! the classical field phi and dphi are real
    COMPLEX(KIND=DP), DIMENSION(size(ystart)) :: ytmp
    LOGICAL :: use_q, compute_zpower

    INTERFACE
       SUBROUTINE derivs(x, y, dydx)
         USE modpkparams
         IMPLICIT NONE
         real(dp), INTENT(IN) :: x
         COMPLEX(KIND=DP), DIMENSION(:), INTENT(IN) :: y
         COMPLEX(KIND=DP), DIMENSION(:), INTENT(OUT) :: dydx
       END SUBROUTINE derivs

       SUBROUTINE qderivs(x, y, dydx)
         USE modpkparams
         IMPLICIT NONE
         real(dp), INTENT(IN) :: x
         COMPLEX(KIND=DP), DIMENSION(:), INTENT(IN) :: y
         COMPLEX(KIND=DP), DIMENSION(:), INTENT(OUT) :: dydx
       END SUBROUTINE qderivs

       SUBROUTINE rkqs_c(y,dydx,x,htry,eps,yscal,hdid,hnext,derivs)
         USE modpkparams
         IMPLICIT NONE
         COMPLEX(KIND=DP), DIMENSION(:), INTENT(INOUT) :: y
         COMPLEX(KIND=DP), DIMENSION(:), INTENT(IN) :: dydx,yscal
         real(dp), INTENT(INOUT) :: x
         real(dp), INTENT(IN) :: htry,eps
         real(dp), INTENT(OUT) :: hdid,hnext
         INTERFACE
            SUBROUTINE derivs(x, y, dydx)
              USE modpkparams
              IMPLICIT NONE
              real(dp), INTENT(IN) :: x
              COMPLEX(KIND=DP), DIMENSION(:), INTENT(IN) :: y
              COMPLEX(KIND=DP), DIMENSION(:), INTENT(OUT) :: dydx
            END SUBROUTINE derivs
         END INTERFACE
       END SUBROUTINE rkqs_c
    END INTERFACE

    real(dp), PARAMETER :: TINY=1.0d-40
    INTEGER, PARAMETER :: MAXSTP=nsteps
    INTEGER*4 :: nstp,i
    real(dp) :: h,hdid,hnext,x,xsav
    COMPLEX(KIND=DP), DIMENSION(size(ystart)) :: dydx, y, yscal
    real(dp) :: scalefac, hubble, a_switch, dotphi

    complex(dp), dimension(num_inflaton**2) :: psi, dpsi
    complex(dp), dimension(num_inflaton**2) :: qij, dqij

    real(dp) :: nk_sum, Nprime(num_inflaton), Nprimeprime(num_inflaton,num_inflaton)
    integer :: ii, jj, kk


    ode_underflow=.FALSE.
    infl_ended=.FALSE.
    x=x1
    h=SIGN(h1,x2-x1)
    nok=0
    nbad=0
    kount=0
    y(:)=ystart(:)
    NULLIFY(xp,yp)

    IF (save_steps) THEN
       xsav=x-2.d0*dxsav
       ALLOCATE(xp(256))
       !MULTIFIELD
       ALLOCATE(yp(2*SIZE(ystart),SIZE(xp)))  !! store real and imiganary seperately
       !END MULTIFIELD
    END IF

    use_q = .false.
    compute_zpower = .true.
    eps_adjust = eps

   DO nstp=1,MAXSTP

       if (any(isnan(real(y))) .or. any(isnan(aimag(y)))) then
         print*, "ERROR in odeint_c"
         print*, "ERROR: y has a NaN value."
         print*, "E-fold",x
         print*, "nstp",nstp
         print*, "y", y
         stop
       end if

       IF (use_q) THEN
          ! super-h use Q
          CALL qderivs(x, y, dydx)
       ELSE
          ! sub-h use psi
          CALL derivs(x, y, dydx)
       END IF

       ! for yscal, evaluate real and imaginary parts separately, and then assemble them into complex format

       !"Trick" to get constant fractional errors except very near
       !zero-crossings. (Numerical Recipes)
       yscal(:)=cmplx(ABS(dble(y(:)))+ABS(h*dble(dydx(:)))+TINY, ABS(dble(y(:)*(0,-1)))+ABS(h*dble(dydx(:)*(0,-1)))+TINY)

       IF (save_steps .AND. (ABS(x-xsav) > ABS(dxsav))) &
            CALL save_a_step

       IF ((x+h-x2)*(x+h-x1) > 0.0) h=x2-x

       IF (use_q) THEN
          CALL rkqs_c(y,dydx,x,h,eps_adjust,yscal,hdid,hnext,qderivs)
       ELSE
          CALL rkqs_c(y,dydx,x,h,eps_adjust,yscal,hdid,hnext,derivs)
       END IF

       IF (hdid == h) THEN
          nok=nok+1
       ELSE
          nbad=nbad+1
       END IF

       IF ((x-x2)*(x2-x1) >= 0.0) THEN
          PRINT*,'MODPK: This could be a model for which inflation does not end.'
          PRINT*,'MODPK: Either adjust phi_init or use slowroll_infl_end for a potential'
          PRINT*,'MODPK: for which inflation does not end by breakdown of slowroll.'
          PRINT*,'MODPK: QUITTING'
          WRITE(*, *) 'vparams: ', (vparams(i,:),i=1, size(vparams,1))
          WRITE(*, *) 'x1, x, x2 :', x, x1, x2
          IF (.NOT.instreheat) WRITE(*,*) 'N_pivot: ', N_pivot
          STOP
          RETURN
       END IF

       !MULTIFIELD
       phi = DBLE(y(1:num_inflaton))
       delphi = DBLE(y(num_inflaton+1 : 2*num_inflaton))
       dotphi = sqrt(dot_product(delphi, delphi))

       !DEBUG
       !print*, "printing real part of modes"
       !print*, "printing imaginary part of modes"
       !if (.not. use_q) then
       ! write(20,'(10E30.22)') x - (n_tot - N_pivot),  real(y(index_ptb_y:index_ptb_vel_y-1))/sqrt(2*k)
       ! write(21,'(10E30.22)') x - (n_tot - N_pivot), aimag(y(index_ptb_y:index_ptb_vel_y-1))/sqrt(2*k)
       !else                                                                                   
       !  write(22,'(10E30.22)') x - (n_tot - N_pivot),  real(y(index_ptb_y:index_ptb_vel_y-1))/sqrt(2*k)
       !  write(23,'(10E30.22)') x - (n_tot - N_pivot), aimag(y(index_ptb_y:index_ptb_vel_y-1))/sqrt(2*k)
       !end if

       scalefac = a_init*exp(x)

       !Increase accuracy requirements when not in SR
       if (getEps(phi,delphi)>0.2e0_dp) then
         eps_adjust=1e-12_dp
         if (getEps(phi,delphi)>0.9e0_dp) then
           eps_adjust=1e-17_dp
         end if
       else
         eps_adjust = eps
       end if
       !END MULTIFIELD

       IF(getEps(phi,delphi) .LT. 1 .AND. .NOT.(slowroll_start)) slowroll_start=.true.

       IF(ode_ps_output) THEN

          IF(k .LT. a_init*EXP(x)*getH(phi, delphi)/eval_ps) THEN ! if k<aH/eval_ps, then k<<aH

             !MULTIFIELD
             IF (use_q) THEN

               !Y's are in \bar{Q}=Q/a_switch
               !psi = y(index_ptb_y:index_ptb_vel_y-1) &
               !     *scalefac/a_switch
               !dpsi = scalefac/a_switch*&
               !  (y(index_ptb_vel_y:index_tensor_y-1) + &
               !  y(index_ptb_y:index_ptb_vel_y-1))

               ! with isocurv calculation
               !call powerspectrum(psi, dpsi, phi, delphi, &
               !  scalefac, power_internal)

               !Y's are in \bar{Q}=Q/a_switch
               qij = y(index_ptb_y:index_ptb_vel_y-1)/a_switch
               dqij = y(index_ptb_vel_y:index_tensor_y-1)/a_switch

               ! with isocurv calculation
               call powerspectrum(qij, dqij, phi, delphi, &
                 scalefac, power_internal, using_q=.true.)

              !Record spectrum
              !print*, "writing spectra"
              !write(2,'(5E27.20)') x - (n_tot - N_pivot), power_internal%adiab, power_internal%isocurv,&
              !  power_internal%entropy, power_internal%pnad

               power_internal%tensor=tensorpower(y(index_tensor_y) &
                  *scalefac/a_switch, scalefac)
             ELSE

               psi = y(index_ptb_y:index_ptb_vel_y-1)
               dpsi = y(index_ptb_vel_y:index_tensor_y-1)

               call powerspectrum(psi, dpsi, phi, delphi, &
                 scalefac, power_internal)

              !Record spectrum
              !print*, "writing spectra"
              !write(2,'(5E27.20)') x - (n_tot - N_pivot), power_internal%adiab, power_internal%isocurv,&
              !  power_internal%entropy, power_internal%pnad


               power_internal%tensor=tensorpower(y(index_tensor_y), scalefac)
             END IF


             if (compute_zpower) then  !! compute only once upon horizon exit
                power_internal%powz = zpower(y(index_uzeta_y), dotphi, scalefac)
                compute_zpower = .false.
             end if

             ! for single field, end mode evolution when the mode is frozen out of the horizon
             ! for multifield, need to evolve the modes until the end of inflation to include superhorizon evolution
             IF (num_inflaton .EQ. 1) infl_ended = .TRUE.  
             !END MULTIFIELD
          END IF
       END IF

       IF(ode_infl_end) THEN 
          IF (slowroll_infl_end) THEN
             IF(getEps(phi, delphi) .GT. 1 .AND. slowroll_start) infl_ended=.TRUE.
          ELSE
             IF(getEps(phi, delphi) .GT. 1 .AND. slowroll_start) THEN
                PRINT*,'MODPK: You asked for a no-slowroll-breakdown model, but inflation'
                PRINT*,'MODPK: already ended via slowroll violation before your phi_end was'
                PRINT*,'MODPK: reached. Please take another look at your inputs.'
                PRINT*,'MODPK: QUITTING'
                PRINT*,'EPSILON =', getEps(phi, delphi), 'phi =', phi
                STOP
             ENDIF

             !MULTIFIELD
             IF (SIZE(phi) .EQ. 1) THEN
                IF (phidot_sign(1).GT.0..AND.(phi(1).GT.(phi_infl_end(1)+0.1))) infl_ended=.TRUE.
                IF (phidot_sign(1).LT.0..AND.(phi(1).LT.(phi_infl_end(1)-0.1))) infl_ended=.TRUE.
             ELSE 
                ! for multifield, determine the total field distance travelled
                IF (SQRT(DOT_PRODUCT(phi-phi_init, phi-phi_init)) .GT. (delsigma+0.1)) infl_ended = .TRUE.
             END IF
             !END MULTIFIELD
          ENDIF

          IF (infl_ended) THEN
             IF (use_q) THEN
                ytmp(:) = y(:)
                ! bckgrd
                ystart(1:2*num_inflaton) = y(1:2*num_inflaton)

                ! ptbs
                ystart(index_ptb_y:index_ptb_vel_y-1) = &
                  ytmp(index_ptb_y:index_ptb_vel_y-1)*scalefac/a_switch
                ystart(index_ptb_vel_y:index_tensor_y-1) = &
                  ytmp(index_ptb_vel_y:index_tensor_y-1)&
                  *scalefac/a_switch + ystart(index_ptb_y:index_ptb_vel_y-1)

                ! tensors
                ystart(index_tensor_y) =&
                  ytmp(index_tensor_y)*scalefac/a_switch
                ystart(index_tensor_y+1) =&
                  ytmp(index_tensor_y+1)*scalefac/a_switch&
                  + ystart(index_tensor_y)
             ELSE
                ystart(:) = y(:)
             END IF
             IF (save_steps) CALL save_a_step
             RETURN
          END IF
       ENDIF

       !DEBUG
       !print*, "not switching to the q variable...."
       IF (k .LT. a_init*exp(x)*getH(phi, delphi)/useq_ps .and. (.not. use_q)) THEN
          !switch to the Q variable for super-horizon evolution
          !only apply the switch on y(1:4*num_inflaton+2)
          use_q = .TRUE.
          a_switch = scalefac
          !set intial condition in (Q*a_switch)
          ytmp(:) = y(:)

          y(index_ptb_y:index_ptb_vel_y-1) = ytmp(index_ptb_y:index_ptb_vel_y-1)
          y(index_ptb_vel_y:index_tensor_y-1) = &
            ytmp(index_ptb_vel_y:index_tensor_y-1) & 
            - y(index_ptb_y:index_ptb_vel_y-1)

          y(index_tensor_y) = ytmp(index_tensor_y)
          y(index_tensor_y+1) = ytmp(index_tensor_y+1) &
            - y(index_tensor_y)
       END IF

       IF (ode_underflow) RETURN
       IF (ABS(hnext) < hmin) THEN
          WRITE(*,*) 'stepsize smaller than minimum in odeint'
          STOP
       END IF
       h=hnext
    END DO
    PRINT*,'too many steps in odeint_c', x
    PRINT*,'x =', x, 'h =', h 
    ode_underflow=.TRUE.


  CONTAINS

    SUBROUTINE save_a_step
      USE modpkparams
      IMPLICIT NONE

      COMPLEX(KIND=DP), DIMENSION(size(ystart)) :: ytmp
      COMPLEX(KIND=DP), DIMENSION(num_inflaton**2) :: ptb_tmp, dptb_tmp

      kount=kount+1
      IF (kount > SIZE(xp)) THEN
         xp=>reallocate_rv(xp,2*SIZE(xp))
         yp=>reallocate_rm(yp,SIZE(yp,1), SIZE(xp))  
      END IF
      xp(kount) = x

      IF (use_q) THEN  ! convert from (a_switch*Q) to v
         ytmp(:) = y(:)
         ptb_tmp =ytmp(index_ptb_y:index_ptb_vel_y-1)
         dptb_tmp =ytmp(index_ptb_vel_y:index_tensor_y-1)

         ytmp(index_ptb_y:index_ptb_vel_y-1) = ptb_tmp*scalefac/a_switch
         ytmp(index_ptb_vel_y:index_tensor_y-1) = dptb_tmp*scalefac/a_switch + ptb_tmp

         ytmp(index_tensor_y) = &
           ytmp(index_tensor_y)*scalefac/a_switch
         ytmp(index_tensor_y+1) = &
           ytmp(index_tensor_y+1)*scalefac/a_switch + ytmp(index_tensor_y)
      END IF

      yp(1:size(yp,1)/2,kount) = dble(ytmp(:))
      yp(size(yp,1)/2+1:size(yp,1),kount) = dble(ytmp(:)*(0,-1))
      xsav=x

    END SUBROUTINE save_a_step
    !  (C) Copr. 1986-92 Numerical Recipes Software, adapted.

  END SUBROUTINE odeint_c

END MODULE modpk_odeint

