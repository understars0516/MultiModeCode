MODULE modpk_odeint
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
    DOUBLE PRECISION, DIMENSION(:), INTENT(INOUT) :: ystart
    DOUBLE PRECISION, INTENT(IN) :: x1,x2,eps,h1,hmin
    !MULTIFIELD
    DOUBLE PRECISION, DIMENSION(num_inflaton) :: p, delp
    !END MULTIFIDLE

    INTERFACE
       SUBROUTINE derivs(x,y,dydx)
         IMPLICIT NONE
         DOUBLE PRECISION, INTENT(IN) :: x
         DOUBLE PRECISION, DIMENSION(:), INTENT(IN) :: y
         DOUBLE PRECISION, DIMENSION(:), INTENT(OUT) :: dydx
       END SUBROUTINE derivs

       SUBROUTINE rkqs_r(y,dydx,x,htry,eps,yscal,hdid,hnext,derivs)
         IMPLICIT NONE
         DOUBLE PRECISION, DIMENSION(:), INTENT(INOUT) :: y
         DOUBLE PRECISION, DIMENSION(:), INTENT(IN) :: dydx,yscal
         DOUBLE PRECISION, INTENT(INOUT) :: x
         DOUBLE PRECISION, INTENT(IN) :: htry,eps
         DOUBLE PRECISION, INTENT(OUT) :: hdid,hnext
         INTERFACE
            SUBROUTINE derivs(x,y,dydx)
              IMPLICIT NONE
              DOUBLE PRECISION, INTENT(IN) :: x
              DOUBLE PRECISION, DIMENSION(:), INTENT(IN) :: y
              DOUBLE PRECISION, DIMENSION(:), INTENT(OUT) :: dydx
            END SUBROUTINE derivs
         END INTERFACE
       END SUBROUTINE rkqs_r
    END INTERFACE
    
    DOUBLE PRECISION, PARAMETER :: TINY=1.0d-30
    INTEGER*4, PARAMETER :: MAXSTP=10000
    INTEGER*4 :: nstp,i
    DOUBLE PRECISION :: h,hdid,hnext,x,xsav
    DOUBLE PRECISION, DIMENSION(SIZE(ystart)) :: dydx, y, yscal
    DOUBLE PRECISION :: z, scalefac
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
       CALL derivs(x,y,dydx)
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

       IF ((x-x2)*(x2-x1) >= 0.0) THEN
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
       !END MULTIFIELD

       IF(getEps(p,delp) .LT. 1 .AND. .NOT.(slowroll_start)) slowroll_start=.true.

       IF(ode_infl_end) THEN 
          IF (slowroll_infl_end) THEN
             IF(getEps(p, delp) .GT. 2 .AND. slowroll_start) THEN 
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
    PRINT*,'too many steps in odeint'
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

  ![ LP: ] Only called for ptb mode eqns
  SUBROUTINE odeint_c(ystart, x1, x2, eps, h1, hmin, derivs, qderivs, rkqs_c)
    USE ode_path
    USE internals
    USE powersp
    USE modpkparams
    USE potential
    USE modpk_utils, only : reallocate_rv, reallocate_rm

    IMPLICIT NONE
    COMPLEX(KIND=DP), DIMENSION(:), INTENT(INOUT) :: ystart
    DOUBLE PRECISION, INTENT(IN) :: x1,x2,eps,h1,hmin
    DOUBLE PRECISION, DIMENSION(num_inflaton) :: p, delp  ! the classical field phi and dphi are real
    COMPLEX(KIND=DP), DIMENSION(size(ystart)) :: ytmp
    LOGICAL :: use_q, compute_zpower

    INTERFACE
       SUBROUTINE derivs(x, y, dydx)
         USE modpkparams
         IMPLICIT NONE
         DOUBLE PRECISION, INTENT(IN) :: x
         COMPLEX(KIND=DP), DIMENSION(:), INTENT(IN) :: y
         COMPLEX(KIND=DP), DIMENSION(:), INTENT(OUT) :: dydx
       END SUBROUTINE derivs

       SUBROUTINE qderivs(x, y, dydx)
         USE modpkparams
         IMPLICIT NONE
         DOUBLE PRECISION, INTENT(IN) :: x
         COMPLEX(KIND=DP), DIMENSION(:), INTENT(IN) :: y
         COMPLEX(KIND=DP), DIMENSION(:), INTENT(OUT) :: dydx
       END SUBROUTINE qderivs

       SUBROUTINE rkqs_c(y,dydx,x,htry,eps,yscal,hdid,hnext,derivs)
         USE modpkparams
         IMPLICIT NONE
         COMPLEX(KIND=DP), DIMENSION(:), INTENT(INOUT) :: y
         COMPLEX(KIND=DP), DIMENSION(:), INTENT(IN) :: dydx,yscal
         DOUBLE PRECISION, INTENT(INOUT) :: x
         DOUBLE PRECISION, INTENT(IN) :: htry,eps
         DOUBLE PRECISION, INTENT(OUT) :: hdid,hnext
         INTERFACE
            SUBROUTINE derivs(x, y, dydx)
              USE modpkparams
              IMPLICIT NONE
              DOUBLE PRECISION, INTENT(IN) :: x
              COMPLEX(KIND=DP), DIMENSION(:), INTENT(IN) :: y
              COMPLEX(KIND=DP), DIMENSION(:), INTENT(OUT) :: dydx
            END SUBROUTINE derivs
         END INTERFACE
       END SUBROUTINE rkqs_c
    END INTERFACE

    DOUBLE PRECISION, PARAMETER :: TINY=1.0d-40
    INTEGER*4, PARAMETER :: MAXSTP=10000
    INTEGER*4 :: nstp,i
    DOUBLE PRECISION :: h,hdid,hnext,x,xsav
    COMPLEX(KIND=DP), DIMENSION(size(ystart)) :: dydx, y, yscal
    DOUBLE PRECISION :: scalefac, hubble, a_switch, dotphi
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

    DO nstp=1,MAXSTP

       IF (use_q) THEN
          ![ LP: ] super-h use Q
          CALL qderivs(x, y, dydx)
       ELSE
          ![ LP: ] sub-h use psi
          CALL derivs(x, y, dydx)
       END IF

       ! for yscal, evaluate real and imaginary parts separately, and then assemble them into complex format
       yscal(:)=cmplx(ABS(dble(y(:)))+ABS(h*dble(dydx(:)))+TINY, ABS(dble(y(:)*(0,-1)))+ABS(h*dble(dydx(:)*(0,-1)))+TINY)

       IF (save_steps .AND. (ABS(x-xsav) > ABS(dxsav))) &
            CALL save_a_step

       IF ((x+h-x2)*(x+h-x1) > 0.0) h=x2-x

       IF (use_q) THEN
          CALL rkqs_c(y,dydx,x,h,eps,yscal,hdid,hnext,qderivs)
       ELSE
          CALL rkqs_c(y,dydx,x,h,eps,yscal,hdid,hnext,derivs)
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
       p = DBLE(y(1:num_inflaton))
       delp = DBLE(y(num_inflaton+1 : 2*num_inflaton))
       dotphi = sqrt(dot_product(delp, delp))
       scalefac = a_init*exp(x)
       !END MULTIFIELD

       IF(getEps(p,delp) .LT. 1 .AND. .NOT.(slowroll_start)) slowroll_start=.true.

       IF(ode_ps_output) THEN
          IF(k .LT. a_init*EXP(x)*getH(p, delp)/eval_ps) THEN ! if k<aH/eval_ps, then k<<aH
             !MULTIFIELD
             IF (use_q) THEN
                ![ LP: ] w/out isocurv calculation
                call powerspectrum(y(2*num_inflaton+1:2*num_inflaton+num_inflaton**2) &
                    *scalefac/a_switch, delp, scalefac, pow_ptb_ij,pow_adiab_ik)
                ![ LP: ] with isocurv calculation --- not working yet
                !call powerspectrum(pow_ptb_ij,pow_adiab_ik,pow_isocurv_ik, &
                !  y(2*num_inflaton+1:2*num_inflaton+num_inflaton**2) &
                !    *scalefac/a_switch, delp, scalefac)

                powt_ik=tensorpower(y(2*num_inflaton+2*num_inflaton**2+1) &
                  *scalefac/a_switch, scalefac)
             ELSE
                call powerspectrum(y(2*num_inflaton+1:2*num_inflaton+num_inflaton**2), &
                    delp, scalefac, pow_ptb_ij,pow_adiab_ik)

                powt_ik=tensorpower(y(2*num_inflaton+2*num_inflaton**2+1), scalefac)
             END IF

             if (compute_zpower) then  !! compute only once upon horizon exit
                ![ LP: ]  CHECK; need to update powerspectrum to include cross-terms
                powz_ik = zpower(y(2*num_inflaton+2*num_inflaton**2+3), dotphi, scalefac)
                compute_zpower = .false.
             end if

             ! for single field, end mode evolution when the mode is frozen out of the horizon
             ! for multifield, need to evolve the modes until the end of inflation to include superhorizon evolution
             IF (num_inflaton .EQ. 1) infl_ended = .TRUE.  
             !END MULTIFIELD
          END IF
       END IF

![ LP: ] CHECK;  check for adiabaticity?
       IF(ode_infl_end) THEN 
          IF (slowroll_infl_end) THEN
             IF(getEps(p, delp) .GT. 2 .AND. slowroll_start) infl_ended=.TRUE.
          ELSE
             IF(getEps(p, delp) .GT. 1 .AND. slowroll_start) THEN
                PRINT*,'MODPK: You asked for a no-slowroll-breakdown model, but inflation'
                PRINT*,'MODPK: already ended via slowroll violation before your phi_end was'
                PRINT*,'MODPK: reached. Please take another look at your inputs.'
                PRINT*,'MODPK: QUITTING'
                PRINT*,'EPSILON =', getEps(p, delp), 'phi =', p
                STOP
             ENDIF

             !MULTIFIELD
             IF (SIZE(p) .EQ. 1) THEN
                IF (phidot_sign(1).GT.0..AND.(p(1).GT.(phi_infl_end(1)+0.1))) infl_ended=.TRUE.
                IF (phidot_sign(1).LT.0..AND.(p(1).LT.(phi_infl_end(1)-0.1))) infl_ended=.TRUE.
             ELSE 
                ! for multifield, determine the total field distance travelled
                IF (SQRT(DOT_PRODUCT(p-phi_init, p-phi_init)) .GT. (delsigma+0.1)) infl_ended = .TRUE.
             END IF
             !END MULTIFIELD
          ENDIF

          IF (infl_ended) THEN
             IF (use_q) THEN
                ytmp(:) = y(:)
                ![ LP: ] bckgrd
                ystart(1:2*num_inflaton) = y(1:2*num_inflaton)

                ![ LP: ] ptbs
                ystart(2*num_inflaton+1:2*num_inflaton+num_inflaton**2) = &
                  ytmp(2*num_inflaton+1:2*num_inflaton+num_inflaton**2)*scalefac/a_switch
                ystart(2*num_inflaton+num_inflaton**2+1:2*num_inflaton+2*num_inflaton**2) = &
                  ytmp(2*num_inflaton+num_inflaton**2+1:2*num_inflaton+2*num_inflaton**2)&
                  *scalefac/a_switch + ystart(2*num_inflaton+1:2*num_inflaton+num_inflaton**2)

                ![ LP: ] tensors
                ystart(2*num_inflaton+2*num_inflaton**2+1) = ytmp(2*num_inflaton+2*num_inflaton**2+1)*scalefac/a_switch
                ystart(2*num_inflaton+2*num_inflaton**2+2) = ytmp(2*num_inflaton+2*num_inflaton**2+2)*scalefac/a_switch + ystart(4*num_inflaton+1)
             ELSE
                ystart(:) = y(:)
             END IF
             IF (save_steps) CALL save_a_step
             RETURN
          END IF
       ENDIF

       IF (k .LT. a_init*exp(x)*getH(p, delp)/useq_ps .and. (.not. use_q)) THEN 
          !switch to the Q variable for super-horizon evolution
          !only apply the switch on y(1:4*num_inflaton+2)
          use_q = .TRUE.
          a_switch = scalefac
          !set intial condition in (Q*a_switch)
          ytmp(:) = y(:)

          y(2*num_inflaton+1:2*num_inflaton+num_inflaton**2) = &
            ytmp(2*num_inflaton+1:2*num_inflaton+num_inflaton**2)
          y(2*num_inflaton+num_inflaton**2+1:2*num_inflaton+2*num_inflaton**2) = &
            ytmp(2*num_inflaton+num_inflaton**2+1:2*num_inflaton+2*num_inflaton**2) & 
            - y(2*num_inflaton+1:2*num_inflaton+num_inflaton**2)

          y(2*num_inflaton+2*num_inflaton**2+1) = ytmp(2*num_inflaton+2*num_inflaton**2+1)
          y(2*num_inflaton+2*num_inflaton**2+2) = ytmp(2*num_inflaton+2*num_inflaton**2+2) &
            - y(2*num_inflaton+2*num_inflaton**2+1)
       END IF

       IF (ode_underflow) RETURN
       IF (ABS(hnext) < hmin) THEN
          WRITE(*,*) 'stepsize smaller than minimum in odeint'
          STOP
       END IF
       h=hnext
    END DO
    PRINT*,'too many steps in odeint'
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
         ptb_tmp =ytmp(2*num_inflaton+1:2*num_inflaton+num_inflaton**2)
         dptb_tmp =ytmp(2*num_inflaton+num_inflaton**2+1:2*num_inflaton+2*num_inflaton**2)

         ytmp(2*num_inflaton+1:2*num_inflaton+num_inflaton**2) = &
           ptb_tmp*scalefac/a_switch
         ytmp(2*num_inflaton+num_inflaton**2+1:2*num_inflaton+2*num_inflaton**2) = &
           dptb_tmp*scalefac/a_switch + ptb_tmp

         ytmp(2*num_inflaton+2*num_inflaton**2+1) = &
           ytmp(4*2*num_inflaton+2*num_inflaton**2+1)*scalefac/a_switch
         ytmp(2*num_inflaton+2*num_inflaton**2+2) = &
           ytmp(4*2*num_inflaton+2*num_inflaton**2+2)*scalefac/a_switch + ytmp(4*num_inflaton+1)
      END IF

      yp(1:size(yp,1)/2,kount) = dble(ytmp(:))
      yp(size(yp,1)/2+1:size(yp,1),kount) = dble(ytmp(:)*(0,-1))
      xsav=x

    END SUBROUTINE save_a_step
    !  (C) Copr. 1986-92 Numerical Recipes Software, adapted.
  
  END SUBROUTINE odeint_c

END MODULE modpk_odeint

