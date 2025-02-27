
#ifndef GENERAL_KERNELS_INCLUDED
#define GENERAL_KERNELS_INCLUDED

/*
 * File smc_kernels.cuh contains kernels used by SMC. 
 */

 #include <curand_kernel.h>
 #include "inference/smc/smc.cuh"

/**
 * This function initializes the curandStates.
 * 
 * @param randStates the curandStates, one for each particle, that should be initialized and used in inference.
 * @param numThreads the number of particles used by SMC.
 * @param seed used in curand_init to achieve unique RNG states in nested SMC (set to zero for top-level SMC).
 */
__global__ void initCurandStates(curandState* randStates, int numThreads, int seed);


/**
 * Initializes the next pointers to the first basic block. 
 * 
 * @param particles the particles used by SMC.
 * @param numParticles the number of particles used by SMC.
 * @param firstBblock the first basic block to be exectued
 */
__global__ void initParticlesNext(particles_t particles, int numParticles, pplFunc_t firstBblock);

/**
 * Each thread executes the bblock pointed to by the corresponding particle's next pointer. 
 * 
 * @param randStates the curandStates, one for each particle, that should be used in inference.
 * @param particles the particles used by SMC.
 * @param funcs the array of bblocks that can be executed.
 * @param numParticles the number of particles used by SMC.
 * @param numBblocks the size of the bblock array
 * @param arg argument that are passed to the bblocks when invoking them, often not used and set to NULL. 
 */
__global__ void execFuncs(curandState* randStates, particles_t particles, int numParticles, int numThreads, void* arg);

#endif