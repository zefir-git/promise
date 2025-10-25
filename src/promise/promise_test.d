module promise_test;

import core.thread;
import core.time;
import std.conv;
import std.exception;
import std.parallelism;
import std.range;
import std.stdio;

import promise;

///  Test basic promise fulfillment with value
unittest {
    writeln("Testing basic promise fulfillment with value");
    auto p = new Promise!int((resolve, reject) {
        Thread.sleep(10.msecs);
        resolve(42);
    });

    assert(p.await() == 42);
}

///  Test basic promise fulfillment with void
unittest {
    writeln("Testing basic promise fulfillment with void");
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
    writeln("Testing basic promise rejection");
    auto p = new Promise!int((resolve, reject) {
        Thread.sleep(dur!"msecs"(10));
        reject(new Exception("Test error"));
    });

    assertThrown!Exception(p.await());
}

///  Test promise rejection with specific error message
unittest {
    writeln("Testing promise rejection with specific error message");
    auto p = new Promise!int((resolve, reject) {
        reject(new Exception("Custom error"));
    });
    assertThrown!Exception(p.await());
}

///  Test executor exception causes rejection
unittest {
    writeln("Testing executor exception causes rejection");
    auto p = new Promise!int((resolve, reject) {
        throw new Exception("Executor error");
    });

    assertThrown!Exception(p.await());
}

///  Test Promise.resolve with value
unittest {
    writeln("Testing Promise.resolve with value");
    auto p = Promise!int.resolve(100);
    assert(p.await() == 100);
}

///  Test Promise.resolve with void
unittest {
    writeln("Testing Promise.resolve with void");
    auto p = Promise!void.resolve();
    p.await(); // Should not throw
}

///  Test Promise.reject
unittest {
    writeln("Testing Promise.reject");
    auto p = Promise!string.reject(new Exception("Rejected"));

    assertThrown!Exception(p.await());
}

///  Test then with fulfillment handler (value to value)
unittest {
    writeln("Testing then with fulfillment handler (value to value)");
    auto p = new Promise!int((resolve, reject) {
        resolve(10);
    });

    auto p2 = p.then!int((value) => value * 2);
    assert(p2.await() == 20);
}

///  Test then with fulfillment handler (value to void)
unittest {
    writeln("Testing then with fulfillment handler (value to void)");
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
    writeln("Testing then with fulfillment handler (void to value)");
    auto p = new Promise!void((resolve, reject) {
        resolve();
    });

    auto p2 = p.then!int(() => 77);
    assert(p2.await() == 77);
}

///  Test then with fulfillment handler (void to void)
unittest {
    writeln("Testing then with fulfillment handler (void to void)");
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
    writeln("Testing then with rejection handler");
    auto p = new Promise!int((resolve, reject) {
        reject(new Exception("Error"));
    });

    auto p2 = p.then!int((value) => value, (error) => 999);
    assert(p2.await() == 999);
}

///  Test then with both handlers, fulfillment path
unittest {
    writeln("Testing then with both handlers, fulfillment path");
    auto p = new Promise!int((resolve, reject) {
        resolve(5);
    });

    auto p2 = p.then!int((value) => value + 1, (error) => -1);
    assert(p2.await() == 6);
}

///  Test then with both handlers, rejection path
unittest {
    writeln("Testing then with both handlers, rejection path");
    auto p = new Promise!int((resolve, reject) {
        reject(new Exception("Error"));
    });

    auto p2 = p.then!int((value) => value, (error) => 42);
    assert(p2.await() == 42);
}

///  Test then chain (multiple then calls)
unittest {
    writeln("Testing then chain (multiple then calls)");
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
    writeln("Testing then without handler propagates fulfillment");
    auto p = new Promise!int((resolve, reject) {
        resolve(55);
    });

    auto p2 = p.then!int(null, null);
    assert(p2.await() == 55);
}

///  Test then without handler propagates rejection
unittest {
    writeln("Testing then without handler propagates rejection");
    auto p = new Promise!int((resolve, reject) {
        reject(new Exception("Propagated"));
    });

    auto p2 = p.then!int(null, null);
    assertThrown!Exception(p2.await());
}

/// / Test catch_ with rejection
unittest {
    writeln("Testing catch_ with rejection");
    auto p = new Promise!int((resolve, reject) {
        reject(new Exception("Catch me"));
    });

    auto p2 = p.catch_((error) => 123);
    assert(p2.await() == 123);
}

///  Test catch_ with fulfillment (no-op)
unittest {
    writeln("Testing catch_ with fulfillment (no-op)");
    auto p = new Promise!int((resolve, reject) {
        resolve(50);
    });

    auto p2 = p.catch_((error) => 999);
    assert(p2.await() == 50);
}

///  Test catch_ can convert exception to value
unittest {
    writeln("Testing catch_ can convert exception to value");
    auto p = new Promise!string((resolve, reject) {
        reject(new Exception("Error message"));
    });

    auto p2 = p.catch_((error) => "Recovered: " ~ error.msg);
    assert(p2.await() == "Recovered: Error message");
}

///  Test finally_ with fulfillment
unittest {
    writeln("Testing finally_ with fulfillment");
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
    writeln("Testing finally_ with rejection");
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
    writeln("Testing finally_ with void promise fulfillment");
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
    writeln("Testing finally_ with void promise rejection");
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
    writeln("Testing finally_ exception overrides original result");
    auto p = new Promise!int((resolve, reject) {
        resolve(50);
    });

    auto p2 = p.finally_(() { throw new Exception("Finally error"); });

    assertThrown!Exception(p2.await());
}

///  Test multiple await on same promise
unittest {
    writeln("Testing multiple await on same promise");
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
    writeln("Testing resolve called multiple times (only first counts)");
    auto p = new Promise!int((resolve, reject) {
        resolve(1);
        resolve(2);
        resolve(3);
    });

    assert(p.await() == 1);
}

///  Test reject called multiple times (only first counts)
unittest {
    writeln("Testing reject called multiple times (only first counts)");
    auto p = new Promise!int((resolve, reject) {
        reject(new Exception("First"));
        reject(new Exception("Second"));
    });

    assertThrown!Exception(p.await());
}

///  Test resolve then reject (resolve wins)
unittest {
    writeln("Testing resolve then reject (resolve wins)");
    auto p = new Promise!int((resolve, reject) {
        resolve(100);
        reject(new Exception("Should be ignored"));
    });

    assert(p.await() == 100);
}

///  Test reject then resolve (reject wins)
unittest {
    writeln("Testing reject then resolve (reject wins)");
    auto p = new Promise!int((resolve, reject) {
        reject(new Exception("First"));
        resolve(200);
    });

    assertThrown!Exception(p.await());
}

///  Test promise with string type
unittest {
    writeln("Testing promise with string type");
    auto p = new Promise!string((resolve, reject) {
        resolve("Hello, World!");
    });

    assert(p.await() == "Hello, World!");
}

///  Test promise with custom struct
unittest {
    writeln("Testing promise with custom struct");
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
    writeln("Testing promise chain with type transformations");
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
    writeln("Testing then handler throwing exception");
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
    writeln("Testing catch_ handler throwing exception");
    auto p = new Promise!int((resolve, reject) {
        reject(new Exception("Original"));
    });

    auto p2 = p.catch_((error) {
        return throw new Exception("Catch handler error");
    });

    assertThrown!Exception(p2.await());
}

///  Test rejection handler with void return type
unittest {
    writeln("Testing rejection handler with void return type");
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
    writeln("Testing complex chain with mixed success and error handling");
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
    writeln("Testing await blocks until promise settles");
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
    writeln("Testing concurrent promises");
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
    writeln("Testing Promise.resolve with already resolved promise");
    auto p1 = Promise!int.resolve(42);
    assert(p1.await() == 42);
}

///  Test void promise with then returning value
unittest {
    writeln("Testing void promise with then returning value");
    auto p = Promise!void.resolve();
    auto p2 = p.then!string(() => "converted");
    assert(p2.await() == "converted");
}

///  Test long promise chain
unittest {
    writeln("Testing long promise chain");
    auto p = Promise!int.resolve(1);

    foreach (i; 0..10) {
        p = p.then!int((v) => v + 1);
    }

    assert(p.await() == 11);
}

///  Test error propagation through long chain
unittest {
    writeln("Testing error propagation through long chain");
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
    writeln("Testing recovery in middle of chain");
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
    writeln("Testing immediate resolution");
    auto p = new Promise!int((resolve, reject) {
        resolve(999);
    });

    assert(p.await() == 999);
}

///  Test immediate rejection
unittest {
    writeln("Testing immediate rejection");
    auto p = new Promise!int((resolve, reject) {
        reject(new Exception("Immediate"));
    });

    assertThrown!Exception(p.await());
}

///  Test nested promise execution
unittest {
    writeln("Testing nested promise execution");
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
    writeln("Testing promise with float type");
    auto p = new Promise!double((resolve, reject) {
        resolve(3.14159);
    });

    auto result = p.await();
    assert(result > 3.14 && result < 3.15);
}

///  Test promise with array type
unittest {
    writeln("Testing promise with array type");
    auto p = new Promise!(int[])((resolve, reject) {
        resolve([1, 2, 3, 4, 5]);
    });

    auto result = p.await();
    assert(result.length == 5);
    assert(result[2] == 3);
}

///  Test exception with empty message
unittest {
    writeln("Testing exception with empty message");
    auto p = new Promise!int((resolve, reject) {
        reject(new Exception(""));
    });

    assertThrown!Exception(p.await());
}

/// Test Promise.all with empty range
unittest {
    writeln("Testing Promise.all with empty range");
    Promise!int[] promises = [];
    auto p = Promise!().all!int(promises);
    auto result = p.await();
    assert(result.length == 0);
}

/// Test Promise.all with single promise
unittest {
    writeln("Testing Promise.all with single promise");
    auto promises = [
        Promise!int.resolve(42)
    ];
    auto p = Promise!().all!int(promises);
    auto result = p.await();
    assert(result.length == 1);
    assert(result[0] == 42);
}

/// Test Promise.all with multiple fulfilled promises
unittest {
    writeln("Testing Promise.all with multiple fulfilled promises");
    auto promises = [
        new Promise!int((resolve, reject) {
            Thread.sleep(dur!"msecs"(10));
            resolve(1);
        }),
        new Promise!int((resolve, reject) {
            Thread.sleep(dur!"msecs"(5));
            resolve(2);
        }),
        new Promise!int((resolve, reject) {
            Thread.sleep(dur!"msecs"(15));
            resolve(3);
        })
    ];

    auto p = Promise!().all!int(promises);
    auto result = p.await();

    assert(result.length == 3);
    assert(result[0] == 1);
    assert(result[1] == 2);
    assert(result[2] == 3);
}

/// Test Promise.all maintains order
unittest {
    writeln("Testing Promise.all maintains order");
    auto promises = [
        new Promise!int((resolve, reject) {
            Thread.sleep(dur!"msecs"(30));
            resolve(100);
        }),
        new Promise!int((resolve, reject) {
            Thread.sleep(dur!"msecs"(10));
            resolve(200);
        }),
        new Promise!int((resolve, reject) {
            Thread.sleep(dur!"msecs"(20));
            resolve(300);
        })
    ];

    auto p = Promise!().all!int(promises);
    auto result = p.await();

    assert(result[0] == 100);
    assert(result[1] == 200);
    assert(result[2] == 300);
}

/// Test Promise.all rejects if any promise rejects
unittest {
    writeln("Testing Promise.all rejects if any promise rejects");
    auto promises = [
        Promise!int.resolve(1),
        new Promise!int((resolve, reject) {
            Thread.sleep(dur!"msecs"(10));
            reject(new Exception("Failed"));
        }),
        Promise!int.resolve(3)
    ];

    auto p = Promise!().all!int(promises);

    assertThrown!Exception(p.await());
}

/// Test Promise.all rejects with first rejection
unittest {
    writeln("Testing Promise.all rejects with first rejection");
    auto promises = [
        new Promise!int((resolve, reject) {
            Thread.sleep(dur!"msecs"(20));
            reject(new Exception("Second"));
        }),
        new Promise!int((resolve, reject) {
            Thread.sleep(dur!"msecs"(10));
            reject(new Exception("First"));
        }),
        Promise!int.resolve(3)
    ];

    auto p = Promise!().all!int(promises);

    assertThrown!Exception(p.await());
}

/// Test Promise.all with mix of immediate and delayed promises
unittest {
    writeln("Testing Promise.all with mix of immediate and delayed promises");
    auto promises = [
        Promise!int.resolve(10),
        new Promise!int((resolve, reject) {
            Thread.sleep(dur!"msecs"(10));
            resolve(20);
        }),
        Promise!int.resolve(30)
    ];

    auto p = Promise!().all!int(promises);
    auto result = p.await();

    assert(result[0] == 10);
    assert(result[1] == 20);
    assert(result[2] == 30);
}

/// Test Promise.all with string type
unittest {
    writeln("Testing Promise.all with string type");
    auto promises = [
        Promise!string.resolve("Hello"),
        Promise!string.resolve("World"),
        Promise!string.resolve("!")
    ];

    auto p = Promise!().all!string(promises);
    auto result = p.await();

    assert(result[0] == "Hello");
    assert(result[1] == "World");
    assert(result[2] == "!");
}

/// Test Promise.all void with empty range
unittest {
    writeln("Testing Promise.all void with empty range");
    Promise!void[] promises = [];
    auto p = Promise!().all!void(promises);
    p.await();
}

/// Test Promise.all void with single promise
unittest {
    writeln("Testing Promise.all void with single promise");
    auto promises = [
        Promise!void.resolve()
    ];
    auto p = Promise!().all!void(promises);
    p.await();
}

/// Test Promise.all void with multiple fulfilled promises
unittest {
    writeln("Testing Promise.all void with multiple fulfilled promises");
    bool flag1 = false;
    bool flag2 = false;
    bool flag3 = false;

    auto promises = [
        new Promise!void((resolve, reject) {
            Thread.sleep(dur!"msecs"(10));
            flag1 = true;
            resolve();
        }),
        new Promise!void((resolve, reject) {
            Thread.sleep(dur!"msecs"(5));
            flag2 = true;
            resolve();
        }),
        new Promise!void((resolve, reject) {
            Thread.sleep(dur!"msecs"(15));
            flag3 = true;
            resolve();
        })
    ];

    auto p = Promise!().all!void(promises);
    p.await();

    assert(flag1);
    assert(flag2);
    assert(flag3);
}

/// Test Promise.all void rejects if any promise rejects
unittest {
    writeln("Testing Promise.all void rejects if any promise rejects");
    auto promises = [
        Promise!void.resolve(),
        new Promise!void((resolve, reject) {
            Thread.sleep(dur!"msecs"(10));
            reject(new Exception("Void failed"));
        }),
        Promise!void.resolve()
    ];

    auto p = Promise!().all!void(promises);

    assertThrown!Exception(p.await());
}

/// Test Promise.all void with mix of immediate and delayed promises
unittest {
    writeln("Testing Promise.all void with mix of immediate and delayed promises");
    bool delayed = false;

    auto promises = [
        Promise!void.resolve(),
        new Promise!void((resolve, reject) {
            Thread.sleep(dur!"msecs"(10));
            delayed = true;
            resolve();
        }),
        Promise!void.resolve()
    ];

    auto p = Promise!().all!void(promises);
    p.await();

    assert(delayed);
}

/// Test Promise.all with large number of promises
unittest {
    writeln("Testing Promise.all with large number of promises");
    Promise!int[] promises;
    foreach (i; 0..200) {
        promises ~= Promise!int.resolve(cast(int)i);
    }

    auto p = Promise!().all!int(promises);
    auto result = p.await();

    assert(result.length == 200);
    foreach (i; 0..200) {
        assert(result[i] == i);
    }
}

/// Test Promise.all doesn't wait for remaining promises after rejection
unittest {
    writeln("Testing Promise.all doesn't wait for remaining promises after rejection");
    import std.datetime.stopwatch : AutoStart, StopWatch;

    auto promises = [
        new Promise!int((resolve, reject) {
            Thread.sleep(dur!"msecs"(10));
            reject(new Exception("Fast fail"));
        }),
        new Promise!int((resolve, reject) {
            Thread.sleep(dur!"msecs"(100));
            resolve(2);
        })
    ];

    auto sw = StopWatch(AutoStart.yes);
    auto p = Promise!().all!int(promises);

    assertThrown!Exception(p.await());
    sw.stop();
    assert(sw.peek().total!"msecs" < 80);
}

///  Test basic promise fulfillment by returning value in executor
unittest {
    writeln("Testing basic promise fulfillment by returning value in executor");
    auto p = new Promise!int(() {
        Thread.sleep(10.msecs);
        return 42;
    });

    assert(p.await() == 42);
}

///  Test basic promise rejection by throwing exception in executor
unittest {
    writeln("Testing basic promise fulfillment by throwing exception in executor");
    auto p = new Promise!int(() {
        Thread.sleep(10.msecs);
        throw new Exception("Rejected");
        return 42;
    });

    assertThrown!Exception(p.await());
}

///  Test basic void promise fulfillment without resolve/reject in executor
unittest {
    writeln("Testing basic void promise fulfillment without resolve/reject in executor");
    auto a = true;
    auto p = new Promise!void(() {
        Thread.sleep(10.msecs);
        a = false;
        return;
    });
    assert(a);
    p.await();
    assert(!a);
}

/// Test Promise.race resolves with first settled promise
unittest {
    writeln("Testing Promise.race resolves with first settled promise");
    foreach (_; parallel(iota(0, 100))) {
        auto p = Promise!int.race([
            new Promise!int((resolve, reject) {
                Thread.sleep(dur!"msecs"(30));
                resolve(1);
            }),
            new Promise!int((resolve, reject) {
                Thread.sleep(dur!"msecs"(10));
                resolve(2);
            }),
            new Promise!int((resolve, reject) {
                Thread.sleep(dur!"msecs"(20));
                resolve(3);
            })
        ]);
        assert(p.await() == 2);
    }
}

/// Test Promise.race rejects with first settled promise
unittest {
    writeln("Testing Promise.race rejects with first settled promise");
    foreach (_; parallel(iota(0, 100))) {
        auto p = Promise!void.race([
            new Promise!void((resolve, reject) {
                Thread.sleep(dur!"msecs"(30));
                reject(new Exception("One"));
            }),
            new Promise!void((resolve, reject) {
                Thread.sleep(dur!"msecs"(10));
                reject(new Exception("Two"));
            }),
            new Promise!void((resolve, reject) {
                Thread.sleep(dur!"msecs"(20));
                reject(new Exception("Three"));
            })
        ]);
        assert(collectExceptionMsg(p.await()) == "Two");
    }
}

/// Test Promise.race with all pre-resolved promises
unittest {
    writeln("Testing Promise.race with all pre-resolved promises");
    foreach (_; parallel(iota(0, 100))) {
        auto p = Promise!int.race([
            Promise!int.resolve(1),
            Promise!int.resolve(2),
            Promise!int.resolve(3)
        ]);
        assert(p.await() == 1);
    }
}

/// Test Promise.race with all pre-rejected promises
unittest {
    writeln("Testing Promise.race with all pre-rejected promises");
    foreach (_; parallel(iota(0, 100))) {
        auto p = Promise!int.race([
            Promise!int.reject(new Exception("First")),
            Promise!int.reject(new Exception("Second")),
            Promise!int.reject(new Exception("Third"))
        ]);
        assert(collectExceptionMsg(p.await()) == "First");
    }
}

/// Test Promise.race with a mix of pending and fulfilled promises
unittest {
    writeln("Testing Promise.race with a mix of pending and fulfilled promises");
    foreach (_; parallel(iota(0, 100))) {
        auto resolved = new Promise!int(() {
            Thread.sleep(dur!"msecs"(5));
            return 2;
        });
        Thread.sleep(dur!"msecs"(10));
        auto promises = [
            new Promise!int(() {
                Thread.sleep(dur!"msecs"(20));
                return 1;
            }),
            resolved,
            Promise!int.resolve(3),
            new Promise!int(() {
                Thread.sleep(dur!"msecs"(5));
                return 4;
            }),
        ];
        auto p = Promise!int.race(promises);
        assert(p.await() == 2);
    }
}
