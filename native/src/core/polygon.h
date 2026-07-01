#pragma once
#include <vector>
#include <utility>
#include <cmath>
#include <algorithm>

// A 2D floor polygon (the room's footprint), matching
// lib/core/geometry/room_shape.dart's ExtrudedPolygonShape.
struct Polygon {
    std::vector<std::pair<double, double>> verts;

    bool contains(double x, double y) const {
        bool inside = false;
        size_t n = verts.size();
        for (size_t i = 0, j = n - 1; i < n; j = i++) {
            double xi = verts[i].first, yi = verts[i].second;
            double xj = verts[j].first, yj = verts[j].second;
            bool crosses = ((yi > y) != (yj > y)) &&
                           (x < (xj - xi) * (y - yi) / (yj - yi) + xi);
            if (crosses) inside = !inside;
        }
        return inside;
    }

    void bounds(double& minX, double& minY, double& maxX, double& maxY) const {
        minX = minY = 1e18; maxX = maxY = -1e18;
        for (auto& v : verts) {
            minX = std::min(minX, v.first); maxX = std::max(maxX, v.first);
            minY = std::min(minY, v.second); maxY = std::max(maxY, v.second);
        }
    }

    double area() const { // shoelace
        double s = 0;
        size_t n = verts.size();
        for (size_t i = 0, j = n - 1; i < n; j = i++)
            s += (verts[j].first + verts[i].first) * (verts[j].second - verts[i].second);
        return std::fabs(s) / 2.0;
    }
};

inline Polygon makeStarPolygon(int points, double outerR, double innerR) {
    Polygon poly;
    int n = points * 2;
    for (int k = 0; k < n; ++k) {
        double theta = M_PI / 2 + k * (2 * M_PI / n);
        double r = (k % 2 == 0) ? outerR : innerR;
        poly.verts.push_back({r * std::cos(theta), r * std::sin(theta)});
    }
    return poly;
}

// The specific 5-point star used to find the disconnection bug: outer radius
// 3 m, inner radius 1.5 m.
inline Polygon makeStarPolygon5() { return makeStarPolygon(5, 3.0, 1.5); }
