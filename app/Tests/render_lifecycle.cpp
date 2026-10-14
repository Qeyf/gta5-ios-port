#include <atomic>
#include <cassert>
#include <chrono>
#include <cstdio>
#include <future>
#include <thread>

#if __has_include("NativeRenderLifecycle.h")
#include "NativeRenderLifecycle.h"

using namespace std::chrono_literals;

int main() {
    PGRenderLifecycle lifecycle;
    std::atomic<unsigned> submitted{0};
    lifecycle.setActive(false);
    auto pending = std::async(std::launch::async, [&] {
        lifecycle.performWhileActive([&] { ++submitted; });
    });
    assert(pending.wait_for(25ms) == std::future_status::timeout);
    assert(submitted == 0);
    lifecycle.setActive(true);
    pending.get();
    assert(submitted == 1);

    // Deactivation must wait until an already admitted submission leaves the
    // critical section, then capture that submission for Metal's scheduling fence.
    std::promise<void> entered, release;
    auto released = release.get_future().share();
    auto submitting = std::async(std::launch::async, [&] {
        lifecycle.performWhileActive([&] {
            entered.set_value();
            released.wait();
            ++submitted;
        });
    });
    entered.get_future().wait();
    unsigned schedulingFence = 0;
    auto pausing = std::async(std::launch::async, [&] {
        lifecycle.setActive(false, [&] { schedulingFence = submitted.load(); });
    });
    assert(pausing.wait_for(25ms) == std::future_status::timeout);
    release.set_value();
    submitting.get();
    pausing.get();
    assert(schedulingFence == 2);

    // The ring consumer and submissions both stop until activation. Resources
    // and commands remain owned by the caller, so resumption can finish them.
    auto consuming = std::async(std::launch::async, [&] {
        lifecycle.waitUntilActive();
        lifecycle.performWhileActive([&] { ++submitted; });
    });
    assert(consuming.wait_for(25ms) == std::future_status::timeout);
    assert(submitted == schedulingFence);
    lifecycle.setActive(true);
    consuming.get();
    assert(submitted == 3);

    // The scheduling fence can wait outside the lifecycle lock without
    // preventing activation or deadlocking the main thread.
    lifecycle.setActive(false);
    lifecycle.setActive(true, [&] { assert(submitted == 3); });
    lifecycle.performWhileActive([&] { ++submitted; });
    assert(submitted == 4);
    puts("PASS: pause blocks ring/submissions, fences admitted work, and resumes pending commands.");
}
#else
int main() {
    fputs("FAIL: the Metal renderer has no synchronized application lifecycle gate.\n", stderr);
    return 1;
}
#endif
