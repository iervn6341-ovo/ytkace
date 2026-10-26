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
    // Compact portrait player: prefer a complete free segment, not a row over transport controls.
    const std::vector<YTPCFrame> native{{178, 86, 60, 60}, {277, 94, 44, 44}, {88, 94, 44, 44}};
    auto packed = ytkace::planOverlayAvoiding(8, 406, 54, 177, 8, native);
    assert(packed.fits && packed.overflowCount > 0);
    YTPCFrame row{packed.x, packed.y, packed.width, 44};
    for (auto obstacle : native) assert(!YTPCIntersects(row, YTPCExpand(obstacle, 6)));
    // A fully obstructed/mini player must never push controls beyond its edges.
    assert(!ytkace::planOverlayAvoiding(8, 120, 54, 98, 8, {{8, 54, 112, 44}}).fits);
    for (int width = 160; width <= 900; width += 13) {
        for (std::size_t count = 1; count <= 12; ++count) {
            std::vector<YTPCFrame> controls{{width * 0.45, 88, 64, 64}, {width * 0.72, 92, 44, 44}};
            auto layout = ytkace::planOverlayAvoiding(8, width - 8, 54, 180, count, controls);
            if (!layout.fits) continue;
            YTPCFrame result{layout.x, layout.y, layout.width, 44};
            assert(YTPCContains({8, 54, double(width - 16), 126}, result));
            for (auto obstacle : controls) assert(!YTPCIntersects(result, YTPCExpand(obstacle, 6)));
            assert(layout.inlineCount + layout.overflowCount == count);
        }
    }
    // Portrait: use the native top band even when central controls block the second row.
    std::vector<YTPCFrame> portrait{{8,4,44,44}, {258,4,44,44}, {308,4,44,44}, {358,4,44,44},
                                    {85,90,60,60}, {178,80,60,60}, {275,90,60,60}};
    auto topBand = ytkace::planPlayerControls(8,406,4,181,8,portrait);
    assert(topBand.fits && topBand.y == 4 && topBand.overflowCount > 0);
    for (auto obstacle : portrait) assert(!YTPCIntersects({topBand.x,topBand.y,topBand.width,44},YTPCExpand(obstacle,6)));
    assert(!ytkace::planPlayerControls(8,406,4,181,8,{{8,0,398,181}}).fits);
    assert(!ytkace::planPlayerControls(8,406,NAN,181,8,portrait).fits);
    auto afterGesture = ytkace::planPlayerControls(8,844,4,362,8,{{8,4,44,44},{696,4,148,44}});
    assert(afterGesture.fits && afterGesture.overflowCount == 0 && afterGesture.y == 4);
    // Fill the first row, then a trailing second row under the native gear.
    auto toolbar = ytkace::planPlayerToolbar(8,406,4,181,9,portrait);
    assert(toolbar.fits && YTPCValid(toolbar.first) && YTPCValid(toolbar.second));
    assert(toolbar.second.y == 54 && toolbar.firstCount + toolbar.secondCount + toolbar.overflowCount == 9);
    assert(toolbar.second.x >= 330 && toolbar.overflowOnSecond);
    auto grouped = ytkace::planPlayerToolbar(8,844,4,362,5,{{8,4,44,44},{696,4,148,44}},2);
    assert(grouped.firstCount == 3 && grouped.secondCount == 2 && grouped.overflowCount == 0);
    assert(grouped.second.y == grouped.first.y + 50);
    auto shortPlayer = ytkace::planPlayerToolbar(8,844,4,48,5,{},2);
    assert(shortPlayer.firstCount == 5 && shortPlayer.secondCount == 0 && shortPlayer.fits);
    for (auto obstacle : portrait) {
        assert(!YTPCIntersects(toolbar.first,YTPCExpand(obstacle,6)));
        assert(!YTPCIntersects(toolbar.second,YTPCExpand(obstacle,6)));
    }
    for (int width = 180; width <= 1024; width += 11) {
        for (std::size_t n = 1; n <= 16; ++n) {
            std::vector<YTPCFrame> obstacles{{8,4,44,44},{double(width-152),4,144,44},
                {width*0.42,86,72,72}};
            auto rows = ytkace::planPlayerToolbar(8,width-8,4,181,n,obstacles);
            if (!rows.fits) continue;
            assert(rows.firstCount + rows.secondCount + rows.overflowCount == n);
            for (auto frame : {rows.first,rows.second}) if (YTPCValid(frame)) {
                assert(YTPCContains({8,4,double(width-16),177},frame));
                for (auto obstacle : obstacles) assert(!YTPCIntersects(frame,YTPCExpand(obstacle,6)));
            }
        }
    }
    assert(!ytkace::planPlayerToolbar(8,406,NAN,181,9,portrait).fits);
    assert(!ytkace::planPlayerToolbar(8,406,4,181,0,portrait).fits);
    // Bottom buttons use the fullscreen coordinate space and retain a 44pt touch target.
    YTPCFrame safe{4, 4, 406, 225}, fullscreen{372, 184, 36, 36};
    YTPCFrame bottomNative[]{{8, 195, 84, 22}, fullscreen};
    auto caption = YTPCPlaceBefore(safe, fullscreen, 44, 6, bottomNative, 2);
    assert(YTPCValid(caption) && caption.width == 44 && YTPCContains(safe, caption));
    for (auto obstacle : bottomNative) assert(!YTPCIntersects(caption, YTPCExpand(obstacle, 6)));
    auto quality = YTPCPlaceBefore(safe, caption, 44, 6, bottomNative, 2);
    assert(YTPCValid(quality) && !YTPCIntersects(caption, quality));
    YTPCFrame blocked[]{{4, 180, 340, 44}};
    assert(!YTPCValid(YTPCPlaceBefore(safe, fullscreen, 44, 6, blocked, 1)));
    assert(!YTPCValid(YTPCPlaceBefore(safe, fullscreen, 24, 6, nullptr, 0)));
    assert(!YTPCValid(YTPCPlaceBefore(safe, {NAN, 0, 44, 44}, 44, 6, nullptr, 0)));
    // Fullscreen peekable hosts can have negative/nonzero origins relative to the player.
    auto swappedHost = YTPCPlaceBefore({-56, -180, 788, 340}, {500, -4, 36, 36}, 44, 6, nullptr, 0);
    assert(YTPCValid(swappedHost) && swappedHost.y == -8);
    assert(YTPCContains({-56, -180, 788, 340}, swappedHost));
}
