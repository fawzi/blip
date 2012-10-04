/// basic support for citations, inspired from Joost's cp2k citation support
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
module blip.serialization.Citations;
import blip.io.BasicIO;
import tango.util.container.HashSet;
import tango.text.Util;
import blip.Comp;

/// a citation of an article
class Citation{
    string key;
    string citation;
    string [] refs;
    this(string key,string citation,string []refs=[]){
        this.key=key;
        this.citation=citation;
    }
    /// comparison
    override int opCmp(Object o){
        auto c2=cast(Citation)o;
        if (c2){
            return ((c2.key>key)?1:(c2.key==key ? 0: -1));
        } else {
            throw new Exception("comparing Citation to an incompatible class: "~o.classinfo.name);
        }
    }
    void desc(scope void delegate(in cstring) sink){
        auto s=dumper(sink);
        s("[")(key)("] ")(citation);
        if (refs.length>0){
            s(" refs:");
            foreach(i,r;refs){
                if (i!=0) s(", ");
                s(r);
            }
        }
        s("\n");
    }
}

/// database of citations
class CitationDB{
    Citation[string ] citations;
    HashSet!(Citation) toPrint;
    /// adds a citation to the DB
    this(){
        toPrint=new HashSet!(Citation)();
    }
    /// returns the citation for the given key
    Citation opIndex(string key){
        return citations[key];
    }
    /// default instance
    static __gshared CitationDB defaultDb;
    shared static this(){
        defaultDb=new CitationDB();
    }
    /// add citation of an article
    void addCitation(string key,string citation){
        synchronized(this){
            assert(!(key in citations),"citation already exists");
            citations[key]=new Citation(key,citation);
        }
    }
    /// adds a reference to a citation
    void addRef(string key,string reference){
        synchronized(this){
            Citation *a=key in citations;
            assert(a!is null,"reference to non existing key '"~key~"'");
            if (a!is null){
                foreach (r;a.refs){
                    if (reference==r){
                        return;
                    }
                }
                a.refs~=reference;
            }
        }
    }
    /// adds the given key for printing
    void cite(string key,string reference=""){
        auto c=citations[key];
        toPrint.add(c);
        if (reference.length>0){
            foreach (r;c.refs){
                if (reference==r){
                    return;
                }
            }
            c.refs~=reference;
        }
    }
    /// prints the references that have been cited
    void printCited(scope void delegate(in cstring) sink){
        auto cits=toPrint.toArray();
        cits.sort;
        foreach(c;cits){
            writeOut(sink,c);
        }
    }
}
