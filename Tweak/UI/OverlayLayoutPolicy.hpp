#pragma once
#include <algorithm>
#include <cmath>
#include <cstddef>

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
} // namespace ytkace
