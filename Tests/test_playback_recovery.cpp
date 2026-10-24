#include "../Tweak/Features/Playback/PlaybackRecoveryPolicy.hpp"

#include <cassert>
#include <limits>

int main() {
    ytkace::PlaybackRecoveryBudget firstPlayer;
    assert(firstPlayer.begin(0));
    assert(firstPlayer.inFlight());
    assert(!firstPlayer.begin(1)); // Duplicate errors cannot start parallel reloads.
    assert(!firstPlayer.begin(120)); // A timeout cannot supersede an active reload.
    firstPlayer.finish();
    assert(firstPlayer.begin(2));
    firstPlayer.finish();
    assert(!firstPlayer.begin(3)); // Stop a permanently rejected stream retry loop.
    assert(firstPlayer.begin(60));

    ytkace::PlaybackRecoveryBudget secondPlayer;
    assert(secondPlayer.begin(3)); // Another video/player has an independent budget.
    assert(ytkace::playbackAdvanced(10, 10.2));
    assert(!ytkace::playbackAdvanced(10, 10.05));
    assert(!ytkace::playbackAdvanced(10, 0));
    assert(!ytkace::playbackAdvanced(-1, 10));
    assert(!ytkace::playbackAdvanced(10, std::numeric_limits<double>::quiet_NaN()));
}
