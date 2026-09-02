/* ALAKAZAM_TFCE  Exact threshold-free cluster enhancement, in C.
 *
 *   SCORE = alakazam_tfce(VALS, EDGES, E, H)
 *
 *   VALS   Nlin x 1 double, already rectified (>= 0); only strictly
 *          positive entries take part.
 *   EDGES  M x 2 int32, 1-based indices into VALS, each row one undirected
 *          edge of the vertex-by-time lattice.
 *   E, H   TFCE extent and height exponents (FieldTrip's tfce_E, tfce_H).
 *
 *   A LINE-BY-LINE PORT of local_etfce in FieldTrip's private/tfcestat.m,
 *   which is the exact-TFCE kernel and, measured, ~98% of a source cluster
 *   permutation run. The algorithm is a component tree built by union-find
 *   over nodes visited in descending value order; nothing here is a
 *   cleverer method, only the same method without the interpreter between
 *   each scalar operation.
 *
 *   TIE-BREAKING IS PART OF THE CONTRACT. MATLAB's sort is stable, so equal
 *   values keep ascending index order, and which of two equal nodes is
 *   visited first decides which becomes a component's root. The comparator
 *   below therefore breaks ties by ascending index rather than leaving it
 *   to qsort, and the edge scan is a counting sort (stable by
 *   construction) rather than a comparison sort. Without both, results
 *   would differ from FieldTrip's on tied values, which is exactly the
 *   kind of discrepancy that would not show up until someone compared two
 *   analyses of the same data.
 */
#include "mex.h"
#include <math.h>
#include <stdlib.h>
#include <string.h>

static const double *g_nodeval;

static int cmp_desc(const void *a, const void *b)
{
    int ia = *(const int *)a, ib = *(const int *)b;
    double va = g_nodeval[ia], vb = g_nodeval[ib];
    if (va > vb) return -1;
    if (va < vb) return  1;
    return (ia < ib) ? -1 : 1;   /* stable: ascending index on ties */
}

void mexFunction(int nlhs, mxArray *plhs[], int nrhs, const mxArray *prhs[])
{
    if (nrhs != 4)
        mexErrMsgIdAndTxt("Alakazam:tfce:nrhs", "Four inputs required: vals, edges, E, H.");
    if (!mxIsDouble(prhs[0]) || mxIsComplex(prhs[0]))
        mexErrMsgIdAndTxt("Alakazam:tfce:vals", "VALS must be real double.");
    if (!mxIsInt32(prhs[1]))
        mexErrMsgIdAndTxt("Alakazam:tfce:edges", "EDGES must be int32.");

    const double *vals = mxGetPr(prhs[0]);
    mwSize Nlin = mxGetNumberOfElements(prhs[0]);
    const int *edges = (const int *) mxGetData(prhs[1]);
    mwSize M = mxGetM(prhs[1]);
    if (mxGetN(prhs[1]) != 2)
        mexErrMsgIdAndTxt("Alakazam:tfce:edges", "EDGES must be M x 2.");
    double Eexp = mxGetScalar(prhs[2]);
    double Hexp = mxGetScalar(prhs[3]);

    plhs[0] = mxCreateDoubleMatrix((mwSize) Nlin, 1, mxREAL);
    double *score = mxGetPr(plhs[0]);

    /* active = vals > 0; nodeid maps linear index -> 1..N (0 = inactive) */
    int *nodeid = (int *) mxCalloc(Nlin, sizeof(int));
    mwSize i, N = 0;
    for (i = 0; i < Nlin; i++)
        if (vals[i] > 0.0) nodeid[i] = (int) (++N);
    if (N == 0) { mxFree(nodeid); return; }

    int *activeIdx = (int *) mxMalloc(N * sizeof(int));
    double *nodeval = (double *) mxMalloc(N * sizeof(double));
    for (i = 0; i < Nlin; i++) {
        if (nodeid[i]) {
            int n = nodeid[i] - 1;
            activeIdx[n] = (int) i;
            nodeval[n]   = vals[i];
        }
    }

    /* Keep edges with both endpoints active. MATLAB filters first and then
     * concatenates, so the doubled list is [all kept ea; all kept eb] --
     * replicated here because a stable sort over it preserves that order. */
    int *ea = (int *) mxMalloc(M * sizeof(int));
    int *eb = (int *) mxMalloc(M * sizeof(int));
    mwSize m, K = 0;
    for (m = 0; m < M; m++) {
        int a = nodeid[edges[m] - 1];
        int b = nodeid[edges[M + m] - 1];
        if (a && b) { ea[K] = a - 1; eb[K] = b - 1; K++; }
    }

    /* CSR adjacency by counting sort over src = [ea; eb], dst = [eb; ea]. */
    mwSize twoK = 2 * K;
    int *cnt = (int *) mxCalloc(N + 1, sizeof(int));
    for (m = 0; m < K; m++) { cnt[ea[m]]++; cnt[eb[m]]++; }
    mwSize *startp = (mwSize *) mxMalloc((N + 1) * sizeof(mwSize));
    startp[0] = 0;
    for (i = 0; i < N; i++) startp[i + 1] = startp[i] + (mwSize) cnt[i];
    mwSize *fill = (mwSize *) mxMalloc(N * sizeof(mwSize));
    for (i = 0; i < N; i++) fill[i] = startp[i];
    int *dst = (int *) mxMalloc((twoK ? twoK : 1) * sizeof(int));
    for (m = 0; m < K; m++) dst[fill[ea[m]]++] = eb[m];
    for (m = 0; m < K; m++) dst[fill[eb[m]]++] = ea[m];
    mxFree(fill); mxFree(cnt); mxFree(ea); mxFree(eb);

    /* order: nodes by descending value, ties by ascending index */
    int *order = (int *) mxMalloc(N * sizeof(int));
    for (i = 0; i < N; i++) order[i] = (int) i;
    g_nodeval = nodeval;
    qsort(order, N, sizeof(int), cmp_desc);
    int *rnk = (int *) mxMalloc(N * sizeof(int));
    for (i = 0; i < N; i++) rnk[order[i]] = (int) i;

    int    *ufp   = (int *)    mxMalloc(N * sizeof(int));
    double *csize = (double *) mxMalloc(N * sizeof(double));
    int    *croot = (int *)    mxMalloc(N * sizeof(int));
    int    *hpar  = (int *)    mxMalloc(N * sizeof(int));
    double *ext   = (double *) mxMalloc(N * sizeof(double));
    for (i = 0; i < N; i++) { ufp[i] = (int) i; csize[i] = 1.0; croot[i] = (int) i; hpar[i] = (int) i; ext[i] = 1.0; }

    mwSize p;
    for (p = 0; p < N; p++) {
        int node = order[p];
        mwSize s = startp[node], e = startp[node + 1];
        int ri = node, a, t;
        while (ufp[ri] != ri) ri = ufp[ri];
        a = node; while (ufp[a] != ri) { t = ufp[a]; ufp[a] = ri; a = t; }

        mwSize k;
        for (k = s; k < e; k++) {
            int j = dst[k], rj, cr;
            if ((mwSize) rnk[j] >= p) continue;
            rj = j;
            while (ufp[rj] != rj) rj = ufp[rj];
            a = j; while (ufp[a] != rj) { t = ufp[a]; ufp[a] = rj; a = t; }
            if (rj == ri) continue;
            cr = croot[rj]; hpar[cr] = node;
            if (csize[ri] >= csize[rj]) {
                ufp[rj] = ri; csize[ri] += csize[rj]; croot[ri] = node;
            } else {
                ufp[ri] = rj; csize[rj] += csize[ri]; croot[rj] = node; ri = rj;
            }
        }
        ext[node] = csize[ri];
    }

    double *T = (double *) mxMalloc(N * sizeof(double));
    double c = 1.0 / (Hexp + 1.0), H1 = Hexp + 1.0;
    for (p = N; p-- > 0; ) {
        int node = order[p], u = hpar[node];
        if (u == node)
            T[node] = c * pow(ext[node], Eexp) * pow(nodeval[node], H1);
        else
            T[node] = T[u] + c * pow(ext[node], Eexp) *
                      (pow(nodeval[node], H1) - pow(nodeval[u], H1));
    }
    for (i = 0; i < N; i++) score[activeIdx[i]] = T[i];

    mxFree(T); mxFree(ext); mxFree(hpar); mxFree(croot); mxFree(csize); mxFree(ufp);
    mxFree(rnk); mxFree(order); mxFree(dst); mxFree(startp);
    mxFree(nodeval); mxFree(activeIdx); mxFree(nodeid);
}
