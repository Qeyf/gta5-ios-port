#pragma once
#include <atomic>
#include <condition_variable>
#include <mutex>

// Serializes the decision to submit GPU work with application deactivation.
// Transition callbacks only capture the scheduling fence; they must not wait
// for Metal or call back into this gate while its mutex is held.
class PGRenderLifecycle {
    std::mutex mutex;
    std::condition_variable changed;
    std::atomic<bool> active{true};

public:
    void waitUntilActive() {
        // Ring commands are frequent; active rendering needs only one atomic
        // read here. Submissions still take the mutex to fence deactivation.
        if (active.load(std::memory_order_acquire)) return;
        std::unique_lock<std::mutex> lock(mutex);
        changed.wait(lock, [this] { return active.load(std::memory_order_relaxed); });
    }

    template<class Submission> void performWhileActive(Submission submission) {
        std::unique_lock<std::mutex> lock(mutex);
        changed.wait(lock, [this] { return active.load(std::memory_order_relaxed); });
        submission();
    }

    template<class Transition> void setActive(bool value, Transition transition) {
        {
            std::lock_guard<std::mutex> lock(mutex);
            active.store(value, std::memory_order_release);
            transition();
        }
        if (value) changed.notify_all();
    }

    void setActive(bool value) { setActive(value, [] {}); }
};
