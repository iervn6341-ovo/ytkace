#pragma once
#include <algorithm>
#include <cmath>
#include <cstddef>
#include <vector>
#include "PlayerControlGeometry.h"

namespace ytkace {
struct OverlayLayout {
    double x = 0, y = 0, width = 0;
    std::size_t inlineCount = 0, overflowCount = 0;
    bool fits = false;
};

// Bounds describe a collision-free row inside the player's safe area.
// Keep touch targets intact; reserve one slot for More rather than shrinking.
inline OverlayLayout planOverlay(double left, double right, double top,
                                  double bottom, std::size_t count,
                                  double extent = 44, double gap = 4) {
    OverlayLayout result;
    if (!std::isfinite(left) || !std::isfinite(right) ||
        !std::isfinite(top) || !std::isfinite(bottom) ||
        !std::isfinite(extent) || !std::isfinite(gap) ||
        count == 0 || extent <= 0 || gap < 0 || right - left < extent ||
        bottom - top < extent) return result;
    const auto slots = static_cast<std::size_t>(std::min<double>(
        count, std::floor((right - left + gap) / (extent + gap))));
    if (slots == 0) return result;
    result.inlineCount = count <= slots ? count : slots - 1;
    result.overflowCount = count - result.inlineCount;
    result.width = slots * extent + (slots - 1) * gap;
    result.x = right - result.width;
    result.y = top;
    result.fits = true;
    return result;
}

// Evaluate complete 44pt rows around native controls. Never shrink buttons to fit.
inline OverlayLayout planOverlayAvoiding(double left, double right, double top, double bottom,
                                         std::size_t count, const std::vector<YTPCFrame>& obstacles,
                                         double extent = 44, double gap = 6) {
    OverlayLayout best;
    if (!planOverlay(left, right, top, bottom, count, extent, gap).fits) return best;
    std::vector<double> rows{top};
    for (auto obstacle : obstacles) if (YTPCValid(obstacle)) {
        rows.push_back(obstacle.y - gap - extent);
        rows.push_back(obstacle.y + obstacle.height + gap);
    }
    std::sort(rows.begin(), rows.end());
    for (double y : rows) {
        if (!std::isfinite(y) || y < top || y + extent > bottom) continue;
        std::vector<std::pair<double, double>> blocked;
        for (auto obstacle : obstacles) {
            if (!YTPCValid(obstacle) || obstacle.y - gap >= y + extent || obstacle.y + obstacle.height + gap <= y) continue;
            blocked.emplace_back(obstacle.x - gap, obstacle.x + obstacle.width + gap);
        }
        std::sort(blocked.begin(), blocked.end());
        double cursor = left;
        auto consider = [&](double end) {
            auto plan = planOverlay(cursor, std::min(right, end), y, bottom, count, extent, gap);
            if (!plan.fits) return;
            if (!best.fits || plan.inlineCount > best.inlineCount ||
                (plan.inlineCount == best.inlineCount && (plan.y < best.y ||
                 (plan.y == best.y && plan.x > best.x)))) best = plan;
        };
        for (auto interval : blocked) {
            consider(interval.first);
            cursor = std::max(cursor, interval.second);
            if (cursor >= right) break;
        }
        consider(right);
    }
    return best;
}
// Follow the native top-button band before considering a second row. Reserving
// a whole second row up front makes short portrait players lose every action.
inline OverlayLayout planPlayerControls(double left, double right, double top, double bottom,
                                        std::size_t count, const std::vector<YTPCFrame>& obstacles) {
    auto row = planOverlayAvoiding(left, right, top, std::min(bottom, top + 44), count, obstacles);
    if (row.fits) return row;
    // If the native top band is full, expose one More target in a free segment
    // instead of extending a second toolbar over the central transport buttons.
    row = planOverlayAvoiding(left, right, top, bottom, count ? 1 : 0, obstacles);
    if (row.fits && count > 1) { row.inlineCount = 0; row.overflowCount = count; }
    return row;
}
} // namespace ytkace
