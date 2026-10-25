#pragma once
#include <math.h>
#include <stddef.h>
#include <stdbool.h>

// C-compatible geometry shared with the patched YTVideoOverlay Objective-C source.
typedef struct { double x, y, width, height; } YTPCFrame;
static inline bool YTPCValid(YTPCFrame r) {
    return isfinite(r.x) && isfinite(r.y) && isfinite(r.width) && isfinite(r.height) && r.width > 0 && r.height > 0;
}
static inline bool YTPCContains(YTPCFrame outer, YTPCFrame inner) {
    return YTPCValid(outer) && YTPCValid(inner) && inner.x >= outer.x && inner.y >= outer.y &&
        inner.x + inner.width <= outer.x + outer.width && inner.y + inner.height <= outer.y + outer.height;
}
static inline bool YTPCIntersects(YTPCFrame a, YTPCFrame b) {
    return YTPCValid(a) && YTPCValid(b) && a.x < b.x + b.width && b.x < a.x + a.width &&
        a.y < b.y + b.height && b.y < a.y + a.height;
}
static inline YTPCFrame YTPCExpand(YTPCFrame r, double margin) {
    YTPCFrame result = {r.x - margin, r.y - margin, r.width + 2 * margin, r.height + 2 * margin};
    return result;
}
static inline YTPCFrame YTPCPlaceBefore(YTPCFrame safe, YTPCFrame anchor, double extent, double gap,
                                      const YTPCFrame *obstacles, size_t count) {
    YTPCFrame empty = {0, 0, 0, 0};
    if (!YTPCValid(safe) || !YTPCValid(anchor) || !isfinite(extent) || !isfinite(gap) ||
        extent < 44 || gap < 0 || extent > safe.width || extent > safe.height) return empty;
    double right = fmin(anchor.x - gap, safe.x + safe.width);
    double y = fmax(safe.y, fmin(anchor.y + (anchor.height - extent) / 2, safe.y + safe.height - extent));
    for (size_t attempt = 0; attempt <= count; ++attempt) {
        YTPCFrame candidate = {right - extent, y, extent, extent};
        if (!YTPCContains(safe, candidate)) return empty;
        double next = right;
        for (size_t i = 0; i < count; ++i) {
            if (YTPCIntersects(candidate, YTPCExpand(obstacles[i], gap))) next = fmin(next, obstacles[i].x - gap);
        }
        if (next == right) return candidate;
        right = next;
    }
    return empty;
}
