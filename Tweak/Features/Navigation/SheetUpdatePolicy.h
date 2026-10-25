#pragma once

// Layout and appearance callbacks in the same run-loop share one glass update.
class YTKACESheetUpdatePolicy {
    bool pending_ = false;
public:
    bool request(bool enabled) {
        if (!enabled || pending_) return false;
        pending_ = true;
        return true;
    }
    bool consume(bool enabled, bool visible) {
        bool apply = pending_ && enabled && visible;
        pending_ = false;
        return apply;
    }
};
