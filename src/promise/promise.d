module promise;

import core.atomic;
import core.sync.condition;
import core.sync.mutex;
import std.parallelism;
import std.array;
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

    private static enum State {
        PENDING,
        FULFILLED,
        REJECTED,
    }

    public static Promise!(U[]) all(U)(Promise!U[] promises) if (!is(U == void)) {
        return new Promise!(U[])((resolve, reject) {
            U[] values = new U[promises.length];

            if (promises.length == 0) {
                resolve(values);
                return;
            }

            shared size_t remaining = promises.length;
            shared bool done = false;
            Exception rejection;
            Mutex mtx = new Mutex();

            /**
             * Returns: Whether to continue scheduling more promises.
             */
            bool schedule(size_t index, Promise!U promise) {
                if (atomicLoad(done))
                    return false;
                promise.then!void((value) {
                    synchronized(mtx) {
                        if (done) return;
                        values[index] = value;
                        atomicOp!"-="(remaining, 1);
                        if (remaining == 0)
                            done = true;
                        else return;
                    }
                    resolve(values);
                    return;
                }, (err) {
                    synchronized(mtx) {
                        if (done) return;
                        done = true;
                        rejection = err;
                    }
                    reject(err);
                    throw err;
                });
                return true;
            }

            foreach (i, p; promises)
                if (!schedule(i, p))
                    break;
        });
    }

    public static Promise!U all(U)(Promise!U[] promises) if (is(U == void)) {
        return new Promise!U((resolve, reject) {
            if (promises.length == 0) {
                resolve();
                return;
            }

            shared size_t remaining = promises.length;
            shared bool done = false;
            Mutex mtx = new Mutex();

            /**
             * Returns: Whether to continue scheduling more promises.
             */
            bool schedule(size_t index, Promise!U promise) {
                promise.then!void(() {
                    synchronized(mtx) {
                        if (done) return;
                        atomicOp!"-="(remaining, 1);
                        if (remaining == 0)
                            done = true;
                        else return;
                    }
                    resolve();
                    return;
                }, (err) {
                    synchronized(mtx) {
                        if (done) return;
                        done = true;
                    }
                    reject(err);
                    throw err;
                });
                return true;
            }

            foreach (i, p; promises)
                if (!schedule(i, p))
                    break;
        });
    }

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

        /**
         * Fulfills the promise.
         */
        public alias Resolve = void delegate();

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

        /**
         * Fulfills the promise with the provided value.
         *
         * Params:
         *   value = Value to fulfill the promise with.
         */
        public alias Resolve = void delegate(T value);

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
     * Rejects the promise.
     *
     * Params:
     *   reason = Reason the promise was rejected.
     */
    public alias Reject = void delegate(Exception reason);

    /**
     * Executes custom code asynchronously that ties an outcome in a callback to a Promise.
     *
     * The promise can only be settled once. The first call to either `resolve()` or `reject()` settles the promise;
     * subsequent calls to either function are ignored.
     *
     * Params:
     *   resolve = Function to call to fulfill the promise with a value.
     *   reject = Function to call to reject the promise with a reason.
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
     * Returns: Immediately a new Promise which is pending (regardless of the current promise’s status). If the original
     *          Promise is rejected, this promise resolves to the value returned by the `onRejected` delegate or rejects
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
