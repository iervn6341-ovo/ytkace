#include "../Tweak/Features/Navigation/SheetUpdatePolicy.h"
#include <cassert>
int main() {
    YTKACESheetUpdatePolicy first, second;
    assert(!first.request(false));
    assert(first.request(true));
    for (int i = 0; i < 100; ++i) assert(!first.request(true));
    assert(second.request(true));
    assert(first.consume(true, true));
    assert(!first.consume(true, true));
    assert(!second.consume(true, false));
    assert(second.request(true));
    assert(!second.consume(false, true));
    assert(first.request(true));
    assert(first.consume(true, true));
}
