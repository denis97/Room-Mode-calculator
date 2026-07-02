#pragma once
#include <vector>
#include <cstdint>

// Matrix-free Neumann (rigid-wall) Laplacian on a voxel grid: each face
// shared with an inside neighbour contributes (u_i - u_j)/h^2; a missing
// neighbour (-1) is a wall and contributes nothing -- the rigid-wall
// condition falls out of the connectivity, with no special-casing. Mirrors
// lib/core/numeric/laplacian_operator.dart exactly.
struct NeumannLaplacian {
    int cellCount = 0;
    double invH2 = 0.0;
    std::vector<int32_t> neighbors; // 6 per cell: -x,+x,-y,+y,-z,+z

    void apply(const std::vector<double>& x, std::vector<double>& y, double shift = 0.0) const {
        for (int c = 0; c < cellCount; ++c) {
            int base = c * 6;
            int degree = 0;
            double neighborSum = 0.0;
            for (int d = 0; d < 6; ++d) {
                int nb = neighbors[base + d];
                if (nb >= 0) {
                    degree++;
                    neighborSum += x[nb];
                }
            }
            y[c] = invH2 * (degree * x[c] - neighborSum) + shift * x[c];
        }
    }
};
