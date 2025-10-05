module promise_test;

import core.thread;
import core.time;
import promise;
import std.exception;

///  Test basic promise fulfillment with value
unittest {
    auto p = new Promise!int((resolve, reject) {
        Thread.sleep(10.msecs);
        resolve(42);
    });

    assert(p.await() == 42);
}

///  Test basic promise fulfillment with void
unittest {
    bool executed = false;
    auto p = new Promise!void((resolve, reject) {
        Thread.sleep(dur!"msecs"(10));
        executed = true;
        resolve();
    });

    p.await();
    assert(executed);
}

///  Test basic promise rejection
unittest {
    auto p = new Promise!int((resolve, reject) {
        Thread.sleep(dur!"msecs"(10));
        reject(new Exception("Test error"));
    });

    assertThrown!Exception(p.await());
}

///  Test promise rejection with specific error message
unittest {
    auto p = new Promise!int((resolve, reject) {
        reject(new Exception("Custom error"));
    });
    assertThrown!Exception(p.await());
}

///  Test executor exception causes rejection
unittest {
    auto p = new Promise!int((resolve, reject) {
        throw new Exception("Executor error");
    });

    try {
        p.await();
        assert(false, "Should have thrown");
    } catch (Exception e) {
        assert(e.msg == "Executor error");
    }
}

///  Test Promise.resolve with value
unittest {
    auto p = Promise!int.resolve(100);
    assert(p.await() == 100);
}

///  Test Promise.resolve with void
unittest {
    auto p = Promise!void.resolve();
    p.await(); // Should not throw
}

///  Test Promise.reject
unittest {
    auto p = Promise!string.reject(new Exception("Rejected"));

    try {
        p.await();
        assert(false, "Should have thrown");
    } catch (Exception e) {
        assert(e.msg == "Rejected");
    }
}

///  Test then with fulfillment handler (value to value)
unittest {
    auto p = new Promise!int((resolve, reject) {
        resolve(10);
    });

    auto p2 = p.then!int((value) => value * 2);
    assert(p2.await() == 20);
}

///  Test then with fulfillment handler (value to void)
unittest {
    int result = 0;
    auto p = new Promise!int((resolve, reject) {
        resolve(15);
    });

    auto p2 = p.then!void((value) { result = value; });
    p2.await();
    assert(result == 15);
}

///  Test then with fulfillment handler (void to value)
unittest {
    auto p = new Promise!void((resolve, reject) {
        resolve();
    });

    auto p2 = p.then!int(() => 77);
    assert(p2.await() == 77);
}

///  Test then with fulfillment handler (void to void)
unittest {
    bool called = false;
    auto p = new Promise!void((resolve, reject) {
        resolve();
    });

    auto p2 = p.then!void(() { called = true; });
    p2.await();
    assert(called);
}

///  Test then with rejection handler
unittest {
    auto p = new Promise!int((resolve, reject) {
        reject(new Exception("Error"));
    });

    auto p2 = p.then!int((value) => value, (error) => 999);
    assert(p2.await() == 999);
}

///  Test then with both handlers, fulfillment path
unittest {
    auto p = new Promise!int((resolve, reject) {
        resolve(5);
    });

    auto p2 = p.then!int((value) => value + 1, (error) => -1);
    assert(p2.await() == 6);
}

///  Test then with both handlers, rejection path
unittest {
    auto p = new Promise!int((resolve, reject) {
        reject(new Exception("Error"));
    });

    auto p2 = p.then!int((value) => value, (error) => 42);
    assert(p2.await() == 42);
}

///  Test then chain (multiple then calls)
unittest {
    auto p = new Promise!int((resolve, reject) {
        resolve(1);
    });

    auto result = p
        .then!int((v) => v + 1)
        .then!int((v) => v * 2)
        .then!int((v) => v + 10)
        .await();

    assert(result == 14); // ((1 + 1) * 2) + 10 = 14
}

///  Test then without handler propagates fulfillment
unittest {
    auto p = new Promise!int((resolve, reject) {
        resolve(55);
    });

    auto p2 = p.then!int(null, null);
    assert(p2.await() == 55);
}

///  Test then without handler propagates rejection
unittest {
    auto p = new Promise!int((resolve, reject) {
        reject(new Exception("Propagated"));
    });

    auto p2 = p.then!int(null, null);
    assertThrown!Exception(p2.await());
}

/// / Test catch_ with rejection
unittest {
    auto p = new Promise!int((resolve, reject) {
        reject(new Exception("Catch me"));
    });

    auto p2 = p.catch_((error) => 123);
    assert(p2.await() == 123);
}

///  Test catch_ with fulfillment (no-op)
unittest {
    auto p = new Promise!int((resolve, reject) {
        resolve(50);
    });

    auto p2 = p.catch_((error) => 999);
    assert(p2.await() == 50);
}

///  Test catch_ can convert exception to value
unittest {
    auto p = new Promise!string((resolve, reject) {
        reject(new Exception("Error message"));
    });

    auto p2 = p.catch_((error) => "Recovered: " ~ error.msg);
    assert(p2.await() == "Recovered: Error message");
}

///  Test finally_ with fulfillment
unittest {
    bool finallyCalled = false;
    auto p = new Promise!int((resolve, reject) {
        resolve(100);
    });

    auto p2 = p.finally_(() { finallyCalled = true; });
    assert(p2.await() == 100);
    assert(finallyCalled);
}

///  Test finally_ with rejection
unittest {
    bool finallyCalled = false;
    auto p = new Promise!int((resolve, reject) {
        reject(new Exception("Finally test"));
    });

    auto p2 = p.finally_(() { finallyCalled = true; });
    assertThrown!Exception(p2.await());
    assert(finallyCalled);
}

///  Test finally_ with void promise fulfillment
unittest {
    bool finallyCalled = false;
    auto p = new Promise!void((resolve, reject) {
        resolve();
    });

    auto p2 = p.finally_(() { finallyCalled = true; });
    p2.await();
    assert(finallyCalled);
}

///  Test finally_ with void promise rejection
unittest {
    bool finallyCalled = false;
    auto p = new Promise!void((resolve, reject) {
        reject(new Exception("Void finally"));
    });

    auto p2 = p.finally_(() { finallyCalled = true; });
    assertThrown!Exception(p2.await());
    assert(finallyCalled);
}

///  Test finally_ exception overrides original result
unittest {
    auto p = new Promise!int((resolve, reject) {
        resolve(50);
    });

    auto p2 = p.finally_(() { throw new Exception("Finally error"); });

    try {
        p2.await();
        assert(false, "Should have thrown");
    } catch (Exception e) {
        assert(e.msg == "Finally error");
    }
}

///  Test multiple await on same promise
unittest {
    auto p = new Promise!int((resolve, reject) {
        Thread.sleep(dur!"msecs"(10));
        resolve(42);
    });

    assert(p.await() == 42);
    assert(p.await() == 42);
    assert(p.await() == 42);
}

///  Test resolve called multiple times (only first counts)
unittest {
    auto p = new Promise!int((resolve, reject) {
        resolve(1);
        resolve(2);
        resolve(3);
    });

    assert(p.await() == 1);
}

///  Test reject called multiple times (only first counts)
unittest {
    auto p = new Promise!int((resolve, reject) {
        reject(new Exception("First"));
        reject(new Exception("Second"));
    });

    try {
        p.await();
        assert(false, "Should have thrown");
    } catch (Exception e) {
        assert(e.msg == "First");
    }
}

///  Test resolve then reject (resolve wins)
unittest {
    auto p = new Promise!int((resolve, reject) {
        resolve(100);
        reject(new Exception("Should be ignored"));
    });

    assert(p.await() == 100);
}

///  Test reject then resolve (reject wins)
unittest {
    auto p = new Promise!int((resolve, reject) {
        reject(new Exception("First"));
        resolve(200);
    });

    assertThrown!Exception(p.await());
}

///  Test promise with string type
unittest {
    auto p = new Promise!string((resolve, reject) {
        resolve("Hello, World!");
    });

    assert(p.await() == "Hello, World!");
}

///  Test promise with custom struct
unittest {
    struct Point {
        int x, y;
    }

    auto p = new Promise!Point((resolve, reject) {
        resolve(Point(10, 20));
    });

    auto result = p.await();
    assert(result.x == 10);
    assert(result.y == 20);
}

///  Test promise chain with type transformations
unittest {
    auto p = new Promise!int((resolve, reject) {
        resolve(42);
    });

    auto p2 = p.then!string((value) {
        import std.conv : to;
        return "The answer is " ~ value.to!string;
    });

    assert(p2.await() == "The answer is 42");
}

///  Test then handler throwing exception
unittest {
    auto p = new Promise!int((resolve, reject) {
        resolve(10);
    });

    auto p2 = p.then!int((value) {
        return throw new Exception("Handler error");
    });

    assertThrown!Exception(p2.await());
}

///  Test catch_ handler throwing exception
unittest {
    auto p = new Promise!int((resolve, reject) {
        reject(new Exception("Original"));
    });

    auto p2 = p.catch_((error) {
        return throw new Exception("Catch handler error");
    });

    try {
        p2.await();
        assert(false, "Should have thrown");
    } catch (Exception e) {
        assert(e.msg == "Catch handler error");
    }
}

///  Test rejection handler with void return type
unittest {
    bool handlerCalled = false;
    auto p = new Promise!int((resolve, reject) {
        reject(new Exception("Error"));
    });

    auto p2 = p.then!void((value) {}, (error) { handlerCalled = true; });
    p2.await();
    assert(handlerCalled);
}

///  Test complex chain with mixed success and error handling
unittest {
    auto p = new Promise!int((resolve, reject) {
        resolve(10);
    });

    auto result = p
        .then!int((v) => v * 2)
        .then!int((v) {
            if (v > 15) throw new Exception("Too big");
            return v;
        })
        .catch_((e) => 0)
        .then!int((v) => v + 100)
        .await();

    assert(result == 100); // (10 * 2 = 20) throws, catch returns 0, then 0 + 100 = 100
}

///  Test await blocks until promise settles
unittest {
    import std.datetime.stopwatch : AutoStart, StopWatch;

    auto sw = StopWatch(AutoStart.yes);
    auto p = new Promise!int((resolve, reject) {
        Thread.sleep(dur!"msecs"(50));
        resolve(123);
    });

    auto result = p.await();
    sw.stop();

    assert(result == 123);
    assert(sw.peek().total!"msecs" >= 40);
}

///  Test concurrent promises
unittest {
    auto p1 = new Promise!int((resolve, reject) {
        Thread.sleep(dur!"msecs"(20));
        resolve(1);
    });

    auto p2 = new Promise!int((resolve, reject) {
        Thread.sleep(dur!"msecs"(20));
        resolve(2);
    });

    auto p3 = new Promise!int((resolve, reject) {
        Thread.sleep(dur!"msecs"(20));
        resolve(3);
    });

    import std.datetime.stopwatch : AutoStart, StopWatch;
    auto sw = StopWatch(AutoStart.yes);

    int sum = p1.await() + p2.await() + p3.await();
    sw.stop();

    assert(sum == 6);
}

///  Test Promise.resolve with already resolved promise
unittest {
    auto p1 = Promise!int.resolve(42);
    assert(p1.await() == 42);
}

///  Test void promise with then returning value
unittest {
    auto p = Promise!void.resolve();
    auto p2 = p.then!string(() => "converted");
    assert(p2.await() == "converted");
}

///  Test long promise chain
unittest {
    auto p = Promise!int.resolve(1);

    foreach (i; 0..10) {
        p = p.then!int((v) => v + 1);
    }

    assert(p.await() == 11);
}

///  Test error propagation through long chain
unittest {
    auto p = new Promise!int((resolve, reject) {
        reject(new Exception("Initial error"));
    });

    auto p2 = p
        .then!int((v) => v + 1)
        .then!int((v) => v * 2)
        .then!int((v) => v - 5);

    assertThrown!Exception(p2.await());
}

///  Test recovery in middle of chain
unittest {
    auto p = new Promise!int((resolve, reject) {
        reject(new Exception("Error"));
    });

    auto result = p
        .catch_((e) => 10)
        .then!int((v) => v * 3)
        .await();

    assert(result == 30);
}

///  Test immediate resolution
unittest {
    auto p = new Promise!int((resolve, reject) {
        resolve(999);
    });

    assert(p.await() == 999);
}

///  Test immediate rejection
unittest {
    auto p = new Promise!int((resolve, reject) {
        reject(new Exception("Immediate"));
    });

    assertThrown!Exception(p.await());
}

///  Test nested promise execution
unittest {
    auto outer = new Promise!int((outerResolve, outerReject) {
        auto inner = new Promise!int((innerResolve, innerReject) {
            innerResolve(42);
        });
        outerResolve(inner.await());
    });

    assert(outer.await() == 42);
}

///  Test promise with float type
unittest {
    auto p = new Promise!double((resolve, reject) {
        resolve(3.14159);
    });

    auto result = p.await();
    assert(result > 3.14 && result < 3.15);
}

///  Test promise with array type
unittest {
    auto p = new Promise!(int[])((resolve, reject) {
        resolve([1, 2, 3, 4, 5]);
    });

    auto result = p.await();
    assert(result.length == 5);
    assert(result[2] == 3);
}

///  Test exception with empty message
unittest {
    auto p = new Promise!int((resolve, reject) {
        reject(new Exception(""));
    });

    assertThrown!Exception(p.await());
}
