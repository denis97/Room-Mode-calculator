#include "room_mode_solver.h"
#include <cstring>
#include <cmath>
#include <algorithm>
#include <vector>
#include <map>
#include "polygon.h"
#include "polygon_laplacian.h"
#include "polygon_tet_mesh.h"
#include "fem_assembly.h"
#include "fem_lanczos.h"

namespace {

char* dupCString(const char* s) {
    size_t n = std::strlen(s) + 1;
    char* out = new char[n];
    std::memcpy(out, s, n);
    return out;
}

NativeSolveResult* makeError(const char* message) {
    auto* r = new NativeSolveResult();
    std::memset(r, 0, sizeof(NativeSolveResult));
    r->success = 0;
    r->errorMessage = dupCString(message);
    return r;
}

// Maps the UI's resolution slider (same meaning as the voxel grid's
// targetPerAxis) to an FEM refinement level (uniform 1-to-4 subdivisions of
// the ear-clipped triangulation) and extrusion layer count. Heuristic, tuned
// by eye against the star/box benchmarks -- doubling nz with each level keeps
// element aspect ratios reasonable as the horizontal mesh refines.
void resolutionToFemParams(int32_t targetPerAxis, int& level, int& nz) {
    level = std::max(0, std::min(4, (targetPerAxis - 10) / 6));
    nz = 2 * (level + 1);
}

// For each voxel cell, finds the FEM mesh node nearest to that cell's centre,
// via a spatial hash bucketed at the same cell size as the voxel grid (so
// each cell only needs to search its own bucket + 26 neighbours instead of
// every node) -- computed once and reused across every mode, since the
// nearest-node mapping doesn't depend on which mode's field is being sampled.
std::vector<int> nearestNodePerCell(const PolygonGridInfo& info, const PolyTetMesh& mesh) {
    auto bucketKey = [](int64_t bi, int64_t bj, int64_t bk) -> int64_t {
        return ((bi + 1000000) << 42) | ((bj + 1000000) << 21) | (bk + 1000000);
    };
    std::map<int64_t, std::vector<int>> buckets;
    for (int nd = 0; nd < (int)mesh.nodes.size(); ++nd) {
        int bi = (int)std::floor((mesh.nodes[nd].x - info.minX) / info.h);
        int bj = (int)std::floor((mesh.nodes[nd].y - info.minY) / info.h);
        int bk = (int)std::floor(mesh.nodes[nd].z / info.h);
        buckets[bucketKey(bi, bj, bk)].push_back(nd);
    }

    int cellCount = (int)info.ci.size();
    std::vector<int> nearest(cellCount, -1);
    for (int cell = 0; cell < cellCount; ++cell) {
        double cx = info.minX + (info.ci[cell] + 0.5) * info.h;
        double cy = info.minY + (info.cj[cell] + 0.5) * info.h;
        double cz = (info.ck[cell] + 0.5) * info.h;
        int bi = info.ci[cell], bj = info.cj[cell], bk = info.ck[cell];

        int best = -1;
        double bestD = 1e30;
        for (int radius = 1; radius <= 4 && best < 0; ++radius) {
            for (int dbi = -radius; dbi <= radius; ++dbi)
                for (int dbj = -radius; dbj <= radius; ++dbj)
                    for (int dbk = -radius; dbk <= radius; ++dbk) {
                        auto it = buckets.find(bucketKey(bi + dbi, bj + dbj, bk + dbk));
                        if (it == buckets.end()) continue;
                        for (int nd : it->second) {
                            double dx = mesh.nodes[nd].x - cx;
                            double dy = mesh.nodes[nd].y - cy;
                            double dz = mesh.nodes[nd].z - cz;
                            double d = dx * dx + dy * dy + dz * dz;
                            if (d < bestD) { bestD = d; best = nd; }
                        }
                    }
            // radius=1 (a full 3x3x3 neighbourhood) covers virtually every
            // cell; the loop only widens if that first pass found nothing,
            // e.g. a cell right at the mesh's edge.
        }
        nearest[cell] = best;
    }
    return nearest;
}

} // namespace

extern "C" {

NativeSolveResult* solve_room_modes(
    const double* polygonX, const double* polygonY, int32_t polygonVertexCount,
    double height, double temperatureC, int32_t targetPerAxis, int32_t modeCount) {
    if (polygonVertexCount < 3) return makeError("Floor plan needs at least 3 vertices");
    if (height <= 0) return makeError("Height must be positive");
    if (modeCount <= 0) return makeError("modeCount must be positive");

    Polygon poly;
    for (int32_t i = 0; i < polygonVertexCount; ++i)
        poly.verts.push_back({polygonX[i], polygonY[i]});

    // ---- FEM solve: the true geometry, the accurate frequencies ----
    int level, femNz;
    resolutionToFemParams(targetPerAxis, level, femNz);
    auto tris = earClipTriangulate(poly);
    if (tris.empty()) return makeError("Could not triangulate the floor plan");
    for (int s = 0; s < level; ++s) tris = subdivide(tris);
    auto femMesh = extrudeToTets(tris, height, femNz);

    auto sys = assembleFem(femMesh.nodes, femMesh.tets);
    std::vector<double> minvSqrt(sys.numNodes);
    for (int i = 0; i < sys.numNodes; ++i) minvSqrt[i] = 1.0 / std::sqrt(sys.lumpedM[i]);
    FemOperator op{sys.K, minvSqrt};
    auto pairs = femLanczosSmallestEigenpairs(op, sys.numNodes, modeCount,
                                               std::max(2 * modeCount + 10, 20));

    double c = 331.3 * std::sqrt(1.0 + temperatureC / 273.15);

    // ---- Voxel grid: visualization only ----
    PolygonGridInfo info;
    auto voxelOp = buildPolygonLaplacian(poly, height, targetPerAxis, info);
    int cellCount = voxelOp.cellCount;
    if (cellCount == 0) return makeError("Floor plan voxelized to zero cells at this resolution");

    auto nearest = nearestNodePerCell(info, femMesh);

    auto* result = new NativeSolveResult();
    std::memset(result, 0, sizeof(NativeSolveResult));
    result->nx = info.nx; result->ny = info.ny; result->nz = info.nz;
    result->h = info.h;
    result->originX = info.minX; result->originY = info.minY; result->originZ = 0;
    result->cellCount = cellCount;
    result->ci = new int32_t[cellCount];
    result->cj = new int32_t[cellCount];
    result->ck = new int32_t[cellCount];
    for (int i = 0; i < cellCount; ++i) {
        result->ci[i] = info.ci[i];
        result->cj[i] = info.cj[i];
        result->ck[i] = info.ck[i];
    }
    result->neighbors = new int32_t[cellCount * 6];
    std::copy(voxelOp.neighbors.begin(), voxelOp.neighbors.end(), result->neighbors);

    result->modeCount = (int32_t)pairs.size();
    result->frequencies = new double[pairs.size() > 0 ? pairs.size() : 1];
    result->fields = new double[(pairs.size() > 0 ? pairs.size() : 1) * cellCount];
    for (size_t m = 0; m < pairs.size(); ++m) {
        double mu = std::max(pairs[m].eigenvalue, 0.0);
        result->frequencies[m] = c * std::sqrt(mu) / (2 * M_PI);
        for (int cell = 0; cell < cellCount; ++cell) {
            int node = nearest[cell];
            result->fields[m * (size_t)cellCount + cell] = node >= 0 ? pairs[m].vector[node] : 0.0;
        }
    }

    result->success = 1;
    return result;
}

void free_solve_result(NativeSolveResult* result) {
    if (!result) return;
    delete[] result->ci;
    delete[] result->cj;
    delete[] result->ck;
    delete[] result->neighbors;
    delete[] result->frequencies;
    delete[] result->fields;
    delete[] result->errorMessage;
    delete result;
}

} // extern "C"
