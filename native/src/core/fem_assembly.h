#pragma once
#include <Eigen/Sparse>
#include <Eigen/Dense>
#include <vector>
#include <array>
#include <cmath>

// Standard linear (P1) tetrahedron element formulas, assembled into the
// global stiffness K and a lumped (diagonal) mass M for the Neumann Helmholtz
// eigenproblem K u = mu M u:
//   element stiffness: K_ab = V * (grad N_a . grad N_b)  [gradients constant per element]
//   element mass (lumped): V/4 added to each of the 4 nodes
// No boundary term is added anywhere -- the rigid-wall (Neumann) condition is
// the *natural* boundary condition of this weak form, exactly as the missing-
// neighbour-means-no-flux trick is for the finite-volume operator.
//
// Works on any (nodes, tets) mesh -- shared by the box-structured mesh (used
// to validate against the analytical cuboid modes) and the extruded-polygon
// mesh (the production Custom-room path).
struct Vec3 { double x, y, z; };

struct FemSystem {
    Eigen::SparseMatrix<double> K;
    std::vector<double> lumpedM;
    int numNodes;
};

inline FemSystem assembleFem(const std::vector<Vec3>& nodes,
                              const std::vector<std::array<int, 4>>& tets) {
    FemSystem sys;
    sys.numNodes = (int)nodes.size();
    sys.lumpedM.assign(sys.numNodes, 0.0);

    std::vector<Eigen::Triplet<double>> triplets;
    triplets.reserve(tets.size() * 16);

    for (auto& tet : tets) {
        const Vec3& p0 = nodes[tet[0]];
        const Vec3& p1 = nodes[tet[1]];
        const Vec3& p2 = nodes[tet[2]];
        const Vec3& p3 = nodes[tet[3]];

        Eigen::Matrix3d J;
        J << p1.x - p0.x, p2.x - p0.x, p3.x - p0.x,
             p1.y - p0.y, p2.y - p0.y, p3.y - p0.y,
             p1.z - p0.z, p2.z - p0.z, p3.z - p0.z;
        double detJ = J.determinant();
        double V = std::fabs(detJ) / 6.0;
        if (V < 1e-14) continue; // degenerate safety net

        Eigen::Matrix3d Jinv = J.inverse();
        Eigen::Matrix<double, 4, 3> grads;
        grads.row(1) = Jinv.row(0); // grad L1
        grads.row(2) = Jinv.row(1); // grad L2
        grads.row(3) = Jinv.row(2); // grad L3
        grads.row(0) = -(grads.row(1) + grads.row(2) + grads.row(3)); // grad L0

        for (int a = 0; a < 4; ++a)
            for (int b = 0; b < 4; ++b)
                triplets.emplace_back(tet[a], tet[b], V * grads.row(a).dot(grads.row(b)));
        for (int a = 0; a < 4; ++a) sys.lumpedM[tet[a]] += V / 4.0;
    }

    sys.K.resize(sys.numNodes, sys.numNodes);
    sys.K.setFromTriplets(triplets.begin(), triplets.end());
    return sys;
}
