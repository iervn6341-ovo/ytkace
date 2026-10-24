#include "../Tweak/UI/OverlayLayoutPolicy.hpp"
#include <cassert>
#include <limits>

int main() {
    auto normal = ytkace::planOverlay(8, 406, 54, 225, 8);
    assert(normal.fits && normal.inlineCount == 8 && normal.overflowCount == 0);
    assert(normal.x >= 8 && normal.x + normal.width <= 406);
    auto narrow = ytkace::planOverlay(8, 312, 54, 172, 8);
    assert(narrow.fits && narrow.inlineCount == 5 && narrow.overflowCount == 3);
    auto centralControls = ytkace::planOverlay(258, 406, 54, 225, 8);
    assert(centralControls.inlineCount == 2 && centralControls.overflowCount == 6);
    auto single = ytkace::planOverlay(8, 52, 54, 98, 8);
    assert(single.fits && single.inlineCount == 0 && single.overflowCount == 8);
    auto landscape = ytkace::planOverlay(67, 785, 8, 350, 8);
    assert(landscape.fits && landscape.overflowCount == 0);
    assert(landscape.x >= 67 && landscape.x + landscape.width <= 785);
    assert(!ytkace::planOverlay(8, 51, 54, 225, 8).fits);
    assert(!ytkace::planOverlay(8, 406, 54, 97, 8).fits);
    assert(!ytkace::planOverlay(8, 406, 54, 225, 0).fits);
    assert(!ytkace::planOverlay(406, 8, 54, 225, 8).fits);
    assert(!ytkace::planOverlay(8, std::numeric_limits<double>::quiet_NaN(), 54, 225, 8).fits);
    // Exact capacity boundaries must not lose the overflow button or extend out.
    assert(ytkace::planOverlay(0, 92, 0, 44, 2).inlineCount == 2);
    assert(ytkace::planOverlay(0, 91.9, 0, 44, 2).overflowCount == 2);
    for (int width = 44; width <= 1024; width += 7) {
        for (std::size_t count = 1; count <= 12; ++count) {
            auto layout = ytkace::planOverlay(8, width + 8, 54, 225, count);
            assert(layout.fits && layout.x >= 8 && layout.x + layout.width <= width + 8.001);
            assert(layout.inlineCount + layout.overflowCount == count);
            const auto slots = layout.inlineCount + (layout.overflowCount != 0 ? 1 : 0);
            assert(layout.width == slots * 44 + (slots - 1) * 4);
        }
    }
}
