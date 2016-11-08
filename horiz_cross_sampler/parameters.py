#!/usr/bin/python

"""Parameters that would change between runs of the horizon crossing sampler.  Variables that should be available for all the threads.  For serial runs or only one MPI process, all parameters are read by the same thread."""

#List of possible observables
poss_observables = ['PR', 'n_s', 'alpha_s',
        'r', 'n_t',
        'f_NL', 'tau_NL']

#Which observables do we want?
#obs_to_calc = ['PR','n_s', 'r','n_t']
#obs_to_calc = ['n_t','r']
obs_to_calc = ['PR', 'n_s', 'n_t']


#How to sample the couplings?



#List of possible hyperparameters
#List in order of [min, max, unit]
#If real number, will create an array between min-max with "unit" of grid points
#If integer, will create an array between min-max with stepsize of unit
#[ LP: ] Should probably also include N_piv...

sampler = "MP"
hyperparams = {
        'nfields':[10,1000,50],
        'beta':[0.5,0.5,1],
        'm_avg':[5e-7,5e-7,1],
        'p':[2,2,1]
        }

#sampler = "uniform"
#hyperparams = {
#        'nfields':[2,10000,10],
#        #'low':[1e-14,1e-14,1],
#        'low':[1e-16,1e-14,1],
#        'high':[1e-13,1e-13,1],
#        'p':[2,2,1]
#        }

#sampler = "log"
#hyperparams = {
#        'nfields':[2,100,1],
#        'low':[-14,-14,1],
#        'high':[-10,-10,1],
#        'p':[2,2,1]
#        }


#Number of sample points to get for each set of hyperparameters
#nsamples=2e7
nsamples=1000

#Should we get less samples with more fields?
scale_nsamples = False

#Output file name "root"
#Will create file called root#.dat where #=mpi_rank
#fileroot = "data/unif_2/outdata"
fileroot = "data/MP/outdata"