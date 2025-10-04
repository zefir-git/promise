module promise;

import core.sync.mutex;
import core.sync.condition;
import core.thread.osthread;

public class Promise(T) {
    private {
        State state;
        static if (!is(T == void))
            T fulfillmentValue;
        Exception rejectionReason;
        Mutex mutex;
        Condition condition;
        Thread executorThread;
    }

    private static enum State {
        PENDING,
        FULFILLED,
        REJECTED,
    }

    static if (is(T == void))
        public alias Resolve = void delegate();
    else
        public alias Resolve = void delegate(T);

    public alias Reject = void delegate(Exception);
    public alias Executor = void delegate(Resolve, Reject);

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

        executorThread = new Thread(() {
            try {
                executor(resolve, reject);
            }
            catch (Exception e) {
                reject(e);
            }
        });
        executorThread.start();
    }

    private this() {}

    static if (is(T == void)) public static Promise!T resolve() {
        auto promise = new Promise!T();
        promise.mutex = new Mutex();
        promise.state = State.FULFILLED;
        return promise;
    }
    else public static Promise!T resolve(T value) {
        auto promise = new Promise!T();
        promise.mutex = new Mutex();
        promise.state = State.FULFILLED;
        promise.fulfillmentValue = value;
        return promise;
    }

    public static Promise!T reject(T)(Exception reason) {
        auto promise = new Promise!T();
        promise.mutex = new Mutex();
        promise.state = State.REJECTED;
        promise.rejectionReason = reason;
        return promise;
    }

    public T await() {
        synchronized(mutex) {
            while (state == State.PENDING)
                condition.wait();

            if (state == State.REJECTED)
                throw rejectionReason;

            static if (is(T == void))
                return;
            return fulfillmentValue;
        }
    }

    public Promise!U catch_(U)(U delegate(Exception) onRejected) {
        return then(null, onRejected);
    }

    public Promise!T finally_(void delegate() onFinally) {
        static if(is(T == void))
            return then!void(() {
                onFinally();
            }, (error) {
                onFinally();
                throw error;
            });
            
        return then!T((value) {
            onFinally();
            return value;
        }, (error) {
            onFinally();
            return throw error;
        });
    }

    static if (is(T == void)) {
        private void _resolve() {
            synchronized(mutex) {
                if (state != State.PENDING) return;
                state = State.FULFILLED;
                condition.notifyAll();
            }
        }

        public Promise!U then(U)(U delegate() onFulfilled, U delegate(Exception) onRejected) {
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
                else resolve();
            });
        }

        public Promise!U then(U)(U delegate() onFulfilled) {
            return then(onFulfilled, null);
        }
    }

    else {
        private void _resolve(T value) {
            synchronized(mutex) {
                if (state != State.PENDING) return;
                state = State.FULFILLED;
                fulfillmentValue = value;
                condition.notifyAll();
            }
        }

        public Promise!U then(U)(U delegate(T) onFulfilled, U delegate(Exception) onRejected) {
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
                else resolve(result);
            });
        }

        public Promise!U then(U)(U delegate(T) onFulfilled) {
            return then(onFulfilled, null);
        }
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
