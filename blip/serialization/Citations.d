module blip.serialization.Citations;
import tango.io.stream.Format;
import tango.util.container.HashSet;
import tango.text.Util;

/// a citation of an article
class Citation{
    char[] key;
    char[] citation;
    char[][] refs;
    this(char[]key,char[]citation,char[][]refs=[]){
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
    FormatOutput!(char)desc(FormatOutput!(char)s){
        s("[")(key)("] ")(citation);
        if (refs.length>0){
            s(" refs:");
            foreach(i,r;refs){
                if (i!=0) s(", ");
                s(r);
            }
        }
        s.newline;
        return s;
    }
}

/// database of citations
class CitationDB{
    Citation[char[]] citations;
    HashSet!(Citation) toPrint;
    /// adds a citation to the DB
    this(){
        toPrint=new HashSet!(Citation)();
    }
    /// returns the citation for the given key
    Citation opIndex(char[]key){
        return citations[key];
    }
    /// default instance
    static CitationDB defaultDb;
    static this(){
        defaultDb=new CitationDB();
    }
    /// add citation of an article
    void addCitation(char[] key,char[] citation){
        synchronized(this){
            assert(!(key in citations),"citation already exists");
            citations[key]=new Citation(key,citation);
        }
    }
    /// adds a reference to a citation
    void addRef(char[] key,char[] reference){
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
    void cite(char[]key,char[] reference=""){
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
    FormatOutput!(char)printCited(FormatOutput!(char)s){
        auto cits=toPrint.toArray();
        cits.sort;
        foreach(c;cits){
            c.desc(s);
        }
        return s;
    }
}