/// a simple file stream, at the moment it builds on tango file interface
/// should probably be reimplemented directly on the OS (using aio or just libev?)
///
/// The functions typically used are outfileStr, outfileStrSync, outfileBin, outfileBinSync
///
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
module blip.io.FileStream;
import blip.Comp;
import blip.io.BasicIO;
import blip.io.StreamConverters;
import tango.io.device.File;
import tango.io.stream.DataFile;
import tango.io.device.Conduit;
import blip.container.GrowableArray;
import blip.math.random.Random;

enum WriteMode{
    WriteClear, /// write on a clean file (reset if present)
    WriteAppend,/// append to a file (create if needed)
    WriteUnique, /// write on a new (not yet existing) file (fails if it exists)
    WriteUniqued,/// write on a new (not yet existing) file (changes name until is is unique)
}

enum StreamOptions{
    BinBase=0,
    CharBase=1,
    WcharBase=2,
    DcharBase=3,
    BaseMask=3,
    Sync=1<<3,
}
private enum File.Style WriteUnique = {File.Access.Write, File.Open.New, File.Share.Read};

/// general StreamStrWriter for the given file (normally you want strFile and binFile)
StreamStrWriter!(T) outfileStrWriterT(T)(string path,WriteMode wMode){
    File.Style wStyle;
    switch (wMode){
    case WriteMode.WriteUniqued:
        {
            wStyle=WriteUnique;
            size_t lastPoint=path.length,lastSlash=path.length;
            foreach(i,c;path){
                if (c=='.') lastPoint=i;
                if (c=='/') lastSlash=i;
            }
            string path0=path;
            string ext="";
            if (lastSlash+1<lastPoint){
                path0=path[0..lastPoint];
                ext=path[lastPoint..$];
            }
            string newPath=path;
            for (size_t i=0;i<20;++i){
                try{
                    auto f=new DataFileOutput(cast(char[])newPath,wStyle);
                    return new StreamStrWriter!(T)(f);
                } catch (Exception e) { // should catch only creation failures...
                    newPath=collectIAppender(delegate void(scope CharSink s){
                        uint uniqueId;
                        rand(uniqueId);
                        dumper(s)(path0)("-")(uniqueId)(ext);
                    });
                }
            }
            throw new Exception("could not create a unique path '"~path,__FILE__,__LINE__);
        }
    case WriteMode.WriteUnique:
        wStyle=WriteUnique;
        break;
    case WriteMode.WriteAppend:
        wStyle=File.WriteAppending;
        break;
    case WriteMode.WriteClear:
        wStyle=File.WriteCreate;
        break;
    default:
        assert(0);
    }
    auto f=new DataFileOutput(cast(char[])path,wStyle);
    return new StreamStrWriter!(T)(f);
}
/// ditto
alias outfileStrWriterT!(char) outfileStrWriter;

/// a string (text) based file (add newline replacing support??)
BasicStreams.BasicStrStream!(T) outfileStrT(T)(string path,WriteMode wMode){
    auto sw=outfileStrWriterT!(T)(path,wMode);
    auto res=new BasicStreams.BasicStrStream!(T)(&sw.desc,&sw.writeStr,&sw.flush,&sw.close);
    return res;
}
/// ditto
alias outfileStrT!(char) outfileStr;

/// a string (text) based file that syncronized access (add newline replacing support??)
BasicStreams.BasicStrStream!(T) outfileStrSyncT(T)(string path,WriteMode wMode){
    auto sw=outfileStrWriterT!(T)(path,wMode);
    auto res=new BasicStreams.BasicStrStream!(T)(&sw.desc,&sw.writeStrSync,&sw.flush,&sw.close);
    return res;
}
/// ditto
alias outfileStrSyncT!(char) outfileStrSync;

/// basic methods to handle a binary file
StreamWriter outfileBinWriter(string path,WriteMode wMode){
    File.Style wStyle;
    switch (wMode){
        case WriteMode.WriteUniqued:
            {
                wStyle=WriteUnique;
                size_t lastPoint=path.length,lastSlash=path.length;
                foreach(i,c;path){
                    if (c=='.') lastPoint=i;
                    if (c=='/') lastSlash=i;
                }
                string path0=path;
                string ext="";
                if (lastSlash+1<lastPoint){
                    path0=path[0..lastPoint];
                    ext=path[lastPoint..$];
                }
                string newPath=path;
                for (size_t i=0;i<20;++i){
                    try{
                        auto f=new DataFileOutput(cast(char[])newPath,wStyle);
                        return new StreamWriter(f);
                    } catch (Exception e) { // should catch only creation failures...
                        newPath=collectIAppender(delegate void(scope CharSink s){
                            uint uniqueId;
                            rand(uniqueId);
                            dumper(s)(path0)("-")(uniqueId)(ext);
                        });
                    }
                }
                throw new Exception("could not create a unique path '"~path,__FILE__,__LINE__);
            }
    case WriteMode.WriteUnique:
        wStyle=WriteUnique;
        break;
    case WriteMode.WriteAppend:
        wStyle=File.WriteAppending;
        break;
    case WriteMode.WriteClear:
        wStyle=File.WriteCreate;
        break;
    default:
        assert(0);
    }
    auto f=new DataFileOutput(cast(char[])path,wStyle);
    return new StreamWriter(f);
}

/// binary stream that writes to a file
BasicStreams.BasicBinStream outfileBin(string path,WriteMode wMode){
    auto sw=outfileBinWriter(path,wMode);
    auto res=new BasicStreams.BasicBinStream(&sw.desc,&sw.writeExact,&sw.flush,&sw.close);
    return res;
}
/// binary stream that writes to a file synchronizing writes
BasicStreams.BasicBinStream outfileBinSync(string path,WriteMode wMode){
    auto sw=outfileBinWriter(path,wMode);
    auto res=new BasicStreams.BasicBinStream(&sw.desc,&sw.writeExactSync,&sw.flush,&sw.close);
    return res;
}
/// returns an output stream with the requested options
OutStreamI outfile(string path,WriteMode wMode,StreamOptions sOpt){
    switch(sOpt){
    case StreamOptions.BinBase:
        return outfileBin(path,wMode);
    case StreamOptions.CharBase:
        return outfileStr(path,wMode);
    case StreamOptions.WcharBase:
        return outfileStrT!(wchar)(path,wMode);
    case StreamOptions.DcharBase:
        return outfileStrT!(dchar)(path,wMode);
    case (StreamOptions.Sync|StreamOptions.BinBase):
        return outfileBinSync(path,wMode);
    case (StreamOptions.Sync|StreamOptions.CharBase):
        return outfileStrSync(path,wMode);
    case (StreamOptions.Sync|StreamOptions.WcharBase):
        return outfileStrSyncT!(wchar)(path,wMode);
    case (StreamOptions.Sync|StreamOptions.DcharBase):
        return outfileStrSyncT!(dchar)(path,wMode);
    default:
        assert(0,"unexpected writeMode");
    }
}
/// input file using string
Reader!(T) infileStrT(T)(string path){
    return toReaderT!(char)(new DataFileInput(cast(char[])path));
}
alias infileStrT!(char) infileStr;
Reader!(void) infileBin(string path){
    return toReaderT!(void)(new DataFileInput(cast(char[])path));
}
MultiInput infile(string path){
    return new MultiInput(new DataFileInput(cast(char[])path));
}
