#include "room_mode_solver.h"
#include <cstring>
#include <cmath>
#include <algorithm>
#include <array>
#include <vector>
#include <map>
#include "polygon.h"
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

// A mesh with too few nodes relative to the number of requested modes gives
// severely wrong low-order frequencies -- not just "less precise", genuinely
// unreliable -- because extracting many eigenvalues out of a tiny system
// means resolving a large fraction of its whole spectrum, and only the
// lowest slice of any discretization's spectrum is trustworthy. Calibrated
// against a 5x3 m L-room requesting 8 modes: 18 nodes gave 31% error on the
// fundamental; >=120 nodes (15 * modeCount) brought the worst-case error
// under ~10% and the fundamental under 1%.
constexpr int kMinNodesPerMode = 15;

// Maps the UI's resolution slider to an FEM refinement level (uniform 1-to-4
// subdivisions of the ear-clipped triangulation) and extrusion layer count,
// then bumps the level up -- never down from what the slider asked for --
// until the mesh has enough nodes for the requested mode count. Calibration
// also showed [nz] barely affects accuracy compared to [level] (going from
// 18->42 nodes via nz alone only moved the error 31.0%->30.4%), so the
// safety margin is enforced by refining the triangulation, not by adding
// more vertical layers.
void resolutionToFemParams(int32_t targetPerAxis, int32_t modeCount,
                            const std::vector<Tri2D>& baseTris, double height,
                            int& level, int& nz) {
    level = std::max(0, std::min(4, (targetPerAxis - 10) / 6));
    nz = 2 * (level + 1);

    const int minNodes = kMinNodesPerMode * std::max(modeCount, 1);
    while (level < 6) {
        auto tris = baseTris;
        for (int s = 0; s < level; ++s) tris = subdivide(tris);
        auto mesh = extrudeToTets(tris, height, nz);
        if ((int)mesh.nodes.size() >= minNodes) break;
        level++;
        nz = 2 * (level + 1);
    }
}

// A tet's 4 triangular faces (each omitting one vertex).
std::array<std::array<int, 3>, 4> tetFaces(const std::array<int, 4>& t) {
    return {{
        {t[1], t[2], t[3]},
        {t[0], t[2], t[3]},
        {t[0], t[1], t[3]},
        {t[0], t[1], t[2]},
    }};
}

// The mesh's outer surface: faces that belong to exactly one tet (an
// interior face is shared by two tets and cancels out). This is the room's
// physical boundary -- walls, floor, ceiling -- and is exactly what the 3D
// view needs to render, with no separate voxelization step and no
// resampling: the field values already live on these same nodes.
std::vector<std::array<int, 3>> extractBoundaryFaces(
    const std::vector<std::array<int, 4>>& tets) {
    std::map<std::array<int, 3>, int> count;
    std::map<std::array<int, 3>, std::array<int, 3>> winding;
    for (auto& t : tets) {
        for (auto& f : tetFaces(t)) {
            auto key = f;
            std::sort(key.begin(), key.end());
            count[key]++;
            winding[key] = f;
        }
    }
    std::vector<std::array<int, 3>> boundary;
    for (auto& [key, c] : count) {
        if (c == 1) boundary.push_back(winding[key]);
    }
    return boundary;
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

    auto baseTris = earClipTriangulate(poly);
    if (baseTris.empty()) return makeError("Could not triangulate the floor plan");
    int level, femNz;
    resolutionToFemParams(targetPerAxis, modeCount, baseTris, height, level, femNz);
    auto tris = baseTris;
    for (int s = 0; s < level; ++s) tris = subdivide(tris);
    auto femMesh = extrudeToTets(tris, height, femNz);

    auto sys = assembleFem(femMesh.nodes, femMesh.tets);
    std::vector<double> minvSqrt(sys.numNodes);
    for (int i = 0; i < sys.numNodes; ++i) minvSqrt[i] = 1.0 / std::sqrt(sys.lumpedM[i]);
    FemOperator op{sys.K, minvSqrt};
    auto pairs = femLanczosSmallestEigenpairs(op, sys.numNodes, modeCount,
                                               std::max(2 * modeCount + 10, 20));

    double c = 331.3 * std::sqrt(1.0 + temperatureC / 273.15);

    // ---- Boundary surface: the visualization *is* the solve mesh ----
    auto boundaryFaces = extractBoundaryFaces(femMesh.tets);
    if (boundaryFaces.empty()) return makeError("FEM mesh has no boundary surface");

    std::vector<int> usedNodes;
    std::map<int, int> remap;
    for (auto& f : boundaryFaces)
        for (int v : f)
            if (remap.find(v) == remap.end()) {
                remap[v] = (int)usedNodes.size();
                usedNodes.push_back(v);
            }

    int nodeCount = (int)usedNodes.size();
    int triCount = (int)boundaryFaces.size();

    auto* result = new NativeSolveResult();
    std::memset(result, 0, sizeof(NativeSolveResult));
    result->nodeCount = nodeCount;
    result->triCount = triCount;
    result->nodeX = new double[nodeCount];
    result->nodeY = new double[nodeCount];
    result->nodeZ = new double[nodeCount];
    for (int i = 0; i < nodeCount; ++i) {
        auto& n = femMesh.nodes[usedNodes[i]];
        result->nodeX[i] = n.x;
        result->nodeY[i] = n.y;
        result->nodeZ[i] = n.z;
    }
    result->triangles = new int32_t[triCount * 3];
    for (int i = 0; i < triCount; ++i)
        for (int k = 0; k < 3; ++k)
            result->triangles[i * 3 + k] = remap[boundaryFaces[i][k]];

    result->modeCount = (int32_t)pairs.size();
    result->frequencies = new double[pairs.size() > 0 ? pairs.size() : 1];
    result->fields = new double[(pairs.size() > 0 ? pairs.size() : 1) * nodeCount];
    for (size_t m = 0; m < pairs.size(); ++m) {
        double mu = std::max(pairs[m].eigenvalue, 0.0);
        result->frequencies[m] = c * std::sqrt(mu) / (2 * M_PI);
        for (int i = 0; i < nodeCount; ++i)
            result->fields[m * (size_t)nodeCount + i] = pairs[m].vector[usedNodes[i]];
    }

    result->success = 1;
    return result;
}

void free_solve_result(NativeSolveResult* result) {
    if (!result) return;
    delete[] result->nodeX;
    delete[] result->nodeY;
    delete[] result->nodeZ;
    delete[] result->triangles;
    delete[] result->frequencies;
    delete[] result->fields;
    delete[] result->errorMessage;
    delete result;
}

} // extern "C"
