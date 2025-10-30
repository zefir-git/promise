module promise;

import core.atomic;
import core.sync.condition;
import core.sync.event;
import core.sync.mutex;
import std.array;
import std.parallelism;
import std.range;
import std.traits;

/**
 * Represents the eventual completion (or failure) of an asynchronous operation.
 */
public class Promise(T = void) {
    private {
        State state;
        static if (!is(T == void))
            T fulfillmentValue;
        Exception rejectionReason;
        Mutex mutex;
        Condition condition;
    }

    private static const enum State {
        PENDING,
        FULFILLED,
        REJECTED,
    }

    /**
     * Creates a Promise that fulfills when all of the provided Promises have been fulfilled, or rejects as soon as any
     * of them reject.
     *
     * Params:
     *   promises = Array of Promises to observe.
     * Returns: Promise that fulfills with an array containing the fulfillment values of all input Promises, in the
     *          same order as provided. If any input Promise rejects, the returned Promise rejects immediately with that
     *          rejection reason.
     */
    public static Promise!(U[]) all(U)(Promise!U[] promises) if (!is(U == void)) {
        if (promises.length == 0)
            return Promise!(U[]).resolve([]);
        return new Promise!(U[])((resolve, reject) {
            U[] values = new U[promises.length];
            shared size_t remaining = promises.length;
            shared bool done = false;

            bool schedule(size_t index, Promise!U promise) {
                if (atomicLoad(done))
                    return false;
                promise.then!void((value) {
                    values[index] = value;
                    if (atomicOp!"-="(remaining, 1) == 0 && cas(&done, false, true)) {
                        resolve(values);
                    }
                }, (err) {
                    if (cas(&done, false, true)) {
                        reject(err);
                        throw err;
                    }
                });
                return true;
            }

            foreach (i, p; promises)
                if (!schedule(i, p))
                    break;
        });
    }

    /**
     * Creates a Promise that fulfills when all of the provided Promises have been fulfilled, or rejects as soon as any
     * of them reject.
     *
     * Params:
     *   promises = Array of Promises to observe.
     * Returns: Promise that fulfills when all input Promises are fulfilled. If any input Promise rejects, the
     *          returned Promise rejects immediately with that rejection reason.
     */
    public static Promise!U all(U)(Promise!U[] promises) if (is(U == void)) {
        if (promises.length == 0)
            return Promise!void.resolve();
        return new Promise!U((resolve, reject) {
            shared size_t remaining = promises.length;
            shared bool done = false;

            bool schedule(size_t index, Promise!U promise) {
                if (atomicLoad(done))
                    return false;
                promise.then!void(() {
                    if (atomicOp!"-="(remaining, 1) == 0 && cas(&done, false, true))
                        resolve();
                }, (err) {
                    if (cas(&done, false, true)) {
                        reject(err);
                        throw err;
                    }
                });
                return true;
            }

            foreach (i, p; promises)
                if (!schedule(i, p))
                    break;
        });
    }

    /**
     * Creates a Promise that fulfills when all of the provided Promises have settled (either fulfilled or rejected).
     *
     * Params:
     *   promises = Array of Promises to observe.
     * Returns: Promise that fulfills with an array containing the results of all input Promises, in the same order as
     *          as provided. Each element in the array is either a `PromiseFulfilledResult!T` or
     *          `PromiseRejectedResult`. The returned Promise never rejects.
     */
    public static Promise!(PromiseSettledResult[]) allSettled(Promise!T[] promises) {
        if (promises.length == 0)
            return Promise!(PromiseSettledResult[]).resolve([]);

        return new Promise!(PromiseSettledResult[])((resolve, reject) {
            PromiseSettledResult[] values = new PromiseSettledResult[promises.length];
            shared size_t remaining = promises.length;

            void schedule(size_t index, Promise!T promise) {
                static if (is(T == void))
                    promise = promise.then(() {
                        values[index] = new PromiseFulfilledResult!void();
                    });
                else
                    promise = promise.then((val) {
                        values[index] = new PromiseFulfilledResult!T(val);
                        return val;
                    });
                promise.catch_((e) {
                    values[index] = new PromiseRejectedResult(e);
                    return throw e;
                }).finally_(() {
                    if (atomicOp!"-="(remaining, 1) == 0)
                        resolve(values);
                });
            }

            foreach (i, p; promises)
                schedule(i, p);
        });
    }

    /**
     * Creates a Promise that fulfills when any of the provided Promises fulfills, with the fulfillment value of the
     * first one that does. It rejects when none of the Promises are fulfilled (including when an empty array is
     * passed), with an `AggregateException` containing the rejection reasons in the order the Promises were provided.
     *
     * Params:
     *   promises = Array of Promises to observe.
     */
    public static Promise!T any(Promise!T[] promises) {
        if (promises.length == 0)
            return Promise!T.reject(new AggregateException([], "No Promise in Promise.any was resolved"));
        return new Promise!T((resolve, reject) {
            shared bool done = false;
            shared size_t remaining = promises.length;
            Exception[] exceptions = new Exception[promises.length];

            bool schedule(size_t index, Promise!T promise) {
                if (atomicLoad(done))
                    return false;

                // settled promises are checked on this promise thread to avoid racing
                if (promise.state != State.PENDING) {
                    try {
                        static if (is(T == void)) {
                            promise.await();
                            resolve();
                        }
                        else
                            resolve(promise.await());
                    }
                    catch (Exception e) {
                        import std.stdio;
                        exceptions[index] = e;
                        if (atomicOp!"-="(remaining, 1) == 0 && cas(&done, false, true))
                            reject(new AggregateException(exceptions, "No Promise in Promise.any was resolved"));
                    }
                    return true;
                }

                static if (is(T == void))
                    promise.then!void(() {
                        if (cas(&done, false, true))
                            resolve();
                    }).catch_((Exception e) {
                        exceptions[index] = e;
                        if (atomicOp!"-="(remaining, 1) == 0 && cas(&done, false, true))
                            reject(new AggregateException(exceptions, "No Promise in Promise.any was resolved"));
                    });
                else
                    promise.then!void((T value) {
                        if (cas(&done, false, true))
                            resolve(value);
                    }).catch_((Exception e) {
                        exceptions[index] = e;
                        if (atomicOp!"-="(remaining, 1) == 0 && cas(&done, false, true))
                            reject(new AggregateException(exceptions, "No Promise in Promise.any was resolved"));
                    });

                return true;
            }

            foreach(i, p; promises)
                if (!schedule(i, p))
                    break;
        });
    }

    /**
     * Creates a Promise that fulfills or rejects with the outcome of the first Promise to settle.
     *
     * Params:
     *   promises = Array of Promises to observe.
     * Returns: A Promise that settles with the state of the first Promise in the array to settle: it fulfills if that
     *         Promise fulfills, or rejects if that Promise rejects. If the array is empty, the returned Promise remains
     *         pending indefinitely.
     */
    public static Promise!T race(Promise!T[] promises) {
        return new Promise!T((resolve, reject) {
            shared bool done = false;

            bool schedule(Promise!T promise) {
                if (atomicLoad(done))
                    return false;

                // settled promises are checked on this promise thread to avoid racing
                if (promise.state != State.PENDING) {
                    if (cas(&done, false, true)) {
                        try {
                            static if (is(T == void)) {
                                promise.await();
                                resolve();
                            }
                            else
                                resolve(promise.await());
                        }
                        catch (Exception e)
                            reject(e);
                    }
                    return false;
                }

                static if (is(T == void)) promise.then!void(() {
                    if (cas(&done, false, true))
                        resolve();
                }).catch_((Exception e) {
                    if (cas(&done, false, true))
                        reject(e);
                });

                else promise.then!void((T value) {
                    if (cas(&done, false, true))
                        resolve(value);
                }).catch_((Exception e) {
                    if (cas(&done, false, true))
                        reject(e);
                });

                return true;
            }

            foreach (p; promises)
                if (!schedule(p))
                    break;
        });
    }

    /**
     * Creates a Promise that fulfills with the return value of the provided delegate, or rejects if the delegate throws
     * an exception.
     *
     * Params:
     *   func = Delegate to call with the arguments provided in `args`.
     *   args = Arguments to pass to the `func` delegate.
     * Returns: Promise that fulfills with the value returned by `func`, or rejects with any exception thrown during its
     *          execution.
     */
    public static Promise!T try_(Args...) (T delegate(Args) func, auto ref Args args) {
        return new Promise!T(() {
            return func(args);
        });
    }

    /** 
     * Creates an object that contains a new `Promise` and two functions to resolve or reject it.
     */
    public static PromiseWithResolvers!T withResolvers() {
        Resolve resolve;
        Reject reject;
        Event event;
        
        event.initialize(manualReset: true, initialState: false);
        
        auto promise = new Promise!T((s, j) {
            resolve = s;
            reject = j;
            event.setIfInitialized();
        });
        event.wait();
        return new PromiseWithResolvers!T(promise, resolve, reject);
    }

    public static alias Resolve = PrivateResolve!T;

    static if (is(T == void)) {
        /**
         * Creates a void Promise that is already resolved.
         */
        public static Promise!T resolve() {
            auto promise = new Promise!T();
            promise.mutex = new Mutex();
            promise.state = State.FULFILLED;
            return promise;
        }

        private void _resolve() {
            synchronized(mutex) {
                if (state != State.PENDING) return;
                state = State.FULFILLED;
                condition.notifyAll();
            }
        }

        /**
         * Appends fulfillment and rejection handlers to the Promise.
         *
         * Params:
         *   onFulfilled = Delegate to asynchronously execute when this Promise becomes fulfilled. Its return value
         *                 becomes the fulfillment value of the Promise returned by this method.
         *   onRejected = Delegate to asynchronously execute when this Promise becomes rejected. Its return value becomes
         *                the fulfillment value of the Promise returned by this method. The delegate is called with a
         *                `reason` argument indicating the rejection reason.
         * Returns: Immediately a new Promise that resolves to the return value of the called handler, or settles with
         *          the same outcome as the original Promise if not handled.
         */
        public Promise!U then(U)(U delegate() onFulfilled, U delegate(Exception) onRejected) {
            assert(onFulfilled !is null || is(U == void), "Promise!void.then!" ~ U.stringof ~ "() called with no "
                ~ "onFulfilled handler: cannot produce " ~ U.stringof ~ " from void.");
            return new Promise!U((resolve, reject) {
                try {
                    await();
                }
                catch (Exception e) {
                    if (onRejected !is null)
                        static if (is(U == void)) {
                            onRejected(e);
                            resolve();
                        }
                        else resolve(onRejected(e));
                    else reject(e);

                    return;
                }

                if (onFulfilled !is null) {
                    static if (is(U == void)) {
                        onFulfilled();
                        resolve();
                    }
                    else resolve(onFulfilled());
                }
                else static if(is(U == void))
                    resolve();
            });
        }

        /**
         * Appends a fulfillment handler to the Promise.
         *
         * Params:
         *   onFulfilled = Delegate to asynchronously execute when this Promise becomes fulfilled. Its return value
         *                 becomes the fulfillment value of the Promise returned by this method.
         * Returns: Immediately a new Promise that resolves to the return value of the called handler, or settles with
         *          the same outcome as the original Promise if not handled.
         */
        public Promise!U then(U)(U delegate() onFulfilled) {
            return then(onFulfilled, null);
        }
    }

    else {
        /**
         * Resolves the given value to a Promise. If the value is a Promise, that Promise is returned.
         *
         * Params:
         *     value = Value to be resolved.
         */
        public static Promise!T resolve(T value) {
            static if (is(T == Promise))
                return value;
            auto promise = new Promise!T();
            promise.mutex = new Mutex();
            promise.state = State.FULFILLED;
            promise.fulfillmentValue = value;
            return promise;
        }

        private void _resolve(T value) {
            synchronized(mutex) {
                if (state != State.PENDING) return;
                state = State.FULFILLED;
                fulfillmentValue = value;
                condition.notifyAll();
            }
        }

        /**
         * Appends fulfillment and rejection handlers to the Promise.
         *
         * Params:
         *   onFulfilled = Delegate to asynchronously execute when this Promise becomes fulfilled. Its return value
         *                 becomes the fulfillment value of the Promise returned by this method. The delegate is called
         *                 with a `value` argument indicating the fulfillment value of the original Promise.
         *   onRejected = Delegate to asynchronously execute when this Promise becomes rejected. Its return value becomes
         *                the fulfillment value of the Promise returned by this method. The delegate is called with a
         *                `reason` argument indicating the rejection reason.
         * Returns: Immediately a new Promise that resolves to the return value of the called handler, or settles with
         *          the same outcome as the original Promise if not handled.
         */
        public Promise!U then(U)(U delegate(T) onFulfilled, U delegate(Exception) onRejected) {
            assert(onFulfilled !is null || is(U == void) || is(U == T), "Promise!" ~ T.stringof ~ ".then!" ~ U.stringof
            ~ "() called with no onFulfilled handler: cannot produce " ~ U.stringof ~ " from " ~ T.stringof ~ ".");
            return new Promise!U((resolve, reject) {
                T result;
                try {
                    result = await();
                }
                catch (Exception e) {
                    if (onRejected !is null)
                        static if (is(U == void)) {
                            onRejected(e);
                            resolve();
                        }
                        else resolve(onRejected(e));
                    else reject(e);

                    return;
                }

                if (onFulfilled !is null) {
                    static if (is(U == void)) {
                        onFulfilled(result);
                        resolve();
                    }
                    else resolve(onFulfilled(result));
                }
                else {
                    static if (is(U == void))
                        resolve();
                    else static if (is(U == T))
                        resolve(result);
                }
            });
        }

        /**
         * Appends fulfillment and rejection handlers to the Promise.
         *
         * Params:
         *   onFulfilled = Delegate to asynchronously execute when this Promise becomes fulfilled. Its return value
         *                 becomes the fulfillment value of the Promise returned by this method. The delegate is called
         *                 with a `value` argument indicating the fulfillment value of the original Promise.
         * Returns: Immediately a new Promise that resolves to the return value of the called handler, or settles with
         *          the same outcome as the original Promise if not handled.
         */
        public Promise!U then(U)(U delegate(T) onFulfilled) {
            return then(onFulfilled, null);
        }
    }

    /**
     * Rejects the Promise.
     *
     * Params:
     *   reason = Reason the Promise was rejected.
     */
    public alias Reject = void delegate(Exception reason);

    /**
     * Executes custom code asynchronously that ties an outcome in a callback to a Promise.
     *
     * The Promise can only be settled once. The first call to either `resolve()` or `reject()` settles the Promise;
     * subsequent calls to either function are ignored.
     *
     * Params:
     *   resolve = Function to call to fulfill the Promise with a value.
     *   reject = Function to call to reject the Promise with a reason.
     */
    public alias Executor = void delegate(Resolve resolve, Reject reject);

    /**
     * Creates a new Promise instance.
     *
     * Params:
     *   executor = Delegate to be executed asynchronously. It receives `resolve` and `reject` functions to control the
     *              outcome of the Promise. Any exception thrown inside the `executor` will cause the Promise to be
     *              rejected with that exception as reason.
     */
    public this(Executor executor) {
        state = State.PENDING;
        mutex = new Mutex();
        condition = new Condition(mutex);

        Resolve resolve;
        static if (is(T == void))
            resolve = () => this._resolve();
        else
            resolve = (value) => this._resolve(value);

        Reject reject = (reason) => this._reject(reason);

        auto task = task({
            try {
                executor(resolve, reject);
            }
            catch (Exception e) {
                reject(e);
            }
        });
        task.executeInNewThread();
    }

    /**
     * Creates a new Promise instance.
     *
     * Params:
     *   executor = Delegate to be executed asynchronously. Its return value, if any, will be used to resolve the
     *              Promise. Any exception thrown inside the `executor` will cause the Promise to be rejected with that
     *              exception as reason.
     */
    public this(T delegate() executor) {
        state = State.PENDING;
        mutex = new Mutex();
        condition = new Condition(mutex);

        Resolve resolve;
        static if (is(T == void))
            resolve = () => this._resolve();
        else
            resolve = (value) => this._resolve(value);

        Reject reject = (reason) => this._reject(reason);

        auto task = task({
            static if (is(T == void))
                try {
                    executor();
                    resolve();
                }
                catch (Exception e)
                    reject(e);
            else try
                resolve(executor());
            catch (Exception e)
                reject(e);
        });
        task.executeInNewThread();
    }

    private this() {}

    /**
     * Creates a Promise that is rejected with a given reason.
     *
     * Params:
     *   reason = Reason why this Promise rejected.
     */
    public static Promise!T reject(Exception reason) {
        auto promise = new Promise!T();
        promise.mutex = new Mutex();
        promise.state = State.REJECTED;
        promise.rejectionReason = reason;
        return promise;
    }

    /**
     * Waits for this Promise (by blocking the calling thread) to be fulfilled or rejected.
     *
     * Returns: The fulfillment value of this Promise.
     * Throws: Exception as rejection reason if the Promise is rejected.
     */
    public T await() {
        synchronized(mutex) {
            while (state == State.PENDING)
                condition.wait();

            if (state == State.REJECTED)
                throw rejectionReason;

            static if (is(T == void))
                return;
            else return this.fulfillmentValue;
        }
    }

    /**
     * Schedules a delegate to be called when the Promise is rejected. It is a shortcut for `then(null, onRejected)`.
     *
     * Params:
     *   onRejected = Delegate to asynchronously execute when this Promise becomes rejected. Its return value becomes
     *                the fulfillment value of the Promise returned by this method. The delegate is called with a
     *                `reason` argument indicating the rejection reason.
     * Returns: Immediately a new Promise which is pending (regardless of the current Promise’s status). If the original
     *          Promise is rejected, this Promise resolves to the value returned by the `onRejected` delegate or rejects
     *          with the reason thrown by it, otherwise it fulfills with the same value as the original Promise.
     */
    public Promise!T catch_(T delegate(Exception) onRejected) {
        return then(null, onRejected);
    }

    /**
     * Schedules a delegate to be called when the Promise is settled (either fulfilled or rejected).
     *
     * Params:
     *   onFinally = Delegate to asynchronously execute when this Promise becomes settled.
     * Returns: Immediately a new Promise which is pending (regardless of the current Promise’s status). If `onFinally`
     *          throws an exception, the Promise rejects with that exception, otherwise will settle with the same state
     *          and value (or reason) as the original Promise.
     */
    public Promise!T finally_(void delegate() onFinally) {
        static if(is(T == void))
            return then!void(() {
                onFinally();
            }, (error) {
                onFinally();
                throw error;
            });

        else return then!T((value) {
            onFinally();
            return value;
        }, (error) {
            onFinally();
            return throw error;
        });
    }

    private void _reject(Exception reason) {
        synchronized(mutex) {
            if (state != State.PENDING) return;
            state = State.REJECTED;
            rejectionReason = reason;
            condition.notifyAll();
        }
    }
}

/**
 * Fulfills the Promise.
 */
private template PrivateResolve(T) {
    static if (is(T == void))
        /**
         * Fulfills the Promise.
         */
        alias PrivateResolve = void delegate();
    else
        /**
         * Fulfills the Promise with the provided value.
         *
         * Params:
         *   value = Value to fulfill the Promise with.
         */
        alias PrivateResolve = void delegate(T value);
}

/**
 * Represents the outcome of a settled Promise.
 */
public abstract class PromiseSettledResult {
    /**
     * Represents the state of a settled Promise.
     */
    public static const enum Status {
        FULFILLED = Promise!().State.FULFILLED,
        REJECTED = Promise!().State.REJECTED,
    }

    /**
     * State of the settled Promise.
     */
    public const PromiseSettledResult.Status status;

    private this(PromiseSettledResult.Status status) {
        this.status = status;
    }
}

/**
 * Represents the outcome of a fulfilled Promise.
 */
public final class PromiseFulfilledResult(T) : PromiseSettledResult {
    static if (is(T == void))
        private this() {
            super(PromiseSettledResult.Status.FULFILLED);
        }

    else {
        /**
         * Fulfillment value of the Promise.
         */
        public const T value;

        private this(T value) {
            super(PromiseSettledResult.Status.FULFILLED);
            this.value = value;
        }
    }
}

/**
 * Represents the outcome of a rejected Promise.
 */
public final class PromiseRejectedResult : PromiseSettledResult {
    /**
     * Rejection reason of the Promise.
     */
    public const Exception reason;

    private this(Exception reason) {
        super(PromiseSettledResult.Status.REJECTED);
        this.reason = reason;
    }
}

/**
 * Represents multiple exceptions as a single object.
 */
public class AggregateException : Exception {
    /**
     * Array representing the exceptions that were aggregated.
     */
    public Exception[] exceptions;

    /**
     * Constructs a new AggregateException.
     *
     * Params:
     *   exceptions = Exceptions to include in this aggregate.
     *   message    = Message describing this aggregate exception.
     */
    public this(Exception[] exceptions, string message) {
        super(message);
        this.exceptions = exceptions;
    }
}

/** 
 * Represents a promise with its associated resolve and reject functions.
 */
public final class PromiseWithResolvers(T) {
    private Promise!T _promise;

    /** 
     * Promise instance. 
     */
    public @property Promise!T promise() {
        return _promise;
    }

    /** 
     * Function for fulfilling the promise. 
     */
    public Promise!T.Resolve resolve;

    /** 
     * Function for rejecting the promise. 
     */
    public Promise!T.Reject reject;

    private this(Promise!T promise, Promise!T.Resolve resolve, Promise!T.Reject reject) {
        this._promise = promise;
        this.resolve = resolve;
        this.reject = reject;
    }
}
