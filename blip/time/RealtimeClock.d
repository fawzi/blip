/// clocks that can be used to time code
/// author: fawzi
//
// Copyright 2008-2010 the blip developer group
// 
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
// 
//     http://www.apache.org/licenses/LICENSE-2.0
// 
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
module blip.time.RealtimeClock;
import tango.core.Exception;

version (Win32){
    private extern (Windows) 
    {
        int QueryPerformanceCounter   (ulong *count);
        int QueryPerformanceFrequency (ulong *frequency);
    }
    /// systemwide realtime clock
    ulong realtimeClock(){
        ulong res;
        if (! QueryPerformanceCounter (&res))
            throw new PlatformException ("high-resolution timer is not available");
        return res;
    }
    /// period in seconds of the systemwide realtime clock
    real realtimeClockPeriod(){
        ulong res;
        if (! QueryPerformanceFrequency (&res))
            throw new PlatformException ("high-resolution timer is not available");
        return 1.0/res;
    }
    /// realtime clock, need to be valid only on one cpu
    /// if the thread migrates from a cpu to another ther result might be bogus
    ulong cpuClock(){
        ulong res;
        if (! QueryPerformanceCounter (&res))
            throw new PlatformException ("high-resolution timer is not available");
        return res;
    }
    /// period in seconds of the cpu realtime clock
    real cpuClockPeriod(){
        ulong res;
        if (! QueryPerformanceFrequency (&res))
            throw new PlatformException ("high-resolution timer is not available");
        return 1.0/res;
    }
    
} else version(darwin){
    extern(C){
        alias int kern_return_t;
        struct mach_timebase_infoT {
            uint numer;
            uint denom;
        }
        kern_return_t mach_timebase_info(mach_timebase_infoT* info);
        ulong mach_absolute_time();
    }
    /// systemwide realtime clock
    ulong realtimeClock(){
        return mach_absolute_time();
    }
    /// period in seconds of the systemwide realtime clock
    real realtimeClockPeriod(){
        mach_timebase_infoT ti;
        mach_timebase_info(&ti);
        return cast(real)ti.numer/cast(real)ti.denom;
    }
    /// realtime clock, need to be valid only on one cpu
    /// if the thread migrates from a cpu to another ther result might be bogus
    ulong cpuClock(){
        return mach_absolute_time();
    }
    /// period in seconds of the cpu realtime clock
    real cpuClockPeriod(){
        mach_timebase_infoT ti;
        mach_timebase_info(&ti);
        return cast(real)ti.numer/cast(real)ti.denom;
    }

} else version (Posix) {
    private import tango.stdc.posix.time;
    private import tango.stdc.posix.sys.time;
    
    // realtime (global) clock
    static if (is(typeof(timespec)) && is(typeof(clock_gettime(CLOCK_REALTIME,cast(timespec*)null)))){
        /// systemwide realtime clock
        ulong realtimeClock(){
            timespec ts;
            clock_gettime(CLOCK_REALTIME,&ts);
            return cast(ulong)ts.tv_nsec+1_000_000_000UL*cast(ulong)ts.tv_sec;
        }
        /// frequency (in seconds) of the systemwide realtime clock
        real realtimeClockFreq(){
            return 1_000_000_000UL;
        }
    } else {
        /// systemwide realtime clock
        ulong realtimeClock(){
            timeval tv;
            if (gettimeofday (&tv, null))
                throw new PlatformException ("Timer :: linux timer is not available");

            return (cast(ulong) tv.tv_sec * 1_000_000) + tv.tv_usec;
        }
        
        /// frequency (in seconds) of the systemwide realtime clock
        ulong realtimeClockFreq(){
            return 1_000_000UL;
        }
    }
    
    // cpu clock
    
    static if (is(typeof(timespec)) &&
        is(typeof(clock_gettime(CLOCK_THREAD_CPUTIME_ID,cast(timespec*)null)))){
        /// realtime clock, need to be valid only on one cpu
        /// if the thread migrates from a cpu to another ther result might be bogus
        ulong cpuClock(){
            timespec ts;
            clock_gettime(CLOCK_REALTIME,&ts);
            return cast(ulong)ts.tv_nsec+1_000_000_000UL*cast(ulong)ts.tv_sec;
        }
        /// period in seconds of the systemwide realtime clock
        real cpuClockPeriod(){
            return 1.0/1_000_000_000UL;
        }
    } else static if (is(typeof(timespec)) && 
        is(typeof(clock_gettime(CLOCK_REALTIME,cast(timespec*)null))))
    {
        /// realtime clock, need to be valid only on one cpu
        /// if the thread migrates from a cpu to another ther result might be bogus
        ulong cpuClock(){
            timespec ts;
            clock_gettime(CLOCK_REALTIME,&ts);
            return cast(ulong)ts.tv_nsec+1_000_000_000UL*cast(ulong)ts.tv_sec;
        }
        /// period in seconds of the systemwide realtime clock
        real cpuClockPeriod(){
            return 1.0/1_000_000_000UL;
        }
    } else {
        /// realtime clock, need to be valid only on one cpu
        /// if the thread migrates from a cpu to another ther result might be bogus
        ulong cpuClock(){
            timeval tv;
            if (gettimeofday (&tv, null))
                throw new PlatformException ("Timer :: linux timer is not available");

            return (cast(ulong) tv.tv_sec * 1_000_000) + tv.tv_usec;
        }
        
        /// period in seconds of the systemwide realtime clock
        real cpuClockPeriod(){
            return 1.0/1_000_000UL;
        }
    }
}

