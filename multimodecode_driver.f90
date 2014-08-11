program multimodecode
  use modpkparams
  use potential
  use background_evolution
  use modpk_utils
  use camb_interface
  use access_modpk, only : evolve, potinit
  use internals
  use modpk_icsampling
  use modpk_output, only : out_opt
  use modpk_deltaN_SR
  use modpk_observables, only : observables

  implicit none

  !Run-specific input params
  integer :: i, vparam_rows

  !Parallel variables
  integer :: numtasks, rank

  !Cosmology
  real(dp) :: dlnk

  !Sampling parameters for ICs
  integer :: numb_samples
  integer :: out_adiab, out_isoc
  real(dp) :: energy_scale
  real(dp), dimension(:,:), allocatable :: priors_min, priors_max

  !Other sampling params
  real(dp) :: N_pivot_prior_min, N_pivot_prior_max
  logical :: varying_N_pivot
  logical :: more_potential_params
  logical :: get_runningofrunning
  logical :: use_horiz_cross_approx

  integer :: pfile

  !For run-time alloc w/out re-compile
  namelist /init/ num_inflaton, potential_choice, &
    slowroll_infl_end, instreheat, vparam_rows, &
    more_potential_params

  namelist /analytical/ use_deltaN_SR, evaluate_modes, &
    use_horiz_cross_approx

  namelist /ic_sampling_params/ ic_sampling, energy_scale, numb_samples, &
    save_iso_N, N_iso_ref, varying_N_pivot

  namelist /params/ phi_init0, dphi_init0, vparams, &
    N_pivot, k_pivot, dlnk

  namelist /more_params/ effective_V_choice, turning_choice, &
    number_knots_qsfrandom, stand_dev_qsfrandom, &
    knot_range_min, knot_range_max, custom_knot_range

  namelist /print_out/ out_opt, get_runningofrunning

  namelist /technical/ tech_opt

  !------------------------------------------------


  !Read initializing params from file
	open(newunit=pfile, file="parameters_multimodecode.txt", &
    status="old", delim = "apostrophe")
  read(unit=pfile, nml=init)
  read(unit=pfile, nml=analytical)

  call allocate_vars()

  !Read other params from file
	read(unit=pfile, nml=ic_sampling_params)
	read(unit=pfile, nml=params)
	read(unit=pfile, nml=print_out)
	read(unit=pfile, nml=technical)
	close(unit=pfile)

  call output_initial_data()

  if (ic_sampling==ic_flags%reg_samp) then

    call out_opt%open_files(SR=use_deltaN_SR)

    call calculate_pk_observables(k_pivot,dlnk)

  else if &
    !Eqen sampling
    (ic_sampling == ic_flags%eqen_samp .or. &
    !Set vels in SR and fields on iso-N surface for N-quad
    ic_sampling == ic_flags%iso_N .or.&
    !Set vels in SR
    ic_sampling == ic_flags%slowroll_samp .or.&
    !Grab IC from file
    ic_sampling == ic_flags%fromfile_samp .or. &
    !Loop over different vparams for given num_inflaton
    ic_sampling == ic_flags%parameter_loop_samp .or. &
    ic_sampling == ic_flags%param_unif_prior .or. &
    !QSF trajectories
    ic_sampling == ic_flags%qsf_random .or.  &
    ic_sampling == ic_flags%qsf_parametric &
    ) then

    call out_opt%open_files(ICs=.true., SR=use_deltaN_SR)

    !Initialize the sampler
    call init_sampler(priors_min, priors_max)

    do i=1,numb_samples

      if (out_opt%modpkoutput) write(*,*) &
        "---------------------------------------------"
      if (out_opt%modpkoutput) write(*,*) &
        "Sample numb", i, "of", numb_samples
      if (out_opt%modpkoutput) write(*,*) &
        "---------------------------------------------"

      call calculate_pk_observables(k_pivot,dlnk)

    end do

  else
    print*, "ERROR: sampling technique",ic_sampling,"not implemented."
    stop
  end if

  contains

    subroutine get_full_pk(pk_arr,pk_iso_arr,calc_full_pk)

      real(dp), dimension(:,:), allocatable, intent(out) :: pk_arr
      real(dp), allocatable, optional, intent(out) :: pk_iso_arr(:,:)

      real(dp) :: kmin, kmax, incr
      logical, intent(inout) :: calc_full_pk
      real(dp) :: p_scalar, p_tensor, p_zeta, p_iso
      real(dp), dimension(:), allocatable :: k_input
      integer :: i, steps, u

      type(power_spectra) :: pk

      namelist /full_pk/ kmin, kmax, steps, calc_full_pk

	    open(newunit=u, file="parameters_multimodecode.txt", &
        status="old", delim = "apostrophe")
      read(unit=u, nml=full_pk)
      close(u)

      !If don't want full spectrum, return
      if (.not. calc_full_pk) return

      !Make the output arrays
      if (allocated(pk_arr)) deallocate(pk_arr)
      if (allocated(pk_iso_arr) .and. present(pk_iso_arr)) &
        deallocate(pk_iso_arr)
      allocate(pk_arr(steps, 2))
      if (present(pk_iso_arr)) allocate(pk_iso_arr(steps, 2))
      pk_arr=0e0_dp
      if (present(pk_iso_arr)) pk_iso_arr=0e0_dp

      !Make the arrays for k values to sample
      allocate(k_input(steps))
      incr=(kmax/kmin)**(1/real(steps-1,kind=dp))
      do i=1,steps
        k_input(i) = kmin*incr**(i-1)
      end do

      do i=1,steps
        call evolve(k_input(i), pk)

        pk_arr(i,:)=(/k_input(i),pk%adiab/)
        if (present(pk_iso_arr)) pk_iso_arr(i,:)=(/k_input(i),pk%isocurv/)

      end do

    end subroutine get_full_pk

    subroutine allocate_vars()

      !Prepare extra params if necessary
      if (more_potential_params) then
        allocate(turning_choice(num_inflaton-1))
        allocate(number_knots_qsfrandom(num_inflaton-1))
        allocate(stand_dev_qsfrandom(num_inflaton-1))
        allocate(knot_range_min(num_inflaton-1))
        allocate(knot_range_max(num_inflaton-1))

        read(unit=pfile, nml=more_params)

      end if

      !Model dependent
      if (potential_choice==8) then
        allocate(vparams(1,4))
      else
        allocate(vparams(vparam_rows,num_inflaton))
      end if
      allocate(priors_max(2,num_inflaton))
      allocate(priors_min(2,num_inflaton))

      allocate(phi_init0(num_inflaton))
      allocate(phi_init(num_inflaton))
      allocate(phidot_sign(num_inflaton))
      allocate(phiarr(num_inflaton, 1:nsteps))
      allocate(dphiarr(num_inflaton, 1:nsteps))
      allocate(param_arr(1:nsteps))
      allocate(phi_infl_end(num_inflaton))
      allocate(phi_pivot(num_inflaton))
      allocate(dphi_pivot(num_inflaton))
      allocate(dphi_init0(num_inflaton))
      allocate(dphi_init(num_inflaton))

    end subroutine allocate_vars

    subroutine output_observables(pk_arr, pk_iso_arr,&
        calc_full_pk, &
        observ_modes, observ_SR)

      type(observables), intent(in), optional :: observ_modes
      type(observables), intent(in), optional :: observ_SR
      real(dp), dimension(:,:), intent(in) :: pk_arr
      real(dp), dimension(:,:), intent(in), optional :: pk_iso_arr

      type(observables) :: SR_pred

      logical :: calc_full_pk

      integer :: i

      if (present(observ_SR)) then
        SR_pred = observ_SR
      else
        call SR_pred%set_zero()
      end if

      !Background stats

      if (.not. out_opt%output_reduced) then
        do i=1,size(vparams,1)
          print*, "vparams", vparams(i,:)
        end do
      end if

      write(*, out_opt%i_fmt) &
        "Number of Inflaton =", num_inflaton
      write(*, out_opt%i_fmt) &
        "Potential Choice =", potential_choice
      if (potential_choice == 14 .or. potential_choice==15) then
        write(*, out_opt%i_fmt) &
          "Turning Choice =", turning_choice
      end if
      write(*, out_opt%e_fmt) &
        "N_pivot =", N_pivot
      write(*, out_opt%e_fmt) &
        "phi_pivot =", phi_pivot(:)
      if (potential_choice==1) then
        write(*, out_opt%e2_fmt)&
          "N_tot =", N_tot,'(', &
          0.25e0_dp*sum(phi_init0**2) , ')'
      else
        write(*, out_opt%e2_fmt)&
          "N_tot =", N_tot
      end if


      !Mode stats

      if (.not. evaluate_modes) then
        write(*, out_opt%e2_fmt)&
          "Ps =", SR_pred%As
        if (potential_choice==1) then
          write(*, out_opt%e2_fmt)&
            "r = Pt/Ps =", SR_pred%r, '(', 8.0/N_pivot, ')'
        else if (potential_choice==16) then
          write(*, out_opt%e2_fmt)&
            "r = Pt/Ps =", SR_pred%r, '(', 4.0*vparams(2,1)/N_pivot, ')'
        end if
        write(*, out_opt%e2_fmt)&
          "n_s =", SR_pred%ns
        write(*, out_opt%e2_fmt)&
          "n_t =", SR_pred%nt
        write(*, out_opt%e2_fmt)&
          "r/n_t =", -(8.0-SR_pred%r/2.0)
        write(*, out_opt%e2_fmt)&
          "alpha_s =", SR_pred%alpha_s
        write(*, out_opt%e2_fmt)&
          "f_NL =", SR_pred%f_NL
        write(*, out_opt%e2_fmt)&
          "tau_NL =", SR_pred%tau_NL, &
          '(>', ((6.0/5.0)*SR_pred%f_NL)**2, ')'

        return
      end if

      write(*, out_opt%e2_fmt)&
        "Ps =", observ_modes%As, '(', SR_pred%As , ')'
      write(*, out_opt%e2_fmt),&
        "Isocurvature P =", observ_modes%A_iso
      write(*, out_opt%e2_fmt),&
        "Pnad P =", observ_modes%A_pnad
      write(*, out_opt%e2_fmt),&
        "Entropy P =", observ_modes%A_ent
      write(*, out_opt%e2_fmt),&
        "Cross Ad-Iso P =", observ_modes%A_cross_ad_iso
      write(*, out_opt%e2_fmt),&
        "Bundle Width =", field_bundle%exp_scalar
      write(*, out_opt%e2_fmt)&
        "r = Pt/Ps =", observ_modes%r, '(', SR_pred%r, ')'

      if (potential_choice==1 .or. potential_choice==15) then
        write(*, out_opt%e2_fmt)&
          "r (m^2 phi^2) =", observ_modes%r, '(', 8.0/N_pivot, ')'
      end if

      write(*, out_opt%e2_fmt)&
        "n_s =", observ_modes%ns, '(', SR_pred%ns,')'
      if (num_inflaton>1) then
        write(*, out_opt%e2_fmt)&
          "n_iso =",  observ_modes%n_iso
        write(*, out_opt%e2_fmt)&
          "n_pnad =", observ_modes%n_pnad
        write(*, out_opt%e2_fmt)&
          "n_ent =",  observ_modes%n_ent
      end if
      write(*, out_opt%e2_fmt)&
        "n_t =", observ_modes%nt, '(', SR_pred%nt , ')'
      write(*, out_opt%e2_fmt)&
        "r/n_t =", observ_modes%r/observ_modes%nt, '(', -(8.0-observ_modes%r/2.0) , ')'
      write(*, out_opt%e2_fmt)&
        "alpha_s =", observ_modes%alpha_s, '(', SR_pred%alpha_s , ')'
      if (get_runningofrunning) then
        write(*, out_opt%e2_fmt)&
          "d^2n_s/dlnk^2 =", observ_modes%runofrun
      end if
      write(*, out_opt%e2_fmt)&
        "Slow-roll f_NL =", observ_modes%f_NL
      write(*, out_opt%e2_fmt)&
        "Slow-roll tau_NL =", observ_modes%tau_NL, &
        '(>', ((6.0/5.0)*observ_modes%f_NL)**2, ')'

      if (calc_full_pk .and. evaluate_modes) then

        !Open output files
        open(newunit=out_adiab,file="out_pk_adiab.txt")
        open(newunit=out_isoc, file="out_pk_isocurv.txt")

        do i=1,size(pk_arr,1)
          write(out_adiab,*) pk_arr(i,:)
          if(present(pk_iso_arr)) write(out_isoc,*) pk_iso_arr(i,:)
        end do
        write(*,*) "Adiab P(k) written to out_pk_adiab.txt"
        if (present(pk_iso_arr))&
          write(*,*) "Iso-P(k) written to out_pk_isocurv.txt"
      end if

    end subroutine output_observables

    subroutine output_initial_data()
      integer :: i

      call out_opt%formatting(num_inflaton)

      do i=1, size(vparams,1)
        if (out_opt%modpkoutput .and. .not. out_opt%output_reduced) &
          write(*, '(A8,I1,A5,100E12.3)'),&
          "vparams(",i,",:) =", vparams(i,:)
      end do

    end subroutine output_initial_data


    !Calculate observables, optionally grab a new IC each time called
    subroutine calculate_pk_observables(k_pivot,dlnk)

      real(dp), intent(in) :: k_pivot,dlnk
      real(dp), dimension(:,:), allocatable :: pk_arr, pk_iso_arr
      logical :: calc_full_pk, leave

      type(power_spectra) :: pk0, pk1, pk2, pk3, pk4
      type(observables) :: observs, observs_SR

      pk_bad=0
      leave = .false.

      !DEBUG
      !Get vparams
      !if (

      !Get ICs
      if (ic_sampling/=ic_flags%reg_samp) then
        call get_ic(phi_init0, dphi_init0, ic_sampling, &
          priors_min, priors_max, &
          numb_samples,energy_scale)

        if (varying_N_pivot) then
          save_iso_N = .false.
          call get_new_N_pivot(N_pivot,&
            N_pivot_prior_min, N_pivot_prior_max)
        end if

      end if

      !Load ics
      allocate(observs%ic(2*num_inflaton))
      observs%ic(1:num_inflaton)=phi_init0
      observs%ic(num_inflaton+1:2*num_inflaton)=dphi_init0
      if (use_deltaN_SR) then
        allocate(observs_SR%ic(2*num_inflaton))
        observs_SR%ic = observs%ic
      end if

      !Initialize potential and calc background
      call potinit

      !For outputting field values at horiz crossing
      if (out_opt%fields_horiz) &
        write(out_opt%fields_h_out,'(1000E28.20)') k, phi_pivot

      call test_bad(pk_bad, observs, leave)
      if (leave) return

      if (use_deltaN_SR) then

        call calculate_SR_observables(observs_SR)

        !Only calculating these in SR
        observs%f_NL = observs_SR%f_NL
        observs%tau_NL = observs_SR%tau_NL

      end if

      !Evaluate the mode functions
      if (evaluate_modes) then

        call evolve(k_pivot, pk0)
          call test_bad(pk_bad, observs, leave)
          if (leave) return
!DEBUG
!print*, "Not evaluating second and third evolve routines"
!stop
        call evolve(k_pivot*exp(-dlnk), pk1)
          call test_bad(pk_bad, observs, leave)
          if (leave) return
        call evolve(k_pivot*exp(dlnk), pk2)
          call test_bad(pk_bad, observs, leave)
          if (leave) return

        if (get_runningofrunning) then
          !Alpha_s from 5-pt stencil
          !or running of running
          call evolve(k_pivot*exp(-2.0e0_dp*dlnk), pk3)
            call test_bad(pk_bad, observs, leave)
            if (leave) return
          call evolve(k_pivot*exp(2.0e0_dp*dlnk), pk4)
            call test_bad(pk_bad, observs, leave)
            if (leave) return
        end if

        !Construct the observables
        if (get_runningofrunning) then
          call observs%set_finite_diff(dlnk, &
            pk0,pk1,pk2,pk3,pk4, &
            field_bundle%exp_scalar)
        else
          call observs%set_finite_diff(dlnk, &
            pk0,pk1,pk2,&
            bundle_width=field_bundle%exp_scalar)
        end if


        !Get full spectrum for adiab and isocurv at equal intvs in lnk
        call get_full_pk(pk_arr,pk_iso_arr,calc_full_pk)

      end if

      if (out_opt%modpkoutput) then
        if (evaluate_modes) then
          call output_observables(pk_arr,pk_iso_arr, &
            calc_full_pk, observs, observs_SR)
        else
          call output_observables(pk_arr,pk_iso_arr, &
            calc_full_pk, observ_SR = observs_SR)
        end if
      end if

      !Print output array
      !Only get the SR arrays if use_deltaN_SR
      !Only print observs if evaluated modes
      if (out_opt%output_badic .or. pk_bad/=bad_ic) then
        if (evaluate_modes) &
          call observs%printout(out_opt%outsamp)
        if (use_deltaN_SR) &
          call observs_SR%printout(out_opt%outsamp_SR)
      end if

      if (save_iso_N) then
        observs%ic(1:num_inflaton) = phi_iso_N
        observs%ic(num_inflaton+1:2*num_inflaton) = dphi_iso_N
        if (use_deltaN_SR) &
          observs_SR%ic(1:num_inflaton) = phi_iso_N
        if (use_deltaN_SR) &
          observs_SR%ic(num_inflaton+1:2*num_inflaton) = dphi_iso_N

        if (out_opt%output_badic .or. pk_bad/=bad_ic) then
          if (evaluate_modes) &
            call observs%printout(out_opt%outsamp_N_iso)
          if (use_deltaN_SR) &
            call observs_SR%printout(out_opt%outsamp_N_iso_SR)
        end if
      end if

    end subroutine calculate_pk_observables

    !Calculate observables for the power spectrum, as well as fNL, using the
    !delta-N formalism in slow-roll
    subroutine calculate_SR_observables(observs_SR)
      use modpk_numerics, only : locate, array_polint, polint
      type(observables), intent(inout) :: observs_SR
      integer :: j, i
      real(dp) :: ah, alpha_ik, dalpha, N_end, del_N, Npiv_renorm
      real(dp), dimension(num_inflaton) :: phi_pivot, phi_end, del_phi

      !Find field values at end of inflation
      !Note that eps=1 perhaps twice, so take the last one.
      call array_polint(epsarr(nactual_bg-4:nactual_bg),&
        phiarr(:,nactual_bg-4:nactual_bg),&
        1.0e0_dp,  phi_end, del_phi)
      call polint(epsarr(nactual_bg-4:nactual_bg),&
        lna(nactual_bg-4:nactual_bg),&
        1.0e0_dp,  N_end, del_N)

      !Find field values at horizon crossing
      Npiv_renorm = N_end - N_pivot

      i= locate(lna(1:nactual_bg), Npiv_renorm)
      j=min(max(i-(4-1)/2,1),nactual_bg+1-4)
      call array_polint(lna(j:j+4), phiarr(:,j:j+4),&
        Npiv_renorm, phi_pivot, del_phi)

      if (use_horiz_cross_approx) then
        HC_approx=.true.
      else
        HC_approx=.false.
      end if

      call observs_SR%set_zero()
      observs_SR%As = PR_SR(phi_pivot,phi_end)
      observs_SR%ns = ns_SR(phi_pivot,phi_end)
      observs_SR%nt = nt_SR(phi_pivot)
      observs_SR%r  = r_SR(phi_pivot,phi_end)
      observs_SR%f_NL  = fnl_SR(phi_pivot,phi_end)
      observs_SR%tau_NL  = taunl_SR(phi_pivot,phi_end)
      observs_SR%alpha_s  = alpha_s_SR(phi_pivot,phi_end)

    end subroutine calculate_SR_observables


    !Check if an IC had some properties where we declare it to be unphysical
    subroutine test_bad(pk_bad,observ,leave)

      integer,  intent(in)     :: pk_bad
      logical,  intent(inout)  :: leave
      type(observables) :: observ

      !NB: If pk_bad==4, then ode_underflow
      if (pk_bad==bad_ic .or. pk_bad==4) then
        call observ%set_zero()

        !Flag for voiding calculation
        leave = .true.
      end if

    end subroutine test_bad

    subroutine init_sampler(priors_min, priors_max)
      use modpk_rng, only : init_random_seed

      real(dp), dimension(:,:), intent(out) :: priors_min, &
        priors_max

      real(dp), dimension(:), allocatable :: phi0_priors_min, &
        dphi0_priors_min, phi0_priors_max, dphi0_priors_max

      integer :: u, i

      namelist /priors/ phi0_priors_min, phi0_priors_max, &
        dphi0_priors_min, dphi0_priors_max, &
        N_pivot_prior_min, N_pivot_prior_max

	    !Set random seed
	    call init_random_seed()

      if (allocated(phi0_priors_max)) then
        print*, "ERROR: Priors allocated before initialization."
        stop
      else
        allocate(phi0_priors_max(num_inflaton))
        allocate(dphi0_priors_max(num_inflaton))
        allocate(phi0_priors_min(num_inflaton))
        allocate(dphi0_priors_min(num_inflaton))
        phi0_priors_min=0e0_dp
        phi0_priors_max=0e0_dp
        dphi0_priors_min=0e0_dp
        dphi0_priors_max=0e0_dp
      end if

      if (save_iso_N) then
        allocate(phi_iso_N(num_inflaton))
        allocate(dphi_iso_N(num_inflaton))
      end if

      !Read phi0 priors from file
	    open(newunit=u, file="parameters_multimodecode.txt", &
        status="old", delim = "apostrophe")
      read(unit=u, nml=priors)
      close(u)

      priors_max(1,:) = phi0_priors_max
      priors_max(2,:) = dphi0_priors_max
      priors_min(1,:) = phi0_priors_min
      priors_min(2,:) = dphi0_priors_min

    end subroutine init_sampler

end program multimodecode
