#include <cuda_runtime.h>
#include <stdio.h>
#include <stdlib.h>
#include <assert.h>
extern "C" {
#include "utils.h"
}

    /* gets last cuda error and if it's not a cudaSuccess
     * prints debug information on stderr and aborts */
#define cudaCheckErrors(msg) \
    do { \
        cudaError_t __err = cudaGetLastError(); \
        if (__err != cudaSuccess) { \
            fprintf(stderr, "Fatal error: %s (%s at %s:%d)\n", \
                    msg, cudaGetErrorString(__err), \
                    __FILE__, __LINE__); \
            exit(1); \
        } \
    } while (0)

    //TODO: change it with nvidia's function
    /* Determines the number of threads per block.
     * Returns a power of 2 number that evenly divides the total number of elements*/
    int find_thread_count(const int dim) {
        if (dim == 0) return 0;
        int result = 2;
        while ((dim % result == 0) && (result < 1024)) result *= 2;
        return result >> 1;
    }

    __global__ void cuda_compute(int* d_help, const int* d_table, int N) {
        const int cell_id = blockIdx.x * blockDim.x + threadIdx.x;
        const int j = cell_id % N;
        const int i = (cell_id - j) / N;

        const int left = (i - 1 + N) % N;
        const int right = (i + 1) % N;
        const int up = (j - 1 + N) % N;
        const int down = (j + 1) % N;

        const int alive_neighbors = d_table[POS(left , up)] +
                                    d_table[POS(left , j)] +
                                    d_table[POS(left , down)] +
                                    d_table[POS(i    , up)] +
                                    d_table[POS(i    , down)] +
                                    d_table[POS(right, up)] +
                                    d_table[POS(right, j)] +
                                    d_table[POS(right, down)] ;
        if (cell_id < N * N)
            d_help[cell_id] = (alive_neighbors == 3) || (alive_neighbors == 2 && d_table[cell_id]) ? 1 : 0;
    }

    int main(int argc, char** argv) {
        if (argc < 3) {
            printf("usage: %s FILE dimension\n", argv[0]);
            exit(1);
        }

        int n_runs;
        if (argc == 4) n_runs = atoi(argv[3]);
        else n_runs = DFL_RUNS;

        const int N = atoi(argv[2]);
        const int total_elements = N * N;
        const int mem_size = total_elements * sizeof(int);

        char* filename = argv[1];
        int* table;
        fprintf(stderr, "Reading %dx%d table from file %s\n", N, N, filename);
        table = (int*) malloc(mem_size);
        read_from_file(table, filename, N, N);
        fprintf(stderr,"Finished reading table\n");

        int t_count = find_thread_count(total_elements);
        dim3 thread_count(t_count);
        dim3 blocks_count(total_elements / t_count);

        int* d_help, *d_table;
        cudaMalloc((void**) &d_help,  mem_size);
        cudaCheckErrors("malloc fail");

        cudaMalloc((void**) &d_table, mem_size);
        cudaCheckErrors("malloc fail");

        cudaMemcpy(d_table, table, mem_size, cudaMemcpyHostToDevice);
        cudaCheckErrors("memcpy fail");

        float time;
        cudaEvent_t start, stop;
        cudaEventCreate(&start) ;
        cudaEventCreate(&stop) ;
        cudaEventRecord(start, 0) ;

        for (int i = 0; i < n_runs; ++i) {
            cuda_compute <<< blocks_count, thread_count >>>(d_help, d_table, N);
            cudaCheckErrors("compute fail");
            swap(&d_table, &d_help);
        }

        cudaEventRecord(stop, 0) ;
        cudaEventSynchronize(stop) ;
        cudaEventElapsedTime(&time, start, stop) ;
        printf("%f\n", time);

        cudaMemcpy(table, d_table, total_elements * sizeof(int), cudaMemcpyDeviceToHost);
        cudaDeviceReset();
        save_table(table, N, N, "cuda-results.bin");
    }
