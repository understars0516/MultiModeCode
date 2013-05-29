MODULE modpk_utils
  use modpkparams
  IMPLICIT NONE

  INTERFACE rkck
     module procedure rkck_r
     module procedure rkck_c
  END INTERFACE

  interface hacked_matrixmul
     !module procedure hacked_matrixmul_CC
     module procedure hacked_matrixmul_DC
     !module procedure hacked_matrixmul_DD
  end interface

CONTAINS

  ![ LP: ] Background derivatives y'=f(y)
  SUBROUTINE bderivs(x,y,yprime)
    USE modpkparams
    USE potential, ONLY: pot,dVdphi,d2Vdphi2,getH,getHdot
    USE camb_interface, ONLY : pk_bad
    DOUBLE PRECISION, INTENT(IN) :: x
    DOUBLE PRECISION, DIMENSION(:), INTENT(IN) :: y
    DOUBLE PRECISION, DIMENSION(:), INTENT(OUT) :: yprime

    !MULTIFIELD
    DOUBLE PRECISION, DIMENSION(size(y)/2) :: p, delp
    DOUBLE PRECISION :: hubble,dhubble
    !END MULTIFIEND

    integer :: i
    !
    !     x=alpha
    !     y(FIRST HALF)=phi              dydx(FIRST HALF)=dphi/dalpha
    !     y(SECOND HALF)=dphi/dalpha      dydx(SECOND HALF)=d^2phi/dalpha^2
    !

    !MULTIFIELD
    p = y(1 : size(y)/2)
    delp = y(size(y)/2+1 : size(y))
    !END MULTIFIELD

    IF(dot_product(delp,delp) .gt. 6.0d0) THEN
       WRITE(*,*) 'MODPK: H is imaginary:',x,p,delp
       !In the case of the hilltop potential, the integrator
       !in a trial step can go here very occasionally because
       !the trial step is too large and it has come too close to V=0.
       !We will stop it going this way, and the code will find the
       !correct epsilon=1 point which has, by definition, to be
       !before this problematic region is reached.
       IF(potential_choice.eq.6) THEN
          yprime(1)=0.0d0
          yprime(2)=0.0d0
          RETURN
       ENDIF
       WRITE(*,*) 'MODPK: QUITTING'
       write(*,*) 'vparams: ', (vparams(i,:),i=1,size(vparams,1))
       if (.not.instreheat) write(*,*) 'N_pivot: ', N_pivot
       STOP
    END IF

    hubble=getH(p,delp)
    dhubble=getHdot(p,delp)

    !MULTIFIELD
    yprime(1 : size(y)/2) = delp
    yprime(size(y)/2+1 : size(y)) = -((3.0+dhubble/hubble)*delp+dVdphi(p)/hubble/hubble)
    !END MULTIFIELD 

    RETURN

  END SUBROUTINE bderivs


  ![ LP: ] Full y (back+mode matrix+tensor) derivatives y'=f(y)
  SUBROUTINE derivs(x,y,yprime)
    USE modpkparams
    USE internals
    USE potential, ONLY: pot, dVdphi, d2Vdphi2, getH, getHdot, getEps, getEta
    IMPLICIT NONE
    DOUBLE PRECISION, INTENT(IN) :: x
    COMPLEX(KIND=DP), DIMENSION(:), INTENT(IN) :: y
    COMPLEX(KIND=DP), DIMENSION(:), INTENT(OUT) :: yprime

    ! background quantity
    DOUBLE PRECISION :: hubble, dhubble, a, epsilon, dotphi, eta
    DOUBLE PRECISION :: thetaN2, Vzz, Vz, grad_V  !! thetaN2 = (d\theta/dNe)^2
    DOUBLE PRECISION, DIMENSION(num_inflaton) :: p, delp, Vp
    DOUBLE PRECISION, DIMENSION(num_inflaton, num_inflaton) :: Cab, Vpp

    COMPLEX(KIND=DP), DIMENSION(num_inflaton**2) :: psi, dpsi        ! scalar ptb mode matrix
    COMPLEX(KIND=DP) :: v, dv                                        ! tensor perturbations
    COMPLEX(KIND=DP) :: u_zeta, du_zeta

    integer :: i, j

    !     x = alpha
    !     y(1:n) = phi                 dydx(1:n)=dphi/dalpha
    !     y(n+1:2n) = dphi/dalpha      dydx(n+1:2n)=d^2phi/dalpha^2
    !     y(2n+1:2n+n**2) = psi               dydx(2n+1:3n)=dpsi/dalpha
    !     y(2n+n**2+1:2n+2n**2) = dpsi/dalpha       dydx(3n+1:4n)=d^2psi/dalpha^2
    !     y(2n+2n**2+1) = v                  dydx(4n+1)=dv/dalpha
    !     y(2n+2n**2+2) = dv/dalpha          dydx(4n+2)=d^2v/dalpha^2
    !     y(2n+2n**2+3) = u_zeta     dydx(4n+4)=d^2u_zeta/dalpha^2  
    !     y(2n+2n**2+4) = du_zeta/dalpha     dydx(4n+4)=d^2u_zeta/dalpha^2  

    p = dble(y(1:num_inflaton))
    delp = dble(y(num_inflaton+1:2*num_inflaton))
    dotphi = sqrt(dot_product(delp, delp))

    ![ LP: ] Aliases to potential derivatives
    epsilon = getEps(p, delp)
    eta = geteta(p, delp)
    Vpp = d2Vdphi2(p)
    Vp = dVdphi(p)
    Vzz = dot_product(delp, matmul(Vpp, delp))/dotphi**2
    Vz = dot_product(Vp, delp)/dotphi
    grad_V = sqrt(dot_product(Vp, Vp))

    IF(dot_product(delp, delp) .GT. 6.d0) THEN
       WRITE(*,*) 'MODPK: H is imaginary:',x,p,delp
       WRITE(*,*) 'MODPK: QUITTING'
       write(*,*) 'vparams: ', (vparams(i, :), i=1, size(vparams,1))
       if (.not.instreheat) write(*,*) 'N_pivot: ', N_pivot
       STOP
    END IF

    hubble=getH(p,delp)
    dhubble=getHdot(p,delp)
    a=EXP(x)

    ![ LP: ] Alias y's into real variable names
    psi  = y(2*num_inflaton+1:2*num_inflaton+num_inflaton**2)
    dpsi = y(2*num_inflaton+num_inflaton**2+1:2*num_inflaton+2*num_inflaton**2)
    v  = y(2*num_inflaton+2*num_inflaton**2+1)
    dv  = y(2*num_inflaton+2*num_inflaton**2+2)
    u_zeta = y(2*num_inflaton+2*num_inflaton**2+3)
    du_zeta = y(2*num_inflaton+2*num_inflaton**2+4)

    ![ LP: ] Build the mass matrix, Cab
    if (potential_choice .eq. 7) then
       Cab = 0.d0  ! exponential potential 7, Cab is excatly zero,prevents numerical error
    else
       forall (i=1:num_inflaton, j=1:num_inflaton) & 
            Cab(i,j) = Vpp(i,j) + 2*epsilon/dotphi * (delp(i)*Vp(j) + delp(j)*Vp(i))/dotphi &
            + 2*epsilon*(3-epsilon)*hubble**2 * delp(i)*delp(j)/dotphi**2
    end if

    ![ LP: ] -----------------------------
    ![ LP: ] Set the RHS of y'(x) = f(y(x))
    ![ LP: ] -----------------------------

    ![ LP: ] background
    yprime(1:num_inflaton) = cmplx(delp)
    yprime(num_inflaton+1:2*num_inflaton) = cmplx(-((3.0+dhubble/hubble)*delp+dVdphi(p)/hubble/hubble))

    ![ LP: ] ptb matrix
    yprime(2*num_inflaton+1:2*num_inflaton+num_inflaton**2) = dpsi

    !yprime(2*num_inflaton+num_inflaton**2+1:2*num_inflaton+2*num_inflaton**2) = &
    !  -(1. - epsilon)*dpsi - (k/a_init/a/hubble)**2*psi &
    !  + (2. - epsilon)*psi - matmul(Cab, psi)/hubble**2
    yprime(2*num_inflaton+num_inflaton**2+1:2*num_inflaton+2*num_inflaton**2) = &
      -(1. - epsilon)*dpsi - (k/a_init/a/hubble)**2*psi &
      + (2. - epsilon)*psi - hacked_matrixmul(Cab, psi)/hubble**2

    ![ LP: ] tensors
    yprime(2*num_inflaton+2*num_inflaton**2+1) = dv
    yprime(2*num_inflaton+2*num_inflaton**2+2) = -(1. - epsilon)*dv - &
      (k/a_init/a/hubble)**2*v + (2. - epsilon)*v

    ![ LP: ] adiabatic ptb
    yprime(2*num_inflaton+2*num_inflaton**2+3) = du_zeta
    thetaN2 = (grad_V + Vz)*(grad_V - Vz)/(dotphi*hubble**2)**2 
    yprime(2*num_inflaton+2*num_inflaton**2+4) = -(1. - epsilon)*du_zeta - (k/a_init/a/hubble)**2*u_zeta &
         + (2 + 5*epsilon - 2*epsilon**2 + 2*epsilon*eta + thetaN2 - Vzz/hubble**2)*u_zeta


    RETURN

  END SUBROUTINE derivs



  ![ LP: ] Full y (back+mode matrix(in Q at horizon cross)+tensor) derivatives y'=f(y)
  SUBROUTINE qderivs(x,y,yprime)
    USE modpkparams
    USE internals
    USE potential, ONLY: pot, dVdphi, d2Vdphi2, getH, getHdot, getEps, getEta
    IMPLICIT NONE
    DOUBLE PRECISION, INTENT(IN) :: x
    COMPLEX(KIND=DP), DIMENSION(:), INTENT(IN) :: y
    COMPLEX(KIND=DP), DIMENSION(:), INTENT(OUT) :: yprime

    ! background quantity
    DOUBLE PRECISION :: hubble, dhubble, a, epsilon, dotphi, eta
    DOUBLE PRECISION :: thetaN2, Vzz, Vz, grad_V  !! thetaN2 = (d\theta/dNe)^2
    DOUBLE PRECISION, DIMENSION(num_inflaton) :: p, delp, Vp  
    DOUBLE PRECISION, DIMENSION(num_inflaton, num_inflaton) :: Cab, Vpp

    COMPLEX(KIND=DP), DIMENSION(num_inflaton**2) :: q_ptb, dq_ptb     ! scalar ptb matrix
    COMPLEX(KIND=DP) :: q_tensor, dq_tensor                           ! tensor perturbations
    COMPLEX(KIND=DP) :: u_zeta, du_zeta

    integer :: i, j

    !     x = alpha
    !     y(1:n) = phi                 dydx(1:n)=dphi/dalpha
    !     y(n+1:2n) = dphi/dalpha      dydx(n+1:2n)=d^2phi/dalpha^2
    !     y(2n+1:2n+n**2) = q_ptb               dydx(2n+1:3n)=dq_ptb/dalpha
    !     y(2n+n**2+1:2n+2n**2) = dq_ptb/dalpha       dydx(3n+1:4n)=d^2q_ptb/dalpha^2
    !     y(2n+2n**2+1) = q_tensor                  dydx(4n+1)=dq_tensor/dalpha
    !     y(2n+2n**2+2) = dq_tensor/dalpha          dydx(4n+2)=d^2q_tensor/dalpha^2
    !     y(2n+2n**2+3) = u_zeta     dydx(4n+4)=d^2u_zeta/dalpha^2  
    !     y(2n+2n**2+4) = du_zeta/dalpha     dydx(4n+4)=d^2u_zeta/dalpha^2  

    p = dble(y(1:num_inflaton))
    delp = dble(y(num_inflaton+1:2*num_inflaton))
    dotphi = sqrt(dot_product(delp, delp))

    ![ LP: ] Aliases to potential derivatives
    epsilon = getEps(p, delp)
    eta = geteta(p, delp)
    Vpp = d2Vdphi2(p)
    Vp = dVdphi(p)
    Vzz = dot_product(delp, matmul(Vpp, delp))/dotphi**2
    Vz = dot_product(Vp, delp)/dotphi
    grad_V = sqrt(dot_product(Vp, Vp))

    IF(dot_product(delp, delp) .GT. 6.d0) THEN
       WRITE(*,*) 'MODPK: H is imaginary:',x,p,delp
       WRITE(*,*) 'MODPK: QUITTING'
       write(*,*) 'vparams: ', (vparams(i, :), i=1, size(vparams,1))
       if (.not.instreheat) write(*,*) 'N_pivot: ', N_pivot
       STOP
    END IF

    hubble=getH(p,delp)
    dhubble=getHdot(p,delp)
    a=EXP(x)

    ![ LP: ] Alias y's into real variable names
    q_ptb  = y(2*num_inflaton+1:2*num_inflaton+num_inflaton**2)
    dq_ptb = y(2*num_inflaton+num_inflaton**2+1:2*num_inflaton+2*num_inflaton**2)
    q_tensor  = y(2*num_inflaton+2*num_inflaton**2+1)
    dq_tensor = y(2*num_inflaton+2*num_inflaton**2+2)
    u_zeta = y(2*num_inflaton+2*num_inflaton**2+3)
    du_zeta = y(2*num_inflaton+2*num_inflaton**2+4)

    ![ LP: ] Build the mass matrix, Cab
    if (potential_choice .eq. 7) then
       Cab = 0.d0  ! for exponential potential 7, Cab is excatly zero, need to set this in order to prevent numerical error
    else
       forall (i=1:num_inflaton, j=1:num_inflaton) & 
            Cab(i,j) = Vpp(i,j) + 2*epsilon/dotphi * (delp(i)*Vp(j) + delp(j)*Vp(i))/dotphi &
            + 2*epsilon*(3-epsilon)*hubble**2 * delp(i)*delp(j)/dotphi**2
    end if

    ![ LP: ] -----------------------------
    ![ LP: ] Set the RHS of y'(x) = f(y(x))
    ![ LP: ] -----------------------------

    ![ LP: ] background
    yprime(1:num_inflaton) = cmplx(delp)
    yprime(num_inflaton+1:2*num_inflaton) = cmplx(-((3.0+dhubble/hubble)*delp+dVdphi(p)/hubble/hubble))

    ![ LP: ] ptb matrix in Q_IJ
    yprime(2*num_inflaton+1:2*num_inflaton+num_inflaton**2) = dq_ptb
    yprime(2*num_inflaton+num_inflaton**2+1:2*num_inflaton+2*num_inflaton**2) = &
      -(3. - epsilon)*dq_ptb - (k/a_init/a/hubble)**2*q_ptb -&
      hacked_matrixmul(Cab, q_ptb)/hubble**2

    ![ LP: ] tensors
    yprime(2*num_inflaton+2*num_inflaton**2+1) = dq_tensor
    yprime(2*num_inflaton+2*num_inflaton**2+2) = -(3. - epsilon)*dq_tensor - (k/a_init/a/hubble)**2*q_tensor

    !! below is the same as in SUBROUTINE derivs
    ![ LP: ] adiabatic ptb
    yprime(2*num_inflaton+2*num_inflaton**2+3) = du_zeta
    thetaN2 = (grad_V + Vz)*(grad_V - Vz)/(dotphi*hubble**2)**2 
    yprime(2*num_inflaton+2*num_inflaton**2+4) = -(1. - epsilon)*du_zeta - (k/a_init/a/hubble)**2*u_zeta &
         + (2 + 5*epsilon - 2*epsilon**2 + 2*epsilon*eta + thetaN2 - Vzz/hubble**2)*u_zeta

    RETURN
  END SUBROUTINE qderivs


  SUBROUTINE rkqs_r(y,dydx,x,htry,eps,yscal,hdid,hnext,derivs)
    USE ode_path
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
    INTEGER*4 :: ndum
    DOUBLE PRECISION :: errmax,h,htemp,xnew
    DOUBLE PRECISION, DIMENSION(size(y)) :: yerr,ytemp
    DOUBLE PRECISION, PARAMETER :: SAFETY=0.9d0,PGROW=-0.2d0,PSHRNK=-0.25d0,&
         ERRCON=1.89e-4
    if (size(y)==size(dydx) .and. size(dydx)==size(yscal)) then
       ndum = size(y)
    else
       write(*,*) 'Wrong array sizes in rkqs'
       stop
    end if
    h=htry
    do
       call rkck(y,dydx,x,h,ytemp,yerr,derivs)
       errmax=maxval(abs(yerr(:)/yscal(:)))/eps
       if (errmax <= 1.0) exit
       htemp=SAFETY*h*(errmax**PSHRNK)
       h=sign(max(abs(htemp),0.1d0*abs(h)),h)
       xnew=x+h
       if (xnew == x) then 
          print*, 'stepsize underflow in rkqs'
          ode_underflow = .true.
          return
       endif
    end do
    if (errmax > ERRCON) then
       hnext=SAFETY*h*(errmax**PGROW)
    else
       hnext=5.0d0*h
    end if
    hdid=h
    x=x+h
    y(:)=ytemp(:)
    !  (C) Copr. 1986-92 Numerical Recipes Software, adapted.
  END SUBROUTINE rkqs_r

  SUBROUTINE rkqs_c(y,dydx,x,htry,eps,yscal,hdid,hnext,derivs)
    USE ode_path
    USE modpkparams
    IMPLICIT NONE
    COMPLEX(KIND=DP), DIMENSION(:), INTENT(INOUT) :: y
    COMPLEX(KIND=DP), DIMENSION(:), INTENT(IN) :: yscal, dydx
    DOUBLE PRECISION, INTENT(INOUT) :: x
    DOUBLE PRECISION, INTENT(IN) :: htry,eps
    DOUBLE PRECISION, INTENT(OUT) :: hdid,hnext
    INTERFACE
       SUBROUTINE derivs(x,y,dydx)
         USE modpkparams
         IMPLICIT NONE
         DOUBLE PRECISION, INTENT(IN) :: x
         COMPLEX(KIND=DP), DIMENSION(:), INTENT(IN) :: y
         COMPLEX(KIND=DP), DIMENSION(:), INTENT(OUT) :: dydx
       END SUBROUTINE derivs
    END INTERFACE

    INTEGER*4 :: ndum
    DOUBLE PRECISION :: errmax,h,htemp,xnew
    COMPLEX(KIND=DP), DIMENSION(size(y)) :: yerr,ytemp
    DOUBLE PRECISION, PARAMETER :: SAFETY=0.9d0,PGROW=-0.2d0,PSHRNK=-0.25d0,&
         ERRCON=1.89e-4

    DOUBLE PRECISION :: yerr_r(2*size(y)), yscal_r(2*size(yscal))

    if (size(y)==size(dydx) .and. size(dydx)==size(yscal)) then
       ndum = size(y)
    else
       write(*,*) 'Wrong array sizes in rkqs'
       stop
    end if
    h=htry
    do
       call rkck(y,dydx,x,h,ytemp,yerr,derivs)

       ! in doing error estimation and step size rescaling, we switch to real components
       yerr_r(1 : size(yerr)) = dble(yerr)
       yerr_r(size(yerr)+1 : 2*size(yerr)) = dble(yerr*(0,-1)) 

       yscal_r(1 : size(yscal)) = dble(yscal)
       yscal_r(size(yscal)+1 : 2*size(yscal)) = dble(yscal*(0,-1))  

       errmax=maxval(abs(yerr_r(:)/yscal_r(:)))/eps

       if (errmax <= 1.0) exit

       htemp=SAFETY*h*(errmax**PSHRNK)
       h=sign(max(abs(htemp),0.1d0*abs(h)),h)
       xnew=x+h
       if (xnew == x) then 
          print*, 'stepsize underflow in rkqs'
          ode_underflow = .true.
          return
       endif
    end do
    if (errmax > ERRCON) then
       hnext=SAFETY*h*(errmax**PGROW)
    else
       hnext=5.0d0*h
    end if
    hdid=h
    x=x+h
    y(:)=ytemp(:)
    !  (C) Copr. 1986-92 Numerical Recipes Software, adapted.
  END SUBROUTINE rkqs_c

  SUBROUTINE rkck_r(y,dydx,x,h,yout,yerr,derivs)
    IMPLICIT NONE
    DOUBLE PRECISION, DIMENSION(:), INTENT(IN) :: y,dydx
    DOUBLE PRECISION, INTENT(IN) :: x,h
    DOUBLE PRECISION, DIMENSION(:), INTENT(OUT) :: yout,yerr
    INTERFACE
       SUBROUTINE derivs(x,y,dydx)
         IMPLICIT NONE
         DOUBLE PRECISION, INTENT(IN) :: x
         DOUBLE PRECISION, DIMENSION(:), INTENT(IN) :: y
         DOUBLE PRECISION, DIMENSION(:), INTENT(OUT) :: dydx
       END SUBROUTINE derivs
    END INTERFACE
    INTEGER*4 :: ndum
    DOUBLE PRECISION, DIMENSION(size(y)) :: ak2,ak3,ak4,ak5,ak6,ytemp
    DOUBLE PRECISION, PARAMETER :: A2=0.2d0,A3=0.3d0,A4=0.6d0,A5=1.0d0,&
         A6=0.875d0,B21=0.2d0,B31=3.0d0/40.0d0,B32=9.0d0/40.0d0,&
         B41=0.3d0,B42=-0.9d0,B43=1.2d0,B51=-11.0d0/54.0d0,&
         B52=2.5d0,B53=-70.0d0/27.0d0,B54=35.0d0/27.0d0,&
         B61=1631.0d0/55296.0d0,B62=175.0d0/512.0d0,&
         B63=575.0d0/13824.0d0,B64=44275.0d0/110592.0d0,&
         B65=253.0d0/4096.0d0,C1=37.0d0/378.0d0,&
         C3=250.0d0/621.0d0,C4=125.0d0/594.0d0,&
         C6=512.0d0/1771.0d0,DC1=C1-2825.0d0/27648.0d0,&
         DC3=C3-18575.0d0/48384.0d0,DC4=C4-13525.0d0/55296.0d0,&
         DC5=-277.0d0/14336.0d0,DC6=C6-0.25d0
    if (size(y)==size(dydx) .and. size(dydx)==size(yout) .and. size(yout)==size(yerr)) then
       ndum = size(y)
    else
       write(*,*) 'Wrong array sizes in rkck'
       stop
    end if
    ytemp=y+B21*h*dydx
    call derivs(x+A2*h,ytemp,ak2)
    ytemp=y+h*(B31*dydx+B32*ak2)
    call derivs(x+A3*h,ytemp,ak3)
    ytemp=y+h*(B41*dydx+B42*ak2+B43*ak3)
    call derivs(x+A4*h,ytemp,ak4)
    ytemp=y+h*(B51*dydx+B52*ak2+B53*ak3+B54*ak4)
    call derivs(x+A5*h,ytemp,ak5)
    ytemp=y+h*(B61*dydx+B62*ak2+B63*ak3+B64*ak4+B65*ak5)
    call derivs(x+A6*h,ytemp,ak6)
    yout=y+h*(C1*dydx+C3*ak3+C4*ak4+C6*ak6)
    yerr=h*(DC1*dydx+DC3*ak3+DC4*ak4+DC5*ak5+DC6*ak6)
    !  (C) Copr. 1986-92 Numerical Recipes Software, adapted.
  END SUBROUTINE rkck_r

  SUBROUTINE rkck_c(y,dydx,x,h,yout,yerr,derivs)
    USE modpkparams
    IMPLICIT NONE
    COMPLEX(KIND=DP), DIMENSION(:), INTENT(IN) :: y, dydx
    DOUBLE PRECISION, INTENT(IN) :: x,h
    COMPLEX(KIND=DP), DIMENSION(:), INTENT(OUT) :: yout,yerr
    INTERFACE
       SUBROUTINE derivs(x,y,dydx)
         USE modpkparams
         IMPLICIT NONE
         DOUBLE PRECISION, INTENT(IN) :: x
         COMPLEX(KIND=DP), DIMENSION(:), INTENT(IN) :: y
         COMPLEX(KIND=DP), DIMENSION(:), INTENT(OUT) :: dydx
       END SUBROUTINE derivs
    END INTERFACE
    INTEGER*4 :: ndum
    COMPLEX(KIND=DP), DIMENSION(size(y)) :: ytemp, ak2,ak3,ak4,ak5,ak6
    DOUBLE PRECISION, PARAMETER :: A2=0.2d0,A3=0.3d0,A4=0.6d0,A5=1.0d0,&
         A6=0.875d0,B21=0.2d0,B31=3.0d0/40.0d0,B32=9.0d0/40.0d0,&
         B41=0.3d0,B42=-0.9d0,B43=1.2d0,B51=-11.0d0/54.0d0,&
         B52=2.5d0,B53=-70.0d0/27.0d0,B54=35.0d0/27.0d0,&
         B61=1631.0d0/55296.0d0,B62=175.0d0/512.0d0,&
         B63=575.0d0/13824.0d0,B64=44275.0d0/110592.0d0,&
         B65=253.0d0/4096.0d0,C1=37.0d0/378.0d0,&
         C3=250.0d0/621.0d0,C4=125.0d0/594.0d0,&
         C6=512.0d0/1771.0d0,DC1=C1-2825.0d0/27648.0d0,&
         DC3=C3-18575.0d0/48384.0d0,DC4=C4-13525.0d0/55296.0d0,&
         DC5=-277.0d0/14336.0d0,DC6=C6-0.25d0
    if (size(y)==size(dydx) .and. size(dydx)==size(yout) .and. size(yout)==size(yerr)) then
       ndum = size(y)
    else
       write(*,*) 'Wrong array sizes in rkck'
       stop
    end if
    ytemp=y+B21*h*dydx
    call derivs(x+A2*h,ytemp,ak2)
    ytemp=y+h*(B31*dydx+B32*ak2)
    call derivs(x+A3*h,ytemp,ak3)
    ytemp=y+h*(B41*dydx+B42*ak2+B43*ak3)
    call derivs(x+A4*h,ytemp,ak4)
    ytemp=y+h*(B51*dydx+B52*ak2+B53*ak3+B54*ak4)
    call derivs(x+A5*h,ytemp,ak5)
    ytemp=y+h*(B61*dydx+B62*ak2+B63*ak3+B64*ak4+B65*ak5)
    call derivs(x+A6*h,ytemp,ak6)
    yout=y+h*(C1*dydx+C3*ak3+C4*ak4+C6*ak6)
    yerr=h*(DC1*dydx+DC3*ak3+DC4*ak4+DC5*ak5+DC6*ak6)
    !  (C) Copr. 1986-92 Numerical Recipes Software, adapted.
  END SUBROUTINE rkck_c


  FUNCTION locate(xx,x)
    IMPLICIT NONE
    DOUBLE PRECISION, DIMENSION(:), INTENT(IN) :: xx
    DOUBLE PRECISION, INTENT(IN) :: x
    INTEGER*4 :: locate
    INTEGER*4 :: n,jl,jm,ju
    LOGICAL :: ascnd
    n=size(xx)
    ascnd = (xx(n) >= xx(1))
    jl=0
    ju=n+1
    do
       if (ju-jl <= 1) exit
       jm=(ju+jl)/2
       if (ascnd .eqv. (x >= xx(jm))) then
          jl=jm
       else
          ju=jm
       end if
    end do
    if (x == xx(1)) then
       locate=1
    else if (x == xx(n)) then
       locate=n-1
    else
       locate=jl
    end if
    !  (C) Copr. 1986-92 Numerical Recipes Software, adapted.
  END FUNCTION locate

  ![ LP: ] Polynomial interpolation
  ![ LP: ] Given array XA and YA (of same length) and given a value X, returns
  !value Y such that if P(x) is a polynomial st P(XA_i)=YA_i, then Y=P(X) ---
  !and an error estimate DY
  SUBROUTINE polint(xa,ya,x,y,dy)
    IMPLICIT NONE
    DOUBLE PRECISION, DIMENSION(:), INTENT(IN) :: xa,ya
    DOUBLE PRECISION, INTENT(IN) :: x
    DOUBLE PRECISION, INTENT(OUT) :: y,dy
    INTEGER*4 :: m,n,ns
    INTEGER*4, DIMENSION(1) :: imin
    DOUBLE PRECISION, DIMENSION(size(xa)) :: c,d,den,ho,absho
    if (size(xa)==size(ya)) then
       n=size(xa)
    else
       write(*,*) 'Wrong array sizes in polint'
       stop
    end if
    c=ya
    d=ya
    ho=xa-x
    absho=abs(ho)
    imin=minloc(absho(:))
    ns=imin(1)
    y=ya(ns)
    ns=ns-1
    do m=1,n-1
       den(1:n-m)=ho(1:n-m)-ho(1+m:n)
       if (any(den(1:n-m) == 0.0)) then
          write(*,*) 'polint: calculation failure'
          stop
       end if
       den(1:n-m)=(c(2:n-m+1)-d(1:n-m))/den(1:n-m)
       d(1:n-m)=ho(1+m:n)*den(1:n-m)
       c(1:n-m)=ho(1:n-m)*den(1:n-m)
       if (2*ns < n-m) then
          dy=c(ns+1)
       else
          dy=d(ns)
          ns=ns-1
       end if
       y=y+dy
    end do
    !  (C) Copr. 1986-92 Numerical Recipes Software, adapted.
  END SUBROUTINE polint

  !MULTIFIELD 
  SUBROUTINE array_polint(xa, ya, x, y, dy)
    IMPLICIT NONE

    DOUBLE PRECISION, INTENT(IN) :: xa(:), ya(:,:)
    DOUBLE PRECISION, INTENT(IN) :: x
    DOUBLE PRECISION, INTENT(OUT) :: y(size(ya(:,1))),dy(size(ya(:,1)))
    INTEGER :: i

    do i = 1, size(ya(:,1))
       call polint(xa, ya(i,:), x, y(i), dy(i))
    end do

  END SUBROUTINE array_polint
  !END MULTIFIELD

  FUNCTION reallocate_rv(p,n)
    DOUBLE PRECISION, DIMENSION(:), POINTER :: p, reallocate_rv
    INTEGER*4, INTENT(IN) :: n
    INTEGER*4 :: nold,ierr
    allocate(reallocate_rv(n),stat=ierr)  !! allocate memeory of size n at new address to be returned
    if (ierr /= 0) then
       write(*,*) 'reallocate_rv: problem in attempt to allocate memory'
       stop
    end if
    if (.not. associated(p)) RETURN
    nold=size(p)
    reallocate_rv(1:min(nold,n))=p(1:min(nold,n))  !! copy old array contents to the new memory block
    deallocate(p)  !! free the old meomory block
    !  (C) Copr. 1986-92 Numerical Recipes Software, adapted.
  END FUNCTION reallocate_rv

  FUNCTION reallocate_rm(p,n,m)
    DOUBLE PRECISION, DIMENSION(:,:), POINTER :: p, reallocate_rm
    INTEGER*4, INTENT(IN) :: n,m
    INTEGER*4 :: nold,mold,ierr
    allocate(reallocate_rm(n,m),stat=ierr)
    if (ierr /= 0) then
       write(*,*) 'reallocate_rm: problem in attempt to allocate memory'
       stop
    end if
    if (.not. associated(p)) RETURN
    nold=size(p,1)
    mold=size(p,2)
    reallocate_rm(1:min(nold,n),1:min(mold,m))= p(1:min(nold,n),1:min(mold,m))
    deallocate(p)
    !  (C) Copr. 1986-92 Numerical Recipes Software, adapted.
  END FUNCTION reallocate_rm


  ![ LP: ] This takes a matrix A and multiplies it by a matrix B that is in the
  !form of a vector where the rows of B(i,1:N) --> first N terms in B(1:N), etc
  !Returns a "hacked" vector...

  ![ LP: ] If you want to fix this, then change structure of y's to an array
  !and use matrix multiplication C*psi

  ![ LP: ] This is the ugliest piece of code I've ever written.

  ![ LP: ] A=double, B=double
!  function hacked_matrixmul_DD(A,B)
!    implicit none
!
!    double precision, dimension(:,:), intent(in) :: A
!    double precision, dimension(:,:) :: temp_matrix
!    double precision, dimension (:), intent(in) :: B
!    double precision, dimension (:) :: hacked_matrixmul_DD
!    integer :: i, j
!
!    if (size(b) .ne. size(a,1)*size(a,2)) then
!      print*, "MULTIFIELD MODPK: Arrays don't conform."
!      stop
!    end if
!
!    ![ LP: ] B vector to matrix
!    do i=1,size(A,2); do j=1,size(A,1)
!      temp_matrix(i,j)=B((i-1)*size(a,2)+j)
!    end do; end do
!
!    temp_matrix = matmul(A,temp_matrix)
!
!    ![ LP: ] Temp matrix to hacked matrix-vector
!    do i=1,size(A,2); do j=1,size(A,1)
!       hacked_matrixmul_DD((i-1)*size(a,2)+j) =temp_matrix(i,j)
!    end do; end do
!
!  end function hacked_matrixmul_DD

  ![ LP: ] A=double, B=complex
  function hacked_matrixmul_DC(A,B) result(hacked_matrix)
    implicit none

    double precision, dimension(:,:), intent(in) :: A
    complex(kind=dp), dimension(:,:), allocatable :: temp_matrix
    complex(kind=dp), dimension(:), intent(in) :: B
    complex(kind=dp), dimension(:), allocatable :: hacked_matrix
    integer :: i, j

    if (size(b) .ne. size(a,1)*size(a,2)) then
      print*, "MULTIFIELD MODPK: Arrays don't conform."
      stop
    end if

    allocate(hacked_matrix(size(B)))
    allocate(temp_matrix(size(a,1),size(a,2)))

    ![ LP: ] B vector to matrix
    do i=1,size(A,2); do j=1,size(A,1)
      temp_matrix(i,j)=B((i-1)*size(a,2)+j)
    end do; end do

    temp_matrix = matmul(A,temp_matrix)

    ![ LP: ] Temp matrix to hacked matrix-vector
    do i=1,size(A,2); do j=1,size(A,1)
       hacked_matrix((i-1)*size(a,2)+j) =temp_matrix(i,j)
    end do; end do

    deallocate(temp_matrix)

  end function hacked_matrixmul_DC

  ![ LP: ] A=complex, B=complex
!  function hacked_matrixmul_CC(A,B)
!    implicit none
!
!    complex(kind=8), dimension(:,:), intent(in) :: A
!    complex(kind=8), dimension(:,:) :: temp_matrix
!    complex(kind=8), dimension (:), intent(in) :: B
!    complex(kind=8), dimension (:) :: hacked_matrixmul_CC
!    integer :: i, j
!
!    if (size(b) .ne. size(a,1)*size(a,2)) then
!      print*, "MULTIFIELD MODPK: Arrays don't conform."
!      stop
!    end if
!
!    ![ LP: ] B vector to matrix
!    do i=1,size(A,2); do j=1,size(A,1)
!      temp_matrix(i,j)=B((i-1)*size(a,2)+j)
!    end do; end do
!
!    temp_matrix = matmul(A,temp_matrix)
!
!    ![ LP: ] Temp matrix to hacked matrix-vector
!    do i=1,size(A,2); do j=1,size(A,1)
!       hacked_matrixmul_CC((i-1)*size(a,2)+j) =temp_matrix(i,j)
!    end do; end do
!
!  end function hacked_matrixmul_CC

END MODULE modpk_utils
