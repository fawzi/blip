/**
 * The mutex module provides a primitive for maintaining mutually exclusive
 * access.
 * Modified to have a binary lock
 *
 * Copyright: Copyright (C) 2005-2006 Sean Kelly.  All rights reserved.
 * License:   BSD style: $(LICENSE)
 * Authors:   Sean Kelly
 */
module blip.parallel.NRMutex;


public import tango.core.Exception : SyncException;

version( Win32 )
{
    private import tango.sys.win32.UserGdi;
}
else version( Posix )
{
    private import tango.stdc.posix.pthread;
}


////////////////////////////////////////////////////////////////////////////////
// Mutex
//
// void lock();
// void unlock();
// bool tryLock();
////////////////////////////////////////////////////////////////////////////////


/**
 * This class represents a general purpose, recursive mutex.
 */
class NRMutex :
    Object.Monitor
{
    ////////////////////////////////////////////////////////////////////////////
    // Initialization
    ////////////////////////////////////////////////////////////////////////////


    /**
     * Initializes a mutex object.
     *
     * Throws:
     *  SyncException on error.
     */
    this()
    {
        version( Win32 )
        {
            InitializeCriticalSection( &m_hndl );
        }
        else version( Posix )
        {
            int rc = pthread_mutex_init( &m_hndl, &sm_attr );
            if( rc )
                throw new SyncException( "Unable to initialize mutex" );
        }
        m_proxy.link = this;
        (cast(void**) this)[1] = &m_proxy;
    }


    ~this()
    {
        version( Win32 )
        {
            DeleteCriticalSection( &m_hndl );
        }
        else version( Posix )
        {
            int rc = pthread_mutex_destroy( &m_hndl );
            assert( !rc, "Unable to destroy mutex" );
        }
        (cast(void**) this)[1] = null;
    }


    ////////////////////////////////////////////////////////////////////////////
    // General Actions
    ////////////////////////////////////////////////////////////////////////////


    /**
     * If this lock is not already held by the caller, the lock is acquired,
     * then the internal counter is incremented by one.
     *
     * Throws:
     *  SyncException on error.
     */
    void lock()
    {
        version( Win32 )
        {
            EnterCriticalSection( &m_hndl );
        }
        else version( Posix )
        {
            int rc = pthread_mutex_lock( &m_hndl );
            if( rc )
                throw new SyncException( "Unable to lock mutex" );
        }
    }


    /**
     * Decrements the internal lock count by one.  If this brings the count to
     * zero, the lock is released.
     *
     * Throws:
     *  SyncException on error.
     */
    void unlock()
    {
        version( Win32 )
        {
            LeaveCriticalSection( &m_hndl );
        }
        else version( Posix )
        {
            int rc = pthread_mutex_unlock( &m_hndl );
            if( rc )
                throw new SyncException( "Unable to unlock mutex" );
        }
    }


    /**
     * If the lock is held by another caller, the method returns.  Otherwise,
     * the lock is acquired if it is not already held, and then the internal
     * counter is incremented by one.
     *
     * Returns:
     *  true if the lock was acquired and false if not.
     *
     * Throws:
     *  SyncException on error.
     */
    bool tryLock()
    {
        version( Win32 )
        {
            return TryEnterCriticalSection( &m_hndl ) != 0;
        }
        else version( Posix )
        {
            return pthread_mutex_trylock( &m_hndl ) == 0;
        }
    }


    version( Posix )
    {
        static this()
        {
            int rc = pthread_mutexattr_init( &sm_attr );
            assert( !rc );

            rc = pthread_mutexattr_settype( &sm_attr, PTHREAD_MUTEX_NORMAL );
            assert( !rc );
        }


        static ~this()
        {
            int rc = pthread_mutexattr_destroy( &sm_attr );
            assert( !rc );
        }
    }


private:
    version( Win32 )
    {
        CRITICAL_SECTION    m_hndl;
    }
    else version( Posix )
    {
        static pthread_mutexattr_t  sm_attr;

        pthread_mutex_t     m_hndl;
    }

    struct MonitorProxy
    {
        Object.Monitor link;
    }

    MonitorProxy            m_proxy;


package:
    version( Posix )
    {
        pthread_mutex_t* handleAddr()
        {
            return &m_hndl;
        }
    }
}


////////////////////////////////////////////////////////////////////////////////
// Unit Tests
////////////////////////////////////////////////////////////////////////////////


debug( UnitTest )
{
    private import tango.core.Thread;


    unittest
    {
        auto mutex      = new NRMutex;
        int  numThreads = 10;
        int  numTries   = 1000;
        int  lockCount  = 0;

        void testFn()
        {
            for( int i = 0; i < numTries; ++i )
            {
                synchronized( mutex )
                {
                    ++lockCount;
                }
            }
        }

        auto group = new ThreadGroup;

        for( int i = 0; i < numThreads; ++i )
            group.create( &testFn );

        group.joinAll();
        assert( lockCount == numThreads * numTries );
    }
}
