#pragma once
#include <vector>
#include <array>
#include <cmath>
#include <algorithm>
#include "fem_assembly.h" // Vec3

// A structured tetrahedral mesh over a box, via the Kuhn/Freudenthal
// triangulation (6 tets per hex, all sharing the (0,0,0)-(1,1,1) diagonal --
// conforming when applied uniformly over a regular grid). Used to validate
// the FEM assembly against the analytical cuboid modes; the production
// Custom-room path uses polygon_tet_mesh.h instead.
struct TetMesh {
    int nx, ny, nz;
    double h;
    int numNodes;
    std::vector<std::array<int, 4>> tets;

    int nodeIndex(int i, int j, int k) const {
        return k * (ny + 1) * (nx + 1) + j * (nx + 1) + i;
    }
};

inline TetMesh buildBoxTetMesh(double L, double W, double H, int targetPerAxis) {
    double maxExtent = std::max({L, W, H});
    double h = maxExtent / targetPerAxis;
    int nx = (int)std::round(L / h);
    int ny = (int)std::round(W / h);
    int nz = (int)std::round(H / h);

    TetMesh mesh;
    mesh.nx = nx; mesh.ny = ny; mesh.nz = nz; mesh.h = h;
    mesh.numNodes = (nx + 1) * (ny + 1) * (nz + 1);

    static const int perms[6][3] = {
        {0, 1, 2}, {0, 2, 1}, {1, 0, 2}, {1, 2, 0}, {2, 0, 1}, {2, 1, 0}};

    for (int k = 0; k < nz; ++k)
        for (int j = 0; j < ny; ++j)
            for (int i = 0; i < nx; ++i) {
                auto gid = [&](int di, int dj, int dk) {
                    return mesh.nodeIndex(i + di, j + dj, k + dk);
                };
                for (auto& perm : perms) {
                    int coords[3] = {0, 0, 0};
                    std::array<int, 4> path;
                    path[0] = gid(0, 0, 0);
                    for (int s = 0; s < 3; ++s) {
                        coords[perm[s]] = 1;
                        path[s + 1] = gid(coords[0], coords[1], coords[2]);
                    }
                    mesh.tets.push_back(path);
                }
            }
    return mesh;
}

// Converts a structured TetMesh into the (nodes, tets) form assembleFem()
// expects, shared with the extruded-polygon mesh path.
inline std::vector<Vec3> boxMeshNodes(const TetMesh& mesh) {
    std::vector<Vec3> nodes(mesh.numNodes);
    for (int idx = 0; idx < mesh.numNodes; ++idx) {
        int i = idx % (mesh.nx + 1);
        int j = (idx / (mesh.nx + 1)) % (mesh.ny + 1);
        int k = idx / ((mesh.nx + 1) * (mesh.ny + 1));
        nodes[idx] = {i * mesh.h, j * mesh.h, k * mesh.h};
    }
    return nodes;
}
