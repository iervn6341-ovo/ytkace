#pragma once

#include <cmath>

namespace ytkace {

// One budget belongs to one player/video, never to the entire application.
class PlaybackRecoveryBudget {
public:
    bool begin(double now) {
        if (inFlight_) return false;
        if (!hasWindow_ || now - windowStart_ >= 60.0) {
            attempts_ = 0;
            windowStart_ = now;
            hasWindow_ = true;
        }
        if (attempts_ >= 2) return false;
        ++attempts_;
        inFlight_ = true;
        return true;
    }

    void finish() { inFlight_ = false; }
    bool inFlight() const { return inFlight_; }

private:
    unsigned attempts_ = 0;
    double windowStart_ = 0;
    bool hasWindow_ = false;
    bool inFlight_ = false;
};

inline bool playbackAdvanced(double saved, double current) {
    return std::isfinite(saved) && std::isfinite(current) && saved >= 0 &&
        current > saved + 0.15;
}

} // namespace ytkace
