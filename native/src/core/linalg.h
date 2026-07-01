#pragma once
#include <vector>
#include <cmath>

inline double dotv(const std::vector<double>& a, const std::vector<double>& b) {
    double s = 0.0;
    for (size_t i = 0; i < a.size(); ++i) s += a[i] * b[i];
    return s;
}

inline double normv(const std::vector<double>& x) { return std::sqrt(dotv(x, x)); }

inline void normalizev(std::vector<double>& x) {
    double n = normv(x);
    if (n > 0) for (double& v : x) v /= n;
}
