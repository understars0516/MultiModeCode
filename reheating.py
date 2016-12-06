####################################################################
####################################################################
####################################################################
################									################
################			REHEATING CODE			################
################			 						################
################			draft version. 			################
################			 						################
####################################################################
####################################################################
####################################################################

import numpy as np
import csv
import math
import collections
from scipy import interpolate
from scipy.integrate import odeint


global inflaton_number
global maxstep
global index_phi
global index_dphi
global index_radn
global index_matter
global index_hubble
global gamma_sorted_index
global index_range
#################################################################
#---ADDED SINCE--------------------------------------------------
#-----------------------ADDED TO THE PART BELOW------------------
#----------------------------------------------------------------
#################################################################

fundamentals = collections.namedtuple('fundamentals',('M_pl','c'))
fundamentals.M_pl = 1.0
fundamentals.c = 1.0


#################################################################
#---part 1-------------------------------------------------------
#--------------End of inflation IC definitions-------------------
#----------------------------------------------------------------
#################################################################
reheater = collections.namedtuple('reheater',('phi_infl_end',
											  'dphi_infl_end',
											  'c_ij_avg',
											  'eps_pivot',
											  'eta_pivot',
											  'P_inf_end',
											  'Gamma_i',
											  'efolds_end',
											  'h_end',
											  'vparams'))

#################################################################
#---part 1.1.1---------------------------------------------------
#------------Definition of the reheating objects-----------------
#----------------------------------------------------------------
#################################################################
evolve_with_N = collections.namedtuple('evolve_with_N',('phi',
														'dphidN',
														'hubble',
														'dhubble',
														'rho_fields',
														'rho_radn',
														'rho_matter',
														'efolds_end',
														'eps',
														'eta',
														'gamma',
														'fields_decayed',
														'not_decayed',
														'fields_decay_order',
														'rho_radn_decay',
														'rho_matter_decay',
														'rho_matter_temp',
														'rho_radn_temp',
														'hubble_temp',
														'save_decay',
														'r_ij',
														'W_i',
														'dN_i',
														'n_s',
														'r_T',
														'eta_ij',
														'P_Xi',
														'h_end',
														'x_1',
														'x_2',
														'remain',
														'flag_down',
														'evolve_with_log'))

oscillation_counter = collections.namedtuple('oscillation_counter',('last_position',
																	'counter',
																	'init_count',
																	'total_osc'))

#################################################################
#---part 1.1.2---------------------------------------------------
#-----------Definition of the reheating functions----------------
#----------------------------------------------------------------
#################################################################
def reheat_getH_with_radn(vparams,phi,dphidN,rho_radn):
	############################################################
	#
	#
	#	H = \sqrt( (\rho_\gamma + V(\phi) )/ (3.0-0.5\sum( (dphi/dN)**2 )))
	#
	#
	############################################################
	rho_sum = np.sum(rho_radn)
	hubble = np.sqrt((rho_sum + potential(vparams,phi))
					 /(3.0-0.5*np.sum(dphidN**2)))
	return hubble;

def reheat_getdH_with_radn(vparams,phi,dphidN,rho_radn,gamma):
	############################################################
	#
	#			(3.0-\eps)*(\sum(dV*(dphi/dN))-4.0*\rho_\gamma
	#				+(\sum(\gamma_i*\rho_\phi)))-(V+\rho_\gamma)
	#					*(\sum((dphi/dN)**2 * (3.0+\gamma_i/H))
	#						+(\sum(dphi/dN)*dV/H**2))
	#	dH/dN = -----------------------------------------
	#			2.0*H*(3.0-\eps)**2+(2.0*\eps/H)*(V+\rho_\gamma)
	#
	############################################################
	rho_sum = sum(rho_radn)
	hubble = reheat_getH_with_radn(vparams,phi,dphidN,rho_radn)
	eps = getEps(dphidN)
	rho_fields = 0.5*hubble**2*dphidN**2+V_i_sum_sep(vparams,phi)
	V = potential(vparams,phi)
	dV = dVdphi(vparams,phi)
	denom = 2.0 * hubble * (3.0-eps)**2 + (2.0 * eps / hubble) * (V + np.sum(rho_radn))
	numer = ((3.0-eps) * (np.sum(dV * dphidN)
						  -4.0*rho_radn + np.sum(gamma * rho_fields))-
			 (V + np.sum(rho_radn))*
			 (np.sum( dphidN**2 * (3.0+gamma/hubble)
					 )+np.sum(dphidN * dV / hubble**2)))
	dhubble = numer/denom
	return dhubble;

def getEta(vparams,phi):
	eta = np.zeros((inflaton_number,inflaton_number),dtype='float')
	############################################################
	#
	#	\eta_ij = d(m2_V_i\phi_i)/dphi_j = diag(m2_V)_ij
	#
	############################################################
	m2_V = 10.0**vparams
	V = potential(vparams,phi)
	print "\sum potential ", V
	for i in range(0,inflaton_number):
		eta[i,i] = m2_V[i] / V
	return eta

def getEps(dphidN):
	############################################################
	#
	#	\eps = 1/2 * M_pl^2 * (dphi/dN)\cdot(dphi/dN)
	#
	############################################################
	eps = 0.5*(1.0)**2*np.dot(dphidN,dphidN)
	return eps;

def potential(vparams,phi):
	############################################################
	#Random sampling for mass values in MODECODE is as follows:
	#!Some inspiration for these priors from 1112.0326
	#
	#!Masses: m^2 = 10**vparams(1,:)
	#vparams_priors_min(1,:) = -13.5e0_dp
	#vparams_priors_max(1,:) = -8.0e0_dp
	#
	#!Intxn:  lambda^4 = 10**vparams(2,:)
	#vparams_priors_min(2,:) = -20.0e0_dp
	#vparams_priors_max(2,:) = -10.0e0_dp
	#
	#do i=1,size(vparams,1); do j=1,size(vparams,2)
	#	call random_number(rand)
	#	vparams(i,j) = (vparams_priors_max(i,j)-vparams_priors_min(i,j))*rand + &
	#		vparams_priors_min(i,j)
	#	end do; end do
	# I incorparate this in the vparam generate function below.
	############################################################
	############################################################
	#
	#	V = 1/2 * \sum( m_i * \phi_i^2 )
	#
	############################################################
	m2_V = 10.0**vparams
	V_potential = 0.5*np.sum(m2_V*phi**2)
	return V_potential;


def V_i_sum_sep(vparams,phi):
	############################################################
	#Random sampling for mass values in MODECODE is as follows:
	#!For a sum-separable potential V=\sum_i V_i.  This returns only the V_i part
	#!For sum-separable potentials with different potential for each field, have
	#!to put this in by hand.
	#
	#!The idea: make temp copy of vparams; change vparams as if it had only the
	#!one field; get V; restore vparams
	#!NB: vparams(vrows,num_inflaton)
	#
	#vrows = size(vparams,1)
	#
	#allocate(vparams_temp(size(vparams,1), size(vparams,2)))
    #vparams_temp = vparams
	#
	#do jj=1,size(phi)
	#deallocate(vparams)
	#allocate(vparams(vrows,1))
	#vparams(:,1) = vparams_temp(:,jj)
	#V_i_sum_sep(jj) = pot((/phi(jj)/))
	#end do
	#
	#deallocate(vparams)
	#allocate(vparams(size(vparams_temp,1), size(vparams_temp,2)))
	#vparams = vparams_temp
	#deallocate(vparams_temp)
	#end function V_i_sum_sep
	############################################################
	############################################################
	#
	#	V_i = 1/2 * ( m_i^2 * \phi_i^2 )
	#
	############################################################
	m2_V = 10.0**vparams
	V_i = 0.5*m2_V*phi*phi
	return V_i;


def dVdphi(vparams,phi):
	############################################################
	#
	# Considering simple case where
	#	V  = 0.5 m^2 \phi^2
	#	V' = m^2 \phi
	#
	############################################################
	m2_V = 10.0**vparams
	first_deriv = m2_V*phi
	return first_deriv;


def	get_vparams(reheater,evolve_with_N):
	############################################################
	#
	#	 Setting the random sampling of the parameters
	#	 that relate to the potential as given
	#	 in the Fortran code.
	#
	############################################################
	#
	#vparams_priors_min = np.empty((2,inflaton_number),dtype=float)
	#vparams_priors_max = np.empty((2,inflaton_number),dtype=float)
	#
	#vparams_priors_min[0,:] = -13.5*np.ones(inflaton_number)
	#vparams_priors_max[0,:]	= -8.0*np.ones(inflaton_number)
	#
	#vparams_priors_min[1,:] = -20.0*np.ones(inflaton_number)
	#vparams_priors_max[1,:] = -10.0*np.ones(inflaton_number)
	#
	reheater.vparams = np.empty((2,inflaton_number),dtype=float)
	#for i in range(0,2):
	#	for j in range(0,inflaton_number):
	#		reheater.vparams[i,j]=((vparams_priors_max[i,j]-
	#							   vparams_priors_min[i,j]
	#							   )*np.random.random()
	#							   )+vparams_priors_min[i,j]
	############################################################
	#
	#	 Temporarily override the random generated potential terms
	#	 to be equal to the correct values generated by the modecode.
	#
	############################################################
	reheater.vparams[0,:]=	np.array([1.0000000000000000, 1.0526315799999999,
							 1.1052631600000000, 1.1578947399999999,
							 1.2105263200000000, 1.2631578900000000,
							 1.3157894699999999, 1.3684210500000000,
							 1.4210526299999999, 1.4736842100000000,
							 1.5263157900000000, 1.5789473700000001,
							 1.6315789500000000, 1.6842105300000001,
							 1.7368421100000000, 1.7894736800000000,
							 1.8421052600000001, 1.8947368400000000,
							 1.9473684200000001, 2.0000000000000000])

#################################################################
#-----------------------ADDED THE PART BELOW---------------------
#  Numerically calculating evolution with NO SUDDEN DECAY (nsd).
#----------------------------------------------------------------
#################################################################
def calc_derivs_nsd(y,x,oc,reheat):

	y_prime = np.empty(y.size,dtype=float)
	#################################################################
	#
	#							f(y) = y'
	#
	#################################################################
	y_prime[index_hubble] = 0.0

	phi = y[index_phi]
	dphidN = y[index_dphi]
	
	eps = getEps(dphidN)

	if (eps > 3.0):
		print "Instable value as \phi(", eps , ") >= 3.0 "

	else:
		gamma = np.zeros(inflaton_number,dtype='float')
		gamma[np.nonzero(oc.counter)] = reheater.Gamma_i[np.nonzero(oc.counter)]

		rho_radn = y[index_radn]
		
		if np.all(oc.counter > 5 ):
			

			y_prime[index_phi] = 0.0
			y_prime[index_dphi] = 0.0

			rho_fields = np.zeros(inflaton_number,dtype='float')
			rho_fields = np.exp(y[index_matter])
			
			rho_matter = np.zeros(inflaton_number,dtype='float')
			rho_matter = np.exp(y[index_matter])
			
			hubble = np.sqrt(np.sum(rho_fields + rho_radn)/3.0)


			y_prime[index_matter] = np.zeros(inflaton_number,dtype='float')
			y_prime[index_matter]= - 3.0 - gamma/hubble
			
			y_prime[index_radn] = -4.0*rho_radn + rho_fields * gamma/hubble

		else:

			rho_radn = y[index_radn]

			hubble 	= reheat_getH_with_radn(reheat.vparams[0,:],
										phi,
										dphidN,
										rho_radn)
			dhubble	= reheat_getdH_with_radn(reheat.vparams[0,:],
										 phi,
										 dphidN,
										 rho_radn,
										 gamma) # MAKE SURE THIS IS OK
		
			rho_fields = 0.5*(hubble*dphidN)**2+V_i_sum_sep(reheat.vparams[0,:],
														phi)
			
			y_prime[index_phi] = dphidN
			y_prime[index_dphi] = (-(3.0 + gamma/hubble +
									 dhubble/hubble)*dphidN -
							   dVdphi(reheat.vparams[0,:], phi)/hubble**2)
								   
			y[index_matter]	= rho_fields
			
			y_prime[index_matter]	= 0.0 #
			y_prime[index_radn]		= -4.0*rho_radn + rho_fields * gamma/hubble
	
			y_prime[index_radn] = -4.0*rho_radn + rho_fields * gamma/hubble

	return y_prime


#################################################################
#---part A.1-----------------------------------------------------
#----------CALCULATION THE DERIVATIVES OF Y----------------------
#----------------------------------------------------------------
#################################################################
def calc_derivs(y,x,evolve,oc,reheat):
	
	y_prime = np.empty(y.size,dtype=float)
	#################################################################
	#
	#							f(y) = y'
	#
	#################################################################
	evolve.phi = y[index_phi] #define index_phi = 0:inflation
	evolve.dphidN = y[index_dphi]
	
	y_prime[index_hubble] = 0.0

	evolve.eps = getEps(evolve.dphidN)
	#############################################################
	#						STABILITY CHECK
	#				check for eps --> 3.0 since in eqn
	#				H^2 =  V / (3 - eps) , this is bad
	#############################################################
	if (evolve.eps > 3.0):
		print "Instable value as eps = ", evolve.eps , " >= 3.0 for evolve with matter "
	#############################################################
	#					REHEATING STATUS CHECK
	#
	#	        reheating status has to be implemented here
	#############################################################
	else:
		
		evolve.gamma = np.zeros(inflaton_number,dtype='float')
		evolve.gamma[np.nonzero(oc.counter)] = reheater.Gamma_i[np.nonzero(oc.counter)]
		#############################################################
		# ^
		# ^	MIND THAT: WE MUST INITIALIZE THE INTEGRATOR AS WE DO A STIFF SHIFT IN EOM HERE
		# ^
		#############################################################
		
		evolve.rho_radn = y[index_radn]

		#############################################################
		#					Matter fluid approximation
		#
		#				dont evolve: \phi 	= 0.0
		#				and 		dphi/dN = 0.0
		#
		#				evolve:
		#						{\rho_i}_\phi = %exp%( {\rho_i}_matter ) (?)
		#							H	  = \sqrt( \sum(\{\rho_i}_\phi + {\rho_i}_radn)/3.0 )
		#						\dot{{\rho_i}_\matter} = -3.0 - \Gamma_i/H
		#
		#	        	TRUE if all fields begun oscillating
		#
		#############################################################
		if np.all(oc.counter > 1):
			#############################################################
			# ^
			# ^	MIND THAT: WE MUST INITIALIZE THE INTEGRATOR AS WE DO A STIFF SHIFT FROM KG HERE
			# ^
			#############################################################
			y_prime[index_phi] = 0.0
			y_prime[index_dphi] = 0.0

			#############################################################
			#
			# 		 		 This is additional to the MODECODE:
			#	 ||		If a field has gone through the sudden decay,
			#	 ||		set the energy density in the field to be zero
			#	 \/		as all the energy for that field will now be radiation.
			#			Alse do not evolve the matter energy density for that field.
			#
			#############################################################
			evolve.rho_fields = np.zeros(inflaton_number,dtype='float')
			evolve.rho_fields = np.exp(y[index_matter])
			
			evolve.rho_matter = np.zeros(inflaton_number,dtype='float')
			evolve.rho_matter = np.exp(y[index_matter])

			#evolve.rho_fields = np.zeros(inflaton_number,dtype='float')
			#evolve.rho_fields[evolve.not_decayed] = np.exp(y[index_matter])[evolve.not_decayed]
			#evolve.rho_matter = np.zeros(inflaton_number,dtype='float')
			#evolve.rho_matter[evolve.not_decayed] = np.exp(y[index_matter])[evolve.not_decayed]
			#############################################################
			# ^
			# ^	NOT SURE: IF I SHOULD JUST EQUAL \rho_fields TO ZERO HERE INSTEAD
			# ^
			#############################################################
			
			#############################################################
			#  ||
			#  ||	THIS NEEDS CORRECTION
			#  \/
			#############################################################
			y_prime[index_matter] = np.zeros(inflaton_number,dtype='float')
			y_prime[index_matter] = - 3.0 - evolve.gamma/evolve.hubble
			#y_prime[index_matter] = np.zeros(inflaton_number,dtype='float')
			#y_prime[index_matter[evolve.not_decayed]]= - 3.0 - evolve.gamma[evolve.not_decayed]/evolve.hubble
			#print "y_prime[index_matter[evolve.not_decayed]] = " , y_prime[index_matter[evolve.not_decayed]]

			#############################################################
			#for i in range(0,inflaton_number):
			#	if evolve.fields_decayed[i]:
			#		evolve.rho_fields[i] = 0.0
			#		evolve.rho_matter[i] = 0.0
			#		print "index_matter[",i,"] = ", index_matter[i]
			#		y[index_matter[i]] = 0.0
			#		y_prime[index_matter[i]] = 0.0
			#		print "decayed field " , i , " set rho_fields to zero for this field. "
			#	else:
			#		evolve.rho_fields[i] = np.exp(y[index_matter[i]]) # still more to improve around here.
			#		y_prime[index_matter[i]]= - 3.0 - evolve.gamma[i]/evolve.hubble
			#		print "index_matter[",i,"] = ", index_matter[i]
			#############################################################
			
			evolve.hubble = np.sqrt(np.sum(evolve.rho_fields + evolve.rho_radn)/3.0)
		
		#############################################################
		#			   Derivatives w.t.r. (KG) equations in N
		#
		#		\ddot{\phi}_i = -(3.0*H + \Gamma_i)*\dot{\phi}_i-dVdphi
		#
		#	{d^2\phi_i}/{dN^2} = - (1 / H) (dH/dN) (d{phi_i}/dN)
		#							- (3 + \gamma_i/ H)({dphi_i}/dN) - m_i \phi /H
		#
		#		where I'll be using: 	dVdphi = m_i*\phi_i
		#
		#					\dot{\rho_i}_\matter = 0.0
		#
		#############################################################
		else:
			
			evolve.hubble 	= reheat_getH_with_radn(reheat.vparams[0,:],
													evolve.phi,
													evolve.dphidN,
													evolve.rho_radn)
			evolve.dhubble	= reheat_getdH_with_radn(reheat.vparams[0,:],
													 evolve.phi,
													 evolve.dphidN,
													 evolve.rho_radn,
													 evolve.gamma)
			# MAKE SURE THIS IS OK

			evolve.rho_fields = 0.5*(evolve.hubble *
									 evolve.dphidN)**2 + V_i_sum_sep(reheat.vparams[0,:],
																				 evolve.phi)
		
			y_prime[index_phi] = evolve.dphidN
			y_prime[index_dphi] = (-(3.0 + evolve.gamma/evolve.hubble +
									 evolve.dhubble/evolve.hubble)*evolve.dphidN -
								   dVdphi(reheat.vparams[0,:],evolve.phi)/evolve.hubble**2)
								   
			y_prime[index_matter] = 0.0

		######################### DEBUGGING #########################
		#
		#			checking the KG equations being satisfied
		#
		#	masses	= 10.0**reheater.vparams[0,:]
		#	value 	= y_prime[index_dphi[:]]+(3.0+evolve.gamma[:]/evolve.hubble+evolve.dhubble[:]
		#	evolve.hubble)*y_prime[index_phi[:]]+masses[:]*y[index_phi[:]]/evolve.hubble**2
		#	assert any(value < 1E-3), "the KG equation is NOT satisfied by 1E-3"
		#
		#############################################################

		#############################################################
		#
		#		\dot{\rho_i}_\gamma  = -4.0*{\rho_i}_\gamma + \Gamma_i*\rho_\phi / H
		#
		#############################################################
		y_prime[index_radn] = -4.0*evolve.rho_radn + evolve.rho_fields * evolve.gamma/evolve.hubble


		#############################################################
		#
		#		calculating the derivate w.r.t the logarithm of the rho_fields if the value is very small.
		#
		#############################################################
		#if ( not evolve.radn_withlog and np.min(evolve.rho_matter) < 1e-8 ):
		#	evolve.radn_withlog = True
		#if( evolve.withlog = True )

	#print "yprime = " ,y_prime
	return y_prime


#################################################################
#---part A.2-----------------------------------------------------
#-------------COUNTING THE OSCILLATIONS OF THE FIELDS------------
#----------------------------------------------------------------
#################################################################
def oscillation_count(oc,evolve):

	for i in range(0,inflaton_number): # NOT SURE IF I FIXED THIS!
		if  (  ((evolve.phi[i] >  0.0) and (oc.last_position[i] <  0.0))
			or ((evolve.phi[i] <  0.0) and (oc.last_position[i] >  0.0))
			or ((evolve.phi[i] >  0.0) and (oc.last_position[i] <  0.0))
			or ((evolve.phi[i] <  0.0) and (oc.last_position[i] >  0.0))):
			oc.counter[i] = oc.counter[i] + 1
	oc.last_position = evolve.phi

#################################################################
#---part A.3-----------------------------------------------------
#----------MAKING REHEATING CHECKS AND MANIPULATIONS-------------
#----------------------------------------------------------------
#################################################################
def reheating_checks(reheat,evolve,oc,y):

	evolve.phi		= y[index_phi]
	evolve.dphidN	= y[index_dphi]

	last_counter	= oc.counter
	oscillation_count(oc,evolve)

	evolve.rho_radn = y[index_radn]
	
	#############################################################
	#
	# 		Interpolation parameters for sudden decay manipulations below.
	#
	#############################################################
	hubble_vector	= np.empty(2,dtype='float')
	rho_matrix		= np.empty((inflaton_number,2),dtype='float')
	
	#############################################################
	#
	#		Checking for whether to start the fluid evolutions rather than KG's
	#
	#############################################################
	check_eps = False
	use_fluid_equations = False
	use_fluid_equations_first_time = False

	if np.any(last_counter == 0) :
		check_eps = getEps(evolve.dphidN) > 2.9

	if (np.all(oc.counter > 1) or check_eps or max_Gamma > 1.2*evolve.hubble):
		use_fluid_equations = True
	if use_fluid_equations and not np.all(oc.last_counter > 1):
		use_fluid_equations_first_time = True

	#############################################################
	#
	#		If (starting to) evaluate fluid evolution equations rathen than KG's
	#
	#############################################################
	if ( use_fluid_equations ):
		if ( use_fluid_equations_first_time ):
			if ( check_eps or max_Gamma > 1.2*evolve.hubble):
				oc.counter = oc.counter + 2 # ~Hack~ if have to decay quite early.

			#############################################################
			#
			#	H = \sqrt{ (\rho_\gamma + V(\phi))/(3.0 - 0.5*\sum((dphi/dN)^2)) }
			#	\rho_\phi = 0.5 * H**2 *(dphi/dN)**2 + V(\phi_i)
			#
			#############################################################
			evolve.hubble = reheat_getH_with_radn(reheater.vparams[0,:],
												  evolve.phi,
												  evolve.dphidN,
												  evolve.rho_radn)
												  
			evolve.rho_fields = 0.5*(evolve.hubble *
									 evolve.dphidN)**2 + V_i_sum_sep(reheater.vparams[0,:],
																	 evolve.phi)

			#############################################################
			#
			#	Begin evolving the scalar sector as matter fluid with \Gamma coupled to radiation fluid
			#
			#############################################################
			y[index_matter] = np.log(evolve.rho_fields)
			evolve.rho_matter = evolve.rho_fields

			use_fluid_equations_first_time = False


		oc.last_counter = oc.counter
		#################################################################
		#---part 3-------------------------------------------------------
		#-------------------SUDDEN DECAY APPROXIMATION-------------------
		#----------------------------------------------------------------
		#################################################################

		evolve.hubble = np.sqrt(np.sum(evolve.rho_matter) + np.sum(evolve.rho_radn)/3.0)

		#############################################################
		#
		#	Initialize temp. parameters and only use \rho_matter rather than \rho_fields
		#
		#############################################################
		if (np.count_nonzero(evolve.rho_matter_temp) == 0):
			evolve.rho_matter_temp = evolve.rho_fields
		if (np.count_nonzero(evolve.rho_radn_temp) == 0):
			evolve.rho_radn_temp = evolve.rho_radn
		if (evolve.hubble_temp == 0):
			evolve.hubble_temp = evolve.hubble

		evolve.save_decay = np.zeros(inflaton_number,dtype=bool) #may be wrong here!
		#############################################################
		#
		#	Using the fluid equations, check if any field ready to decay \Gamma_i <= H
		#
		#############################################################
		for j in range(0,inflaton_number):
			#############################################################
			#
			# 		If the field is decaying for the first time, we save:
			#	 	energy density in the fields and radiation at the decay time
			#	 	for this field as a vector. We use polynomial interpoation on
			#	 	this time to get a more accurate value.
			#
			#############################################################
			#############################################################
			#
			#	At the paper 1311.3972v2 --> The t_dec values are calculated when the
			#	matter (scalar field) energy density are equal to the
			#	radiation (decay product) energy density when doing the numerical
			#	simulations. I implement that approach here in order to produce
			#	similar plots as the Figs 4,5 in 1311.3972v2.
			#
			#	NOTE: this requires evolving the matter fluid approx. already.
			#
			#############################################################
			#if ( evolve.hubble <= evolve.gamma[j] ):
			if ( evolve.rho_matter[j] <= evolve.rho_radn[j] ):
				if not evolve.fields_decayed[j]:
					evolve.save_decay[j] = True

					hubble_vector[0] = evolve.hubble_temp
					hubble_vector[1] = evolve.hubble

					rho_matrix[:,0] = evolve.rho_matter_temp
					rho_matrix[:,1] = evolve.rho_matter

					for k in range(0,inflaton_number):
						evolve.rho_matter_decay[k,j] = interpolate.barycentric_interpolate(hubble_vector,
																						   rho_matrix[k,:],
																						   evolve.gamma[j])
					
					rho_matrix[:,0] = evolve.rho_radn_temp
					rho_matrix[:,1] = evolve.rho_radn
					

					for k in range(0,inflaton_number):
						evolve.rho_radn_decay[k,j] = interpolate.barycentric_interpolate(hubble_vector,
																						 rho_matrix[k,:],
																						evolve.gamma[j])
					

			else :
				evolve.fields_decayed[j] = False
				evolve.save_decay[j]	 = False
		
		

		evolve.rho_matter_temp	= evolve.rho_matter
		evolve.rho_radn_temp	= evolve.rho_radn
		evolve.hubble_temp		= evolve.hubble

		#############################################################
		#
		#	Calculate the r_ij variable for a field that has just decayed
		#
		#############################################################
		for j in range(0,inflaton_number):
			if evolve.save_decay[j]:
				
				evolve.r_ij[:,j] = (3.0*(evolve.rho_radn_decay[:,j] + evolve.rho_matter_decay[:,j])
									 /np.sum(4.0*(evolve.rho_radn_decay[:,j] +
												  evolve.rho_matter_decay[:,j])*(evolve.fields_decayed) +
											 3.0*(evolve.rho_radn_decay[:,j] +
												  evolve.rho_matter_decay[:,j])*(evolve.fields_decayed == False)))
				
				evolve.fields_decayed[j]	 = True
				evolve.fields_decay_order[j] = np.count_nonzero(evolve.fields_decayed)


		evolve.not_decayed = np.nonzero(evolve.fields_decayed == False)
		#############################################################
		#
		#	Set here what \rho_matter is equivalent to.
		#
		#############################################################
		#############################################################
		#
		# 	new 		 This is addiational to the MODECODE:
		#	 ||		For the decayed field, rho matter is 0.0 .
		#	 ||		Correcting for the exponential here by setting
		#	 \/		it to zero by hand if the field has decayed.
		#
		#############################################################
		evolve.rho_matter = np.zeros(inflaton_number,dtype='float')
		evolve.rho_matter[evolve.not_decayed] = np.exp(y[index_matter])[evolve.not_decayed]

		print "evolve.rho_matter[evolve.not_decayed] = " , evolve.rho_matter[evolve.not_decayed]
		#############################################################
		#
		#	If all fields have decayed, calculate the W_i and leave.
		#
		#############################################################
		if all(evolve.fields_decayed) and evolve.flag_down:
			
			#############################################################
			#
			#	At this point the fields are ordered w.r.t. how they take position in the
			#	arbitrary fields vector. Definition of W_i depends on how the fields ordered
			#	w.r.t. when they suddenly decayed into radiation at H <= \Gamma_i. This is
			#	achieved by reorderding the r_ij matrix w.r.t. when the fields decayed. Once
			#	the correct W_i's for each field is calculated, one realigns this vector to
			#	match the fields's arbitrary order in the rest of the code.
			#
			#############################################################
			r_ij_proper = np.empty((inflaton_number,inflaton_number),dtype='float')
			
			for i in range(0,inflaton_number):
				for j in range(0,inflaton_number):
					r_ij_proper[(evolve.fields_decay_order[i]-1),
								(evolve.fields_decay_order[j]-1)] = evolve.r_ij[i,j]

			#############################################################
			#
			#	Calculate the a vector as defined in the paper. (check)
			#
			#############################################################
			a_vector = np.empty(inflaton_number,dtype='float')

			a_vector[0] = 1.0
			for j in range(1,inflaton_number):
				a_sum	= 0.0
				for k in range(0,j):
					a_sum	= a_sum + a_vector[k]*r_ij_proper[(inflaton_number-1)-j,(inflaton_number-1)-k]
				a_vector[j] = a_sum / 3.0

			#############################################################
			#
			#	Calculate the W_i as defined in the paper. (check)
			#
			#############################################################
			for i in range(0,inflaton_number): #	CORRECT THIS
				W_sum	= 0.0
				for j in range(0,inflaton_number): #	CORRECT THIS
					W_sum  = W_sum + a_vector[j] * r_ij_proper[i,(inflaton_number-1)-j]
				evolve.W_i[i] = W_sum

			#############################################################
			#
			#	Reordering of the vector W_i to align it with the field vector.
			#
			#############################################################
			W_temp = evolve.W_i
			for i in range(0,inflaton_number):
				evolve.W_i = W_temp[index_range]
			print gamma_sorted_index
			evolve.flag_down = False
			#############################################################
			#
			#	Leave iterating the field equations since all the fields have decayed.
			#
			#############################################################
			#print "evolve.W_i = " , evolve.W_i
			#print "sum evolve.W_i = " , np.sum(evolve.W_i)
			#print "order : " , evolve.fields_decay_order
			#print "gamma : " , evolve.gamma
			#	evolve.remain = False # <---- INSTEAD, WILL GO ON A WHILE FOR PLOTTING PURPOSES.

			#################################################################
			#---ADDED SINCE--------------------------------------------------
			#-----------------------ADDED TO THE PART BELOW------------------
			#----------------------------------------------------------------
			#################################################################
			#############################################################
			#
			#	Calculating the power spectrum and other observables of interest.
			#
			#############################################################

			#############################################################
			#
			#			Following also Ewan's & Layne's notes
			#
			#			Xi_i(t_N,x) = \sum_i^N W_i 		* Xi_i(t_osc,x)
			#			  Xi(t_N,x) = \sum_i^N N_,i(t_N) * dphi_i(t_*,x)
			#			 N_,i(t_N) = \sum_j^N W_j 		* C_ji(t_osc)
			#
			#			Observables are then:
			#				  P_Xi  = P_* \sum_i^N (N_,i)^2
			#			  n_Xi - 1  = -2 eps_* - 2/( \sum_i (N_,i)^2 )
			#								* [ 1 - \sum_ij eta*_ij N_,i N_,j ]
			#				  r_T  = 8 P_* / P_Xi
			#
			#############################################################
			#
			#		In the code: N_,i  = evolve.dN_i[:]
			#					eta*_ij  = reheat.eta_end_inf
			#					eps_*	   = reheat.eps_end_inf
			#					k^3P_Xi = evolve.P_Xi
			#					k^3P_* = reheat.P_inf_end
			#
			#############################################################

			for i in range(0,inflaton_number):
				evolve.dN_i[i] = np.sum( evolve.W_i[:] * reheat.c_ij_avg[i,:] )

			dN2_sum		= np.sum(evolve.dN_i**2)
			evolve.P_Xi = reheat.P_inf_end * dN2_sum

			print "dN**2 = " , dN2_sum

			sum_Neta = 0.0
			for i in range(0,inflaton_number):
				for j in range(0,inflaton_number):
					sum_Neta = sum_Neta + reheat.eta_pivot[i,j]*evolve.dN_i[i]*evolve.dN_i[j]

			print " sum_Neta = " , sum_Neta

			evolve.n_s = 1.0 -  2.0 * reheat.eps_pivot - (2.0 / dN2_sum) * (1.0 - sum_Neta )
			evolve.r_T = 8.0 * reheat.P_inf_end / evolve.P_Xi

			print "evolve.dN_i = " , evolve.dN_i
			print "evolve.n_s = " , evolve.n_s
			print "evolve.r_T = " , evolve.r_T




#################################################################
#---part 1.2-----------------------------------------------------
#--------Take multimodecode data from end of inflation-----------
#----------------------------------------------------------------
#################################################################
############# MUCH TO IMPROVE (ESPECIALLY) HERE #################
############# MUCH TO IMPROVE (ESPECIALLY) HERE #################
reheat_IC_data_file		= np.loadtxt('out_reheaterfile.txt')
reheater.phi_infl_end	= reheat_IC_data_file[0]
reheater.dphi_infl_end	= reheat_IC_data_file[1]
reheater.Gamma_i		= reheat_IC_data_file[2]

inflaton_number = reheater.phi_infl_end.size
reheater.vparams = np.empty((2,inflaton_number),dtype=float)

#reheater.Gamma_i		= reheater.Gamma_i*(reheater.vparams[0,:]**4)#+np.random.random(inflaton_number)*0.0001376
#################################################################

#################################################################
#reheater.c_ij_avg		= np.transpose(reheat_IC_data_file[3:(3+inflaton_number)])
#reheater.vparams[0,:]	= reheat_IC_data_file[(3+inflaton_number)]
#reheater.phi_pivot		= reheat_IC_data_file[(4+inflaton_number)]
#reheater.c_ij_avg		= np.transpose(reheat_IC_data_file[3:(3+inflaton_number)])
reheater.c_ij_avg		= np.zeros((inflaton_number,inflaton_number))
reheater.vparams[0,:]	= reheat_IC_data_file[3]
reheater.phi_pivot		= reheat_IC_data_file[4]
#################################################################

#################################################################
#reheater.c_ij_avg		= reheat_IC_data_file[3::]
reheater.efolds_end 	= 91.690
############# MUCH TO IMPROVE (ESPECIALLY) HERE #################
############# MUCH TO IMPROVE (ESPECIALLY) HERE #################

inflaton_number = reheater.phi_infl_end.size

#################################################################
#	Was here in case if had to fix for Fortran matrix format.
#print "reheater.c_ij_avg before : " , reheater.c_ij_avg
#reheater.c_ij_avg = np.reshape(reheater.c_ij_avg,
#							   (inflaton_number,inflaton_number),
#							   order='F')
#print "reheater.c_ij_avg after : " , reheater.c_ij_avg
#################################################################

index_phi		= np.array(range(0,inflaton_number))
index_dphi		= np.array(range(inflaton_number,2*inflaton_number))
index_radn		= np.array(range((2*inflaton_number+1),(3*inflaton_number+1)))
index_matter	= np.array(range((3*inflaton_number+1),(4*inflaton_number+1)))
index_hubble	= 2*inflaton_number

aux_constaints = 0


y = np.empty(inflaton_number + inflaton_number + 1 +
			 inflaton_number + inflaton_number + aux_constaints, dtype=float)
y_init = np.empty(y.size,dtype=float)


# Setting up the integration bounds in N
evolve_with_N.x_1 = reheater.efolds_end
evolve_with_N.x_2 = evolve_with_N.x_1 + 100.0

x_last = evolve_with_N.x_1

evolve_with_N.remain = True
evolve_with_N.flag_down = True

#################################################################
#
#				Initializing sudden decay parameters
#
#################################################################
evolve_with_N.fields_decayed		= np.zeros(inflaton_number,dtype=bool)
evolve_with_N.fields_decay_order	= np.zeros(inflaton_number, dtype=np.int)
evolve_with_N.rho_radn_decay		= np.zeros((inflaton_number,inflaton_number),dtype='float')
evolve_with_N.rho_matter_decay		= np.zeros((inflaton_number,inflaton_number),dtype='float')
evolve_with_N.r_ij					= np.zeros((inflaton_number,inflaton_number),dtype='float')
evolve_with_N.rho_radn_temp			= np.zeros(inflaton_number,dtype='float')
evolve_with_N.W_i					= np.zeros(inflaton_number,dtype='float')
evolve_with_N.rho_matter_temp		= np.zeros(inflaton_number,dtype='float')
evolve_with_N.save_decay			= np.zeros(inflaton_number,dtype=bool)
evolve_with_N.hubble_temp			= 0.0

#################################################################
#---ADDED SINCE--------------------------------------------------
#----------------------ADDED TO THE PARTS BELOW------------------
#----------------------------------------------------------------
#################################################################
evolve_with_N.dN_i					= np.zeros(inflaton_number,dtype='float')

oscillation_counter.last_counter	= np.zeros(inflaton_number,dtype=np.int)
oscillation_counter.init_count		= np.zeros(inflaton_number,dtype=np.int)
oscillation_counter.counter			= np.zeros(inflaton_number,dtype=np.int)
oscillation_counter.total_osc		= np.zeros(inflaton_number,dtype=np.int)
oscillation_counter.last_position	= reheater.phi_infl_end

evolve_with_N.gamma					= np.zeros(inflaton_number,dtype='float')
evolve_with_N.rho_radn				= np.zeros(inflaton_number,dtype='float')
evolve_with_N.rho_matter			= np.zeros(inflaton_number,dtype='float')

#################################################################
#################################################################
#get_vparams(reheater,evolve_with_N)
#################################################################
#################################################################

nsteps	= 0
maxstep = 6000

x_init	= reheater.efolds_end
x		= np.array([x_init,x_init+0.001])

reheater.Gamma_i	= reheater.Gamma_i/(reheater.vparams[0,:]
										+ (4-3.0*np.random.random(inflaton_number)))**3
index_range			= np.zeros(inflaton_number,dtype='int')
gamma_sorted_index	= reheater.Gamma_i.argsort()

#################################################################
#################################################################
reheater.Gamma_i	= reheater.Gamma_i # * 100
#################################################################
#################################################################


#################################################################
#
#			Sorting the reheating fields with respect to \Gamma
#
#################################################################

for i in range(0,inflaton_number):
	intval = gamma_sorted_index[::-1][i]
	index_range[intval] = i

reheater.phi_infl_end =reheater.phi_infl_end[gamma_sorted_index[::-1]]
reheater.dphi_infl_end = reheater.dphi_infl_end[gamma_sorted_index[::-1]]
reheater.Gamma_i = reheater.Gamma_i[gamma_sorted_index[::-1]]
reheater.vparams[0,:] = reheater.vparams[0,gamma_sorted_index[::-1]]
reheater.phi_pivot = reheater.phi_pivot[gamma_sorted_index[::-1]]

#################################################################
print "reheater.Gamma_i[:] = " , reheater.Gamma_i
#print "gamma_sorted_index[::-1] = " , gamma_sorted_index[::-1]
#print "index_range = " , index_range
#print "reheater after = " , reheater.phi_infl_end
#reheater.phi_infl_end = reheater.phi_infl_end[index_range]
#print "reheater backagain = " , reheater.phi_infl_end
#reheater.phi_infl_end =reheater.phi_infl_end[gamma_sorted_index]
#################################################################

max_Gamma = np.amax(reheater.Gamma_i)

evolve_with_N.phi		= reheater.phi_infl_end
evolve_with_N.dphidN	= reheater.dphi_infl_end
evolve_with_N.hubble	= reheat_getH_with_radn(reheater.vparams[0,:],
												evolve_with_N.phi,
												evolve_with_N.dphidN,
												evolve_with_N.rho_radn)

evolve_with_N.rho_radn	= np.zeros(inflaton_number,dtype='float')
evolve_with_N.rho_matter= np.zeros(inflaton_number,dtype='float')
#evolve_with_N.hubble	= reheater.Gamma_i[0]*100.0

y_init[index_phi]		= reheater.phi_infl_end
y_init[index_dphi]		= reheater.dphi_infl_end
y_init[index_hubble]	= 0.0 #reheat_getH_with_radn(reheater.vparams[0,:],
									#					evolve_with_N.phi,
									#					evolve_with_N.dphidN,
									#					evolve_with_N.rho_radn)
y_init[index_radn]		= evolve_with_N.rho_radn #radiation
y_init[index_matter]	= evolve_with_N.rho_matter #matter

y = y_init

#################################################################
#-----------------------ADDED THE PART BELOW---------------------
#  Numerically calculating evolution with NO SUDDEN DECAY (nsd).
#----------------------------------------------------------------
#################################################################
y_nsd = y_init

#################################################################
#---ADDED SINCE--------------------------------------------------
#-----------------------ADDED THE PART BELOW---------------------
#----------------------------------------------------------------
#################################################################

reheater.eps_pivot = getEps(0)
reheater.eta_pivot = getEta(reheater.vparams[0,:],reheater.phi_pivot)
reheater.P_inf_end = evolve_with_N.hubble**2/4.0*math.pi**2

#####################  PRINTING THE DATA   #####################
#y_file			= open('y_data_reheating_gamma_En1_50.txt','w')
#y_prime_file	= open('y_prime_data_reheating_gamma_En1_40.txt','w')
#rho_fields_file = open('rho_fields_data_reheating_gamma_En1_50.txt','w')
#rho_matter_file = open('rho_matter_data_reheating_gamma_En1_50.txt','w')
#hubble_file		= open('hubble_data_reheating_gamma_En1_50.txt','w')
#y_nsd_file		= open('y_nsd_data_reheating_gamma_En1_50.txt','w')
################################################################
#print "evolve_with_N.phi = " , evolve_with_N.phi
#print "evolve_with_N.dphidN = " , evolve_with_N.dphidN
#print "evolve_with_N.hubble = " , evolve_with_N.hubble
#################################################################
#---part 2-------------------------------------------------------
#-----------------------PERTURBATIVE REHEATING-------------------
#----------------------------------------------------------------
#################################################################

while ( nsteps < maxstep and evolve_with_N.remain ):

	#############################################################
	#						REHEATING CHECKS
	#					(has to be incorporated)
	#					using 'oscillation counters'
	#			decide whether to use matter fluid description
	#			or the KG equations. etc.
	#############################################################
	
	reheating_checks(reheater,
					 evolve_with_N,
					 oscillation_counter,
					 y)
					 
	#############################################################
	#
	#			check whether cacl_derivs gives an OK result!
	#
	#						havent yet done this!
	#
	#############################################################
	#y_prime_test = calc_derivs(y,
	#						   x,
	#						   evolve_with_N,
	#						   oscillation_counter,
	#						   reheater)

	y = odeint(calc_derivs,
			   y,
			   x,
			   args=(evolve_with_N,
					 oscillation_counter,
					 reheater))[1,:]
					 #############################################################
					 #
					 #			TODO: odeint calculations --> check for reheating errors are OK.
					 #
					 #############################################################
	
	#################################################################
	#-----------------------ADDED THE PART BELOW---------------------
	#  Numerically calculating evolution with NO SUDDEN DECAY (nsd).
	#----------------------------------------------------------------
	#################################################################
	y_nsd, info = odeint(calc_derivs_nsd,
				   y_nsd,
				   x ,
				   args=(oscillation_counter,
							 reheater),full_output=True)
	y_nsd = y_nsd[1,:]
	
	print "info.hu  =  " , info['hu'][:]
	print "info.imxer=  " , info['imxer']
	###################  PRINTING THE DATA   ####################
	#np.savetxt(y_file, y ,delimiter=',',newline="\n")
	#np.savetxt(y_prime_file, y_prime_test ,delimiter=',',newline="\n")
	#np.savetxt(rho_fields_file, evolve_with_N.rho_fields, delimiter=',',newline="\n")
	#np.savetxt(rho_matter_file, evolve_with_N.rho_matter, delimiter=',',newline="\n")
	#np.savetxt(y_nsd_file,y_nsd,delimiter=',',newline="\n")
	#############################################################

	x = x + 0.001
	#############################################################
	#
	#			check for eternal inflation
	#
	#			check for inflation started properly (?)
	#
	#			check for evolution stopped properly
	#
	#############################################################
	print nsteps
	nsteps = nsteps + 1

print reheater.Gamma_i
###################  PRINTING THE DATA   ####################
#y_file.close()
#y_prime_file.close()
#rho_fields_file.close()
#hubble_file.close()
#rho_matter_file.close()
#y_nsd_file.close()
#############################################################




