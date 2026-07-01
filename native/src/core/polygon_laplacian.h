#pragma once
#include <vector>
#include <cmath>
#include <algorithm>
#include "laplacian.h"
#include "polygon.h"

struct PolygonGridInfo {
    int nx, ny, nz;
    double h;
    double minX, minY;
    int insideFootprintCells;
    std::vector<int> ci, cj, ck; // grid indices of each inside cell (for visualization/resampling)
};

// Voxelizes an extruded polygon, mirroring lib/core/geometry/voxel_grid.dart.
// Kept as an FDM reference/test path (see native/README.md) -- the production
// Custom-room solver uses the FEM path below, which is both faster and more
// accurate on non-rectilinear rooms (see the star-room comparison).
inline NeumannLaplacian buildPolygonLaplacian(const Polygon& poly, double height,
                                               int targetPerAxis, PolygonGridInfo& info) {
    double minX, minY, maxX, maxY;
    poly.bounds(minX, minY, maxX, maxY);
    double extentX = maxX - minX, extentY = maxY - minY;
    double maxExtent = std::max({extentX, extentY, height});
    double h = maxExtent / targetPerAxis;
    int nx = std::max(1, (int)std::ceil(extentX / h));
    int ny = std::max(1, (int)std::ceil(extentY / h));
    int nz = std::max(1, (int)std::ceil(height / h));

    auto lin = [&](int i, int j, int k) { return (k * ny + j) * nx + i; };
    std::vector<int32_t> compact(nx * ny * nz, -1);
    std::vector<int> ci, cj, ck;

    for (int k = 0; k < nz; ++k)
        for (int j = 0; j < ny; ++j)
            for (int i = 0; i < nx; ++i) {
                double cx = minX + (i + 0.5) * h;
                double cy = minY + (j + 0.5) * h;
                if (poly.contains(cx, cy)) {
                    compact[lin(i, j, k)] = (int32_t)ci.size();
                    ci.push_back(i); cj.push_back(j); ck.push_back(k);
                }
            }

    int cellCount = (int)ci.size();
    NeumannLaplacian op;
    op.cellCount = cellCount;
    op.invH2 = 1.0 / (h * h);
    op.neighbors.assign(cellCount * 6, -1);

    auto neighborAt = [&](int i, int j, int k) -> int32_t {
        if (i < 0 || i >= nx || j < 0 || j >= ny || k < 0 || k >= nz) return -1;
        return compact[lin(i, j, k)];
    };
    for (int c = 0; c < cellCount; ++c) {
        int i = ci[c], j = cj[c], k = ck[c];
        int base = c * 6;
        op.neighbors[base + 0] = neighborAt(i - 1, j, k);
        op.neighbors[base + 1] = neighborAt(i + 1, j, k);
        op.neighbors[base + 2] = neighborAt(i, j - 1, k);
        op.neighbors[base + 3] = neighborAt(i, j + 1, k);
        op.neighbors[base + 4] = neighborAt(i, j, k - 1);
        op.neighbors[base + 5] = neighborAt(i, j, k + 1);
    }

    int footprint = 0;
    for (int c = 0; c < cellCount; ++c) if (ck[c] == 0) footprint++;
    info = {nx, ny, nz, h, minX, minY, footprint, ci, cj, ck};
    return op;
}
