#ifndef MACROS_INCLUDED
#define MACROS_INCLUDED

/*
 * File macros.cuh defines macros that acts as an interface to the SMC framework.
 * These macros helps define the intermediate language RootPPL, in which the models are programmed. 
 * 
 * Short summary of how some of the most fundamental macros are used in models:
 *
 * - INIT_MODEL (mandatory) will set up globally accessible bblocks, takes the program state type and the number of bblocks as argument
 * - BBLOCK_DATA (optional) will set up globally accessible data
 * - BBLOCK will set up function that define the model together with other BBLOCK:s. 
 * - MAIN will set up main function and some necessary variables. 
 * - INIT_BBLOCK with BBLOCK function (defined with BBLOCK macro) as argument for each BBLOCK
 * - SMC with callback as argument to start inference
 * - Result (currently only normalizationConstant) available through local variable "res" in MAIN
 */

#include <fstream>
#include <string>
// #include "utils/misc.cuh"
#include "macros_adaptive.cuh"

#ifdef __NVCC__
#include "utils/cuda_error_utils.cuh"
#endif

// Using a macro for "," is unfortunately necessary for some longer lists within bblocks. For example when doing array initialization.
#define COMMA ,
#define CMA ,

// Convenient
#define MIN(a, b) a <= b ? a : b
#define MAX(a, b) a >= b ? a : b

// To be able to switch between single and double precision easily.
typedef double floating_t; 

// Used to achieve parameter overloading in macros
#define GET_MACRO(_1, _2, _3, NAME,...) NAME

// Sets up globally accessible bblock array, that can be accessed from the bblocks, and defines the type used in the model.
#define INIT_MODEL(progStateType) \
typedef progStateType progStateTypeTopLevel_t;

#define INIT_MODEL_STACK() \
typedef progStateStack_t progStateTypeTopLevel_t;


/***    BBLOCKS    ***/

// Used by BBLOCK, BBLOCK_HELPER and BBLOCK_CALL macros.
#define BBLOCK_PARAMS(progStateType) RAND_STATE_DECLARE particles_t& particles, int particleIdx
#define BBLOCK_ARGS RAND_STATE particles, particleIdx

// Declarations of BBLOCK and BBLOCK_HELPER functions.
#define BBLOCK_DECLARE(funcName) DEV void funcName(RAND_STATE_SIGNATURE particles_t&, int, void*);
#define BBLOCK_HELPER_DECLARE(funcName, returnType, ...) \
DEV returnType funcName(RAND_STATE_SIGNATURE particles_t&, int, ##__VA_ARGS__);

// template <typename T> \

// These will be executed by the framework. 
#define BBLOCK_DEF(funcName, progStateType, body) \
DEV void funcName(BBLOCK_PARAMS(progStateType), void* arg = NULL) \
body \
DEV_POINTER(funcName, progStateType)
// Handles parameter overloading
#define BBLOCK(...) GET_MACRO(__VA_ARGS__, BBLOCK_DEF, BBLOCK_DEF_NO_TYPE)(__VA_ARGS__)
#define BBLOCK_DEF_NO_TYPE(funcName, body) BBLOCK_DEF(funcName, progStateTypeTopLevel_t, body)

// Something like this could be used to count number bblocks during compile time. 
// const char dummy ## funcName = __COUNTER__;

// Regular helper functions that takes the particles as argument (syntactic sugar).
#define BBLOCK_HELPER(funcName, body, returnType, ...) \
DEV returnType funcName(BBLOCK_PARAMS(progStateTypeTopLevel_t), ##__VA_ARGS__) \
body

// template <typename T> \

// Call functions that takes the particles as argument (syntactic sugar).
#define BBLOCK_CALL(funcName, ...) funcName(BBLOCK_ARGS, ##__VA_ARGS__)

// Jump directly to a BBLOCK without adding a new stack frame.
// TODO Current implementation is identical to BBLOCK_CALL, but it would be
// nice to change this.
#define BBLOCK_JUMP(funcName, ...) funcName(BBLOCK_ARGS, ##__VA_ARGS__)

// Declares array global data with CUDA managed memory to handle transfers between host and device. 
#define BBLOCK_DATA_MANAGED(pointerName, type, n) MANAGED type pointerName[n];

// Declares global data with CUDA managed memory to handle transfers between host and device.
#define BBLOCK_DATA_MANAGED_SINGLE(name, type) MANAGED type name;


/***    *****    ***/


/***    Access particles from BBLOCKS    ***/

// Add log-weight to the particle.
#define WEIGHT(w) particles.weights[particleIdx] += w

// Access particle program counter (bblock index).
// #define PC particles.pcs[particleIdx]
// #define NEXT ((pplFunc_t*)particles.next)[particleIdx]
#define NEXT particles.next[particleIdx]

// Access the particle's program/model specific state. Uses the top-level program state type.
#define PSTATE static_cast<progStateTypeTopLevel_t*>(particles.progStates)[particleIdx]

// Access the array of progStates, should not be used by particles, but in callbacks for example. Uses the top-level program state type.
#define PSTATES static_cast<progStateTypeTopLevel_t*>(particles.progStates)

// Access the particle's program/model specific state.
#define PSTATE_TYPE(progStateType) static_cast<progStateType*>(particles.progStates)[particleIdx]

// Access the array of progStates, should not be used by particles, but in callbacks for example. 
#define PSTATES_TYPE(progStateType) static_cast<progStateType*>(particles.progStates)

// Access the array of weights, should not be used by particles, but in callbacks for example.
#define WEIGHTS particles.weights
/***    *****    ***/


// Main function with default number of particles, prints the normalization constant.
#define MAIN(body) \
int main(int argc, char** argv) { \
    initGen(); \
    double res = 0; \
    body \
    freeGen(); \
    return 0; \
}

// Functions that can be called from the framework, usually to use resulting particle distributions before clean up.
#define CALLBACK(funcName, body) void funcName(particles_t& particles, int N, void* arg=NULL) body
#define CALLBACK_NESTED(funcName, progStateType, body, arg) DEV void funcName(particles_t& particles, int N, arg) body

// Define the first BBLOCK that should be executed in inference. The model itself then defines the order of BBLOCK execution. 
#define FIRST_BBLOCK(funcName) \
pplFunc_t funcName ## Host; \
FUN_REF(funcName, progStateTypeTopLevel_t) \
pplFunc_t firstBblock = funcName ## Host;


// Samples from distributions, which should all take the curandState as argument first if compiled for GPU.
#define SAMPLE(distName, ...) distName(RAND_STATE __VA_ARGS__ )

// Condition on cond. Sets weight to negative infinity if condition is not met. 
#define CONDITION(cond) if(! (cond)) WEIGHT(-INFINITY)

// Observe value from distribution. Conceptually, this is equivalent to drawing a value from the distribution
// and conditioning on it being equal to the passed value. Technically, it weights with the score at point value.
// This macro should be called like this: OBSERVE(distName, distArgs, value)
#define OBSERVE(distName, ...) WEIGHT(distName ## Score(__VA_ARGS__))


// Run SMC with callback function (optional, can be declared with CALLBACK macro).
#define SMC(callback) \
int numParticles = 10000; \
if(argc > 1) { \
    numParticles = atoi(argv[1]); \
} \
int numRuns = 1; \
if(argc > 2) { \
    numRuns = atoi(argv[2]); \
} \
int ompThreads = -1; \
if(argc > 3) { \
    ompThreads = atoi(argv[3]); \
} \
int particlesPerThread = 1; \
if(argc > 4) { \
    particlesPerThread = atoi(argv[4]); \
} \
prepareSMC(); \
for(int i = 0; i < numRuns; i++) \
    res = runSMC(firstBblock, numParticles, ompThreads, particlesPerThread, sizeof(progStateTypeTopLevel_t), callback); \
finishFilesSMC();

/*** Nested SMC, not as thoroughly developed as top-level SMC ***/

// Prepare bblock array for initialization of bblocks, for nested inference only.
#define SMC_PREPARE_NESTED(progStateType, numBblocks) \
pplFunc_t* bblocks = new pplFunc_t[numBblocks]; /*{}*/ \
int bbIdx = 0;

/* 
Run the nested inference with arguments:
- progStateType: The program state used by particles/bblocks in nested inference.
- numParticles: the number of particles to use in the nested inference. 
- parallelExec: boolean, whether new CUDA-kernels should be launched for nested inference, otherwise just run sequentially (on GPU threads if top-level inference runs on the GPU).
- parallelResampling: boolean, whether new CUDA-kernels should be launched for nested resampling, otherwise run sequential variant (on GPU threads if top-level inference runs on the GPU).
- parentIndex: the index of the current thread, used to seed curand
- callback: Callback function to use resulting particle distribution before clean up.
- retStruct: structure to fill with result in callback (passed to callback, handled by model, just passed by framework).
- arg: argument to nested inference bblocks.
*/
#define SMC_NESTED(progStateType, numParticles, parallelExec, parallelResampling, parentIndex, callback, retStruct, arg) \
int numBblocks = bbIdx; \
double res = runSMCNested(RAND_STATE bblocks, numBblocks, numParticles, sizeof(progStateType), \
    parallelExec, parallelResampling, parentIndex, callback, (void*)&retStruct, (void*)arg); \
delete[] bblocks;

#endif

