/// infomration about Numa topology, and functions to influence it
///
/// good resources of information about this topic:
/// - processor and api report:
///      http://www.halssoftware.com/reports/technical/procmem/ProcMemReport_download
///   a good overview of the various apis on the various OS (but not osX)
/// - Linux (novell) numa api:
///      http://www.novell.com/collateral/4621437/4621437.pdf
///   good overview of the modern linux NUMA api, available in the new distributions
/// - Portable Linux Processor Affinity (PLPA):
///      http://www.open-mpi.org/projects/plpa/
///   a nice library that I use to get affinity & more working on linux distribtion without libnuma
/// - OSX 10.5 thread affinity
///      http://developer.apple.com/releasenotes/Performance/RN-AffinityAPI/
///   a good starting point for these issues on macosX 10.5
/// - Windows numa resources:
///      http://www.microsoft.com/whdc/archive/numa_isv.mspx
///   an intoductive article about it
///      http://msdn.microsoft.com/en-us/library/aa363804.aspx
///   Windows numa API
/// - Opensolaris topology representation
///      http://opensolaris.org/os/community/performance/mpo_overview.pdf
///   the topology representation that did inspire the current interface
///
///  author: Fawzi Mohamed
module blip.parallel.smp.Numa;
import blip.t.core.Thread;
import blip.serialization.Serialization;
import blip.t.math.random.Random;
import blip.t.stdc.stringz;
import blip.parallel.hwloc.hwloc;
import blip.serialization.StringSerialize;
import blip.BasicModels;
import blip.util.Grow:growLength;
import blip.io.BasicIO;
import blip.io.Console;//pippo
import blip.t.stdc.stdlib:abort;
import blip.container.GrowableArray:collectAppender;
version(Windows){
    
} else {
    import tango.stdc.posix.sys.types:pid_t;
}

/// identifier for the processor (OS dependent)
alias long proc_id_t;
/// identifier for the socket (OS dependent)
alias int cpu_sock_t;

/// struct node/proc mask
struct NodeMask{
    version (Windows)
    {
        //alias HANDLE pid_t;
        alias int pid_t;
    }
    /// set the affinity of the current thread (this is the most likely to be implemented)
    bool setThreadAffinity(){
        return false;
    }
    /// set the affinity of the current thread (this is the most likely to be implemented)
    static NodeMask getThreadAffinity(){
        NodeMask res;
        return res;
    }
    /// set the affinity of the thread t
    bool setThreadAffinity(Thread t){
        return false;
    }
    /// set the affinity of the thread t
    static NodeMask getThreadAffinity(Thread t){
        NodeMask res;
        return res;
    }
    /// set the affinity 
    bool setProcessAffinity(pid_t pid){ return false;}
    /// gets the process affinity
    static NodeMask getProcessAffinity(pid_t pid){
        NodeMask res;
        return res;
    }

    // system dependent representation
    
}

/// identifies a numa node
struct NumaNode{
    int level=-1; // invalid
    int pos;
    
    equals_t opEquals(NumaNode n){
        return level==n.level && pos==n.pos;
    }
    static NumaNode opCall(int level,int pos){
        NumaNode res;
        res.level=level;
        res.pos=pos;
        return res;
    }
    int opCmp(NumaNode n){
        auto v=level-n.level; // we assume less than 2**31 levels and pos
        return
            ((v==0)?(pos-n.pos):v);
    }
    static ClassMetaInfo metaI;
    static this(){
        metaI=ClassMetaInfo.createForType!(typeof(*this))("NumaNode");
        metaI.addFieldOfType!(int)("level","the level of this node");
        metaI.addFieldOfType!(int)("pos","position of this node within the level");
    }
    ClassMetaInfo getSerializationMetaInfo(){
        return metaI;
    }
    void serial(Ser)(Ser s){
        s.field(metaI[0],level);
        s.field(metaI[1],pos);
    }
    void serialize(Serializer s){
        serial(s);
    }
    void unserialize(Unserializer s){
        serial(s);
    }
    char[] toString(){
        return serializeToArray(this);
    }
    mixin printOut!();
}

struct CacheInfo{
    NumaNode attachedTo;
    ulong size_kB;
    ulong sharingLevel;
    ulong depth; // useful?
    mixin(serializeSome("",`attachedTo|size_kB|sharingLevel|depth`));
    mixin printOut!();
}

struct MemoryInfo{
    NumaNode attachedTo;
    ulong memory_kB;          /**< \brief Size of memory node */
    ulong huge_page_free;     /**< \brief Number of available huge pages */
    mixin(serializeSome("",`attachedTo|memory_kB|huge_page_free`));
    mixin printOut!();
}

struct MachineInfo{
    NumaNode attachedTo;
    char[]dmi_board_vendor;       /**< \brief DMI board vendor name */
    char[]dmi_board_name;         /**< \brief DMI board model name */
    ulong memory_kB;          /**< \brief Size of memory node */
    ulong huge_page_free;     /**< \brief Number of available huge pages */
    ulong huge_page_size_kB;      /**< \brief Size of huge pages */
    mixin(serializeSome("",`attachedTo|dmi_board_vendor|dmi_board_name|memory_kB
        huge_page_free|huge_page_size_kB`));
    mixin printOut!();
}

struct SocketInfo{
    NumaNode attachedTo;
    mixin(serializeSome("",`attachedTo`));
    mixin printOut!();
}

/// returns the id of the current CPU
proc_id_t currentCpuId() { throw new Exception("unimplemented",__FILE__,__LINE__); }
/// loops on the available nodes (at one ot the levels 0,1 or 2)
SimpleIteratorI!(NumaNode) nodesAvailable() {
    throw new Exception("unimplemented",__FILE__,__LINE__); // do not implement at all, so that presence can be statically checked?
}

/// describes the topology of a machine in a simplified hierarchical way
/// starting with leaf nodes each super level adds nodes that are further away
/// there are methods to loop on subnodes or on the added nodes
interface Topology(NodeType):BasicObjectI{
    /// maximum (whole system) level
    int maxLevel();
    /// maximum number of nodes at the given level (actual nodes might be less)
    int nNodes(int level);
    /// it the given level is a partition (no overlap between the nodes)
    /// if false it might still be a partition, or not
    bool isPartition(int level);
    /// loops on the nodes at the given level
    SimpleIteratorI!(NodeType) nodes(int level);
    /// super node of the given node
    NodeType superNode(NumaNode node);
    /// loops on the subnodes (level of subnodes is uniform, but might be lower than node.lower-1)
    SimpleIteratorI!(NodeType) subNodes(NodeType node);
    /// loops on the subnodes in a random order (load balancing), if possible skipping the 
    // subnodes of the skip subnode
    SimpleIteratorI!(NodeType) subNodesRandom(NodeType node,NodeType skipSubnode=NodeType.init);
}

struct SubnodesWithLevel(NodeType,bool isRandom) /+:SimpleIteratorI!(NodeType)+/{
    Topology!(NodeType) topo;
    SimpleIteratorI!(NodeType)[] stack;
    size_t lastStack;
    int level;
    NodeType skipSubnode;
    
    static SubnodesWithLevel opCall(int level, Topology!(NodeType) topo,
        NodeType rootNode,NodeType skipSubnode=NodeType(-1,0))
    {
        SubnodesWithLevel res;
        res.topo=topo;
        res.lastStack=0;
        res.stack.length=rootNode.level;
        res.skipSubnode=skipSubnode;
        res.level=level;
        static if (isRandom){
            res.stack[res.lastStack]=topo.subNodesRandom(rootNode,res.skipSubnode);
        } else {
            res.stack[res.lastStack]=topo.subNodes(rootNode);
        }
        return res;
    }
    /// goes to the next element
    bool next(ref NodeType el){
        NodeType nodeAtt;
        bool readVal=false;
        readVal=stack[lastStack].next(nodeAtt);
        while (true){
            if (!readVal){
                if (lastStack!=0){
                    --lastStack;
                } else {
                    return false;
                }
            } else {
                if (nodeAtt!=skipSubnode){
                    if (nodeAtt.level>level) {
                        ++lastStack;
                        static if (isRandom){
                            stack[lastStack]=topo.subNodesRandom(nodeAtt,skipSubnode);
                        } else {
                            stack[lastStack]=topo.subNodes(nodeAtt);
                        }
                    } else if (nodeAtt.level==level){
                        el=nodeAtt;
                        return true;
                    } // else ignore too deep nodes
                }
            }
            readVal=stack[lastStack].next(nodeAtt);
        }
    }
    mixin opApplyFromNext!(NodeType);
}
/// subnodes of the root subnode that have the given level
SubnodesWithLevel!(NodeType,false) subnodesWithLevel(NodeType)(int level,
    Topology!(NodeType) topo,NodeType rootNode,NodeType skipNode=NodeType.init)
{
    return SubnodesWithLevel!(NodeType,false)(level,topo,rootNode,skipNode);
}

/// subnodes of the root subnode that have the given level in a random order
/// (potentially different for each call)
SubnodesWithLevel!(NodeType,true) randomSubnodesWithLevel(NodeType)(int level,
    Topology!(NodeType) topo,NodeType rootNode,NodeType skipNode=NodeType.init)
{
    return SubnodesWithLevel!(NodeType,true)(level,topo,rootNode,skipNode);
}

/// level 0 are the single logical cores (threads)
/// level 1 are the threads with same cache (cores)
/// level 2 are the cores that have uniform latency to the local memory (NUMA nodes)
/// higher level represent group obtained by adding to a group of the previous level all
/// the nodes of level 2 that are at the next possible latency distance
/// for levels higher than 2 the nodes do not necessarily form a partition (i.e. they might overlap)
/// the level of subnodes is min(node.level-1,2)
/// this simplified structure might miss some caches, as only one cache per level is assumed
interface NumaTopology: Topology!(NumaNode){
    /+
    /// mask for the given node
    NodeMask maskForNode(NumaNode node);
    /// mapping from processors to nodes of level 0
    NumaNode procToNode(proc_id_t extLeaf);
    /// mapping from nodes of level 0 to processors
    proc_id_t nodeToProc(NumaNode);
    /// mapping from cpu socket to nodes of level x>=2
    NumaNode socketToNode(cpu_sock_t extLeaf);
    /// mapping from nodes of level x>=2 to cpu sockets
    cpu_sock_t nodeToSocket(NumaNode);
    +/
    // next*, mean with level>= to the current level
    
    /// tries to restrict the current thread to the given node
    /// returns false if the bind failed, singlify just pics a single processor
    /// withing the ones of the node
    bool bindToNode(NumaNode n,bool singlify=false);
    /// returns the next cache, if attachedTo.level=-1 the result is bogus (no cache found)
    CacheInfo nextCache(NumaNode);
    /// returns the next memory, if attachedTo.level=-1 the result is bogus (no memory found)
    MemoryInfo nextMemory(NumaNode);
    /// returns the next machine, if attachedTo.level=-1 the result is bogus (no machine found)
    MachineInfo nextMachine(NumaNode);
    /// returns the next socket, if attachedTo.level=-1 the result is bogus (no socket found)
    SocketInfo nextSocket(NumaNode);
}

void writeOutTopo(NodeType)(void delegate(char[]) sink,Topology!(NodeType) topo){
    auto s=dumper(sink);
    for (int ilevel=topo.maxLevel;ilevel!=0;--ilevel){
        s("level(")(ilevel)("){");
        if (topo.isPartition(ilevel)){
            s("*partition*");
        }
        s("\n");
        foreach(i,n;topo.nodes(ilevel)){
            if (i!=0) s(",\n");
            s("  ")(n)("[");
            foreach(j,subN;topo.subNodes(n)){
                if (j!=0) s(",");
                s(subN);
            }
            s("]");
        }
        s("\n}\n");
    }
    if (topo.maxLevel>=0){
        s("level(0){");
        if (topo.isPartition(0)){
            s("*partition*");
        }
        s("\n  ");
        foreach(i,n;topo.nodes(0)){
            if (i!=0) s(", ");
            s(n);
        }
        s("\n}\n");
    }
}

class ExplicitTopology(NodeType): Topology!(NodeType){
    final class ArrayIterator(T):SimpleIteratorI!(T){
        T[] array;
        size_t pos;
        size_t left;
        this(T[] arr,size_t startIdx=0){
            array=arr;
            pos=startIdx;
            left=array.length;
        }
        bool next(ref T el){
            if (left==0) return false;
            size_t posAtt=pos;
            ++pos;
            --left;
            if (pos==array.length) pos=0;
            el=array[posAtt];
            return true;
        }
        int opApply(int delegate(ref T el) loopBody){
            while (left!=0){
                if (auto res=loopBody(array[pos])){
                    return res;
                }
                ++pos;--left;
                if (pos==array.length) pos=0;
            }
            return 0;
        }
        int opApply(int delegate(ref size_t i,ref T el) loopBody){
            while (left!=0){
                if (auto res=loopBody(pos,array[pos])){
                    return res;
                }
                ++pos;--left;
                if (pos==array.length) pos=0;
            }
            return 0;
        }
    }
    
    struct NumaLevel{
        NodeType[] nodes;
        NodeType[] superNodes;
        NodeType[][] subNodes;
        bool partition;
        size_t nNodes(){
            return nodes.length;
        }
        void nNodes(size_t size){
            nodes.length=size;
            subNodes.length=size;
            superNodes.length=size;
        }
        static ClassMetaInfo metaI;
        static this(){
            metaI=ClassMetaInfo.createForType!(typeof(*this))("ExplicitTopology!("~NodeType.stringof~").NumaLevel");
            metaI.addFieldOfType!(NodeType[])("nodes","the nodes of this level");
            metaI.addFieldOfType!(NodeType[])("superNodes","the super Nodes of this level");
            metaI.addFieldOfType!(NodeType[][])("subNodes","the sub nodes of this level");
        }

        ClassMetaInfo getSerializationMetaInfo(){
            return metaI;
        }
        
        void serial(Ser)(Ser s){
            s.field(metaI[0],nodes);
            s.field(metaI[1],superNodes);
            s.field(metaI[2],subNodes);
        }
        void serialize(Serializer s){
            serial(s);
        }
        void unserialize(Unserializer s){
            serial(s);
        }
    }
    
    NumaLevel[] levels;
    
    /// constructor
    this(){
    }

    /// constructor
    this(NumaLevel[] levels){
        this.levels=levels;
    }
    
    /// maximum (whole system) level
    int maxLevel(){
        return levels.length-1;
    }
    /// maximum number of nodes at the given level (actual nodes might be less)
    int nNodes(int level){
        return levels[level].nodes.length;
    }
    /// it the given level is a partition (no overlap between the nodes)
    /// if false it might still be a partition, or not
    bool isPartition(int level){
        return levels[level].partition;
    }
    /// loops on the nodes at the given level
    SimpleIteratorI!(NodeType) nodes(int level){
        return new ArrayIterator!(NodeType)(levels[level].nodes);
    }
    /// super node of the given node
    NodeType superNode(NodeType node){
        assert(node.level+1<levels.length,"no super node for node at top level"); // return itself?
        return levels[node.level].superNodes[node.pos];
    }
    /// loops on the subnodes (level of subnodes is uniform, but might be 2 rather than node.level-1)
    SimpleIteratorI!(NodeType) subNodes(NodeType node){
        assert(node.level!=0,"no subnode of the last level"); // return an empty iterator?
        return new ArrayIterator!(NodeType)(levels[node.level].subNodes[node.pos]);
    }
    /// loops on the subnodes, but perform at least a random
    /// rotation on them and tries to avoid the subnodes of skip
    /// (thus can be used for load balancing purposes)
    SimpleIteratorI!(NodeType) subNodesRandom(NodeType node,NodeType skipSubnode=NodeType(-1,0)){
        assert(node.level!=0,"no subNodes at level 0"); // return an empty iterator?
        int start=0;
        auto subNs=levels[node.level].subNodes[node.pos];
        int mLevel=skipSubnode.level;
        if (mLevel>=levels.length) mLevel=-1;
        for (int i=1;i<10;++i){
            start=rand.uniformR!(int)(subNs.length);
            auto subN=subNs[start];
            for (int iLevel=subN.level;iLevel<=mLevel;++iLevel){
                subN=levels[iLevel].superNodes[subN.pos];
            }
            if (subN!=skipSubnode) break;
        }
        return new ArrayIterator!(NodeType)(levels[node.level].subNodes[node.pos],start);
    }
    
    static ClassMetaInfo metaI;
    static this(){
        metaI=ClassMetaInfo.createForType!(typeof(this))("ExplicitTopology!("~NodeType.stringof~")");
        metaI.addFieldOfType!(NumaLevel[])("levels","the levels of this topology");
    }
    ClassMetaInfo getSerializationMetaInfo(){
        return metaI;
    }
    void serialize(Serializer s){
        s.field(metaI[0],levels);
    }
    void unserialize(Unserializer s){
        s.field(metaI[0],levels);
    }
    void desc(CharSink sink){
        writeOutTopo(sink,cast(Topology!(NumaNode))this);
    }
}

class ExplicitNumaTopology: ExplicitTopology!(NumaNode), NumaTopology {
    /// constructor
    this(){
        super();
    }

    /// constructor
    this(ExplicitTopology!(NumaNode).NumaLevel[] levels){
        super(levels);
    }

    CacheInfo nextCache(NumaNode){ CacheInfo res; return res; }
    MemoryInfo nextMemory(NumaNode){ MemoryInfo res; return res; }
    MachineInfo nextMachine(NumaNode){ MachineInfo res; return res; }
    SocketInfo nextSocket(NumaNode){ SocketInfo res; return res; }
    bool bindToNode(NumaNode n,bool singlify=false){ return false; }
    
    static ClassMetaInfo metaI;
    static this(){
        metaI=ClassMetaInfo.createForType!(typeof(this))("ExplicitNumaTopology");
    }
    ClassMetaInfo getSerializationMetaInfo(){
        return metaI;
    }
    void serialize(Serializer s){
        super.serialize(s);
    }
    void unserialize(Unserializer s){
        super.unserialize(s);
    }
    
}

ExplicitNumaTopology uniformTopology(int[] nDirectChilds){
    alias ExplicitTopology!(NumaNode).NumaLevel Level;
    int nNodesLevel=1;
    auto nLevels=nDirectChilds.length;
    Level[] levels=new Level[nLevels+1];
    for (int ilevel=0;ilevel<nLevels;++ilevel){
        Level *lAtt=&(levels[nLevels-ilevel]);
        lAtt.nNodes=nNodesLevel;
        for (int inode=0;inode<nNodesLevel;++inode){
            lAtt.nodes[inode].level=nLevels-ilevel;
            lAtt.nodes[inode].pos=inode;
            
            int nChilds=nDirectChilds[ilevel];
            lAtt.subNodes[inode]=new NumaNode[nChilds];
            auto ii=inode*nChilds;
            for (int isub=0; isub<nChilds;++isub){
                lAtt.subNodes[inode][isub].level=nLevels-ilevel-1;
                lAtt.subNodes[inode][isub].pos=ii;
                ++ii;
            }
            
            if (ilevel>0){
                lAtt.superNodes[inode].pos=inode/nDirectChilds[ilevel-1];
                lAtt.superNodes[inode].level=nNodesLevel-ilevel+1;
            }
        }
        nNodesLevel*=nDirectChilds[ilevel];
    }
    for (int inode=0;inode<nNodesLevel;++inode){
        Level *lAtt=&(levels[0]);
        lAtt.nNodes=nNodesLevel;

        lAtt.nodes[inode].level=0;
        lAtt.nodes[inode].pos=inode;
    }
    levels[nLevels].superNodes[0]=levels[nLevels].nodes[0];
    for (int ilevel=1;ilevel<=nLevels;++ilevel){
        Level *lAtt=&(levels[ilevel]);
        for (int inode=0;inode<lAtt.nNodes;++inode){
            for (int isub=0; isub<lAtt.subNodes[inode].length;++isub){
                auto nAtt=&(lAtt.subNodes[inode][isub]);
                *nAtt=levels[nAtt.level].nodes[nAtt.pos];
            }
        }
    }
    return new ExplicitNumaTopology(levels);
}

version(noHwloc){} else {
    class HwlocTopology: NumaTopology{
        hwloc_topology_t topology;
    
        struct LevelMap{
            int depth; /// hwloc depth
            bool partition; /// if it is a partition
            mixin(serializeSome("",`depth|partition`));
            mixin printOut!();
        }
        LevelMap[] levelMapping; /// mapping numa level -> hwloc depth
        int backMapping[]; /// mapping hwloc depth -> numa level
    
        class CousinIterator:SimpleIteratorI!(NumaNode){
            HwlocTopology topo;
            hwloc_obj_t pos;
        
            this(HwlocTopology topo,hwloc_obj_t pos){
                this.topo=topo;
                this.pos=pos;
            }
        
            bool next(ref NumaNode res){
                if (pos!is null){
                    res=NumaNode(backMapping[pos.depth],pos.logical_index);
                    pos=pos.next_cousin;
                    return true;
                }
                return false;
            }
        
            int opApply(int delegate(ref NumaNode x) dlg){
                if (pos is null) return 0;
                int nEl=hwloc_get_nbobjs_by_depth(topo.topology,pos.depth);
                for (int i=pos.logical_index;i<nEl;++i){
                    auto n=NumaNode(backMapping[pos.depth],i);
                    auto res=dlg(n);
                    if (res) return res;
                }
                return 0;
            }
            int opApply(int delegate(ref size_t i,ref NumaNode x) dlg){
                if (pos is null) return 0;
                int nEl=hwloc_get_nbobjs_by_depth(topo.topology,pos.depth);
                size_t ii=0;
                for (int i=pos.logical_index;i<nEl;++i){
                    auto n=NumaNode(backMapping[pos.depth],i);
                    auto res=dlg(ii,n);
                    if (res) return res;
                    ++ii;
                }
                return 0;
            }
        
            int opApply(int delegate(ref NumaNode x,ref hwloc_obj_t obj) dlg){
                if (pos is null) return 0;
                int nEl=hwloc_get_nbobjs_by_depth(topo.topology,pos.depth);
                for (int i=pos.logical_index;i<nEl;++i){
                    assert(pos!is null);
                    auto n=NumaNode(backMapping[pos.depth],i);
                    auto res=dlg(n,pos);
                    if (res) return res;
                    pos=pos.next_cousin;
                }
                return 0;
            }
        }

        class RandomChildernIterator:SimpleIteratorI!(NumaNode){
            HwlocTopology topo;
            hwloc_obj_t[][] childrens;
            int[] pos;
            int[] left;
            int lastStack;
            int level; /// the minimum level of the childrens
            int depth2,maxDepth;
        
            this(HwlocTopology topo,hwloc_obj_t[] childrens,int start,int level){
                this.topo=topo;
                this.level=level;
                
                if (childrens.length>0 && level>=0){
                    depth2=levelMapping[level].depth;
                    maxDepth=hwloc_topology_get_depth(topology);
                    this.childrens.length=maxDepth-levelMapping[level+1].depth+1;
                    this.childrens[0]=childrens;
                    lastStack=0;
                    pos.length =this.childrens.length;
                    left.length=this.childrens.length;
                    pos[0]=start%(childrens.length);
                    left[0]=childrens.length;
                } else {
                    this.childrens=[[]];
                    lastStack=0;
                    pos=[0];
                    left=[0];
                }
            }
        
            bool next(ref NumaNode res,ref hwloc_obj_t obj){
                while(true){
                    while (left[lastStack]<=0){
                        if (lastStack==0) return false;
                        --lastStack;
                    }
                    auto cAtt=childrens[lastStack][pos[lastStack]];
                    ++(pos[lastStack]);
                    if (pos[lastStack]==childrens[lastStack].length) {
                        pos[lastStack]=0;
                    }
                    --(left[lastStack]);
                    if(cAtt.depth<depth2){
                        ++lastStack;
                        pos[lastStack]=0;
                        left[lastStack]=cAtt.arity;
                        childrens[lastStack]=cAtt.children[0..cAtt.arity];
                    } else if (cAtt.depth==depth2){
                        res=NumaNode(level,cAtt.logical_index);
                        obj=cAtt;
                        return true;
                    } else {
                        for (int ilevel=level;ilevel>=0;--ilevel){
                            if (cAtt.depth==levelMapping[ilevel].depth){
                                res=NumaNode(ilevel,cAtt.logical_index);
                                obj=cAtt;
                                return true;
                            }
                        }
                        if (cAtt.depth<maxDepth){
                            ++lastStack;
                            pos[lastStack]=0;
                            left[lastStack]=cAtt.arity;
                            childrens[lastStack]=cAtt.children[0..cAtt.arity];
                        }
                    }
                }
            }
            
            bool next(ref NumaNode res){
                hwloc_obj_t o;
                return next(res,o);
            }
        
            int opApply(int delegate(ref NumaNode x) dlg){
                NumaNode n;
                while (next(n)){
                    auto res=dlg(n);
                    if (res!=0) return res;
                }
                return 0;
            }

            int opApply(int delegate(ref size_t,ref NumaNode) dlg){
                size_t ii=0;
                NumaNode n;
                while (next(n)){
                    auto res=dlg(ii,n);
                    if (res!=0) return res;
                    ++ii;
                }
                return 0;
            }
        
            int opApply(int delegate(ref NumaNode x,ref hwloc_obj_t obj) dlg){
                NumaNode n;
                hwloc_obj_t obj;
                while (next(n,obj)){
                    auto res=dlg(n,obj);
                    if (res!=0) return res;
                }
                return 0;
            }
        }
    
        /// constructor
        this(){
            hwloc_topology_init(&topology);
            /* Perform the topology detection.  */
            hwloc_topology_load(topology);
            initLevels();
        }

        /// constructor
        this(hwloc_topology_t topology){
            this.topology=topology;
            initLevels();
        }
    
        ~this(){
            hwloc_topology_destroy(topology);
        }
    
        void initLevels(){
            auto depth=hwloc_topology_get_depth(topology);
            backMapping=new int[depth];
            int nLevels;
            auto obj=hwloc_get_obj_by_depth(topology,depth-1,0);
        
            while(obj!is null){
                switch (obj.type){
                    case HWLOC_OBJ.SYSTEM,HWLOC_OBJ.MACHINE,HWLOC_OBJ.NODE,
                         HWLOC_OBJ.CORE,HWLOC_OBJ.PROC :
                    ++nLevels;
                    break;
                    default:
                        if (obj.arity>1)
                            ++nLevels;
                    break;
                }
                obj=obj.father;
            }
            levelMapping=new LevelMap[nLevels];
        
            nLevels=0;
            obj=hwloc_get_obj_by_depth(topology,depth-1,0);
            int lastDepth=depth;
            while(obj!is null){
                switch (obj.type){
                    case HWLOC_OBJ.SYSTEM,HWLOC_OBJ.MACHINE,HWLOC_OBJ.NODE,
                         HWLOC_OBJ.CORE,HWLOC_OBJ.PROC :
                        ++nLevels;
                        levelMapping[nLevels-1].depth=obj.depth;
                        levelMapping[nLevels-1].partition=true;
                        break;
                    default:
                        if (obj.arity>1){
                            ++nLevels;
                            levelMapping[nLevels-1].depth=obj.depth;
                            levelMapping[nLevels-1].partition=true;
                        }
                    break;
                }
                for (int d=obj.depth;d<lastDepth;d++)
                    backMapping[d]=nLevels-1;
                lastDepth=obj.depth;
                obj=obj.father;
            }
//            desc(sout.call); // pippo
//            sout("\n");
        }
    
        /// maximum (whole system) level
        int maxLevel(){
            return levelMapping.length-1;
        }
    
        /// maximum number of nodes at the given level (actual nodes might be less)
        int nNodes(int level){
            // this might fail if there are different types at the same level
            return hwloc_get_nbobjs_by_depth(topology, levelMapping[level].depth);
        }
        /// it the given level is a partition (no overlap between the nodes)
        /// if false it might still be a partition, or not
        bool isPartition(int level){
            return levelMapping[level].partition;
        }
        /// internal method that returns the underlying hwloc_obj
        hwloc_obj_t hwlocObjForNumaNode(NumaNode n){
            if (n.level==-1) abort();
            if (n.level==-1) throw new Exception("invalid node",__FILE__,__LINE__);
            return hwloc_get_obj_by_depth(topology,levelMapping[n.level].depth,n.pos);
        }
        /// loops on the nodes at the given level
        SimpleIteratorI!(NumaNode) nodes(int level){
            return new CousinIterator(this,
                hwloc_get_obj_by_depth(topology,levelMapping[level].depth,0));
        }
        /// super node of the given node
        NumaNode superNode(NumaNode node){
            if (!(node.level+1<levelMapping.length)) abort;//pippo
            assert(node.level+1<levelMapping.length,"no super node for node at top level"); // return itself?
            auto obj=hwlocObjForNumaNode(node);
            if (obj is null){
                throw new Exception(collectAppender(delegate void(CharSink s){
                    s("no object for node "); writeOut(s,node);  s("\n");
                }),__FILE__,__LINE__);
            }
            auto prevDepth=levelMapping[node.level+1].depth;
            while (obj.depth>prevDepth){
                obj=obj.father;
                assert(obj!is null);
            }
            if (obj.depth==prevDepth){
                return NumaNode(node.level+1,obj.logical_index);
            } else {
                auto maxL=maxLevel;
                while(true){
                    for (int ilevel=node.level+1;ilevel<=maxL;++ilevel){
                        if (obj.depth==levelMapping[ilevel].depth){
                            return NumaNode(ilevel,obj.logical_index);
                        } else if (obj.depth>levelMapping[ilevel].depth) {
                            break;
                        }
                    }
                    if (obj.depth==0) break;
                    obj=obj.father;
                }
            }
            throw new Exception(collectAppender(delegate void(CharSink s){
                s("no superNode for node "); writeOut(s,node);  s("\n");
            }),__FILE__,__LINE__);
        }
        /// loops on the subnodes (level of subnodes is uniform, but might be 2 rather than node.level-1)
        SimpleIteratorI!(NumaNode) subNodes(NumaNode node){
            assert(node.level!=0,"no subnode of the last level"); // return an empty iterator?
            auto obj=hwlocObjForNumaNode(node);
            if (obj is null){
                throw new Exception(collectAppender(delegate void(CharSink s){
                    s("no hwlocObjForNumaNode for node "); writeOut(s,node);  s("\n");
                }),__FILE__,__LINE__);
            }
            auto nextDepth=levelMapping[node.level-1].depth;
            while (obj !is null && obj.depth<nextDepth-1 && obj.arity==1){
                obj=obj.first_child;
            }
            if (obj is null){
                throw new Exception(collectAppender(delegate void(CharSink s){
                    s("no subnodes for node "); writeOut(s,node);  s("\n");
                }),__FILE__,__LINE__); // return an empty iterator?
            }
            auto childrens=obj.children[0..obj.arity];
            return new RandomChildernIterator(this,childrens,0,node.level-1);
        }
        /// loops on the subnodes, but perform at least a random
        /// rotation on them and tries to avoid the subnodes of skip
        /// (thus can be used for load balancing purposes)
        /// could be better (really skip all subnodes of skip)
        SimpleIteratorI!(NumaNode) subNodesRandom(NumaNode node,NumaNode skipSubnode=NumaNode(-1,0)){
            assert(node.level!=0,"no subNodes at level 0"); // return an empty iterator?
            auto obj=hwlocObjForNumaNode(node);
            auto nextDepth=levelMapping[node.level-1].depth;
            while (obj.depth<nextDepth-1 && obj.arity==1){
                obj=obj.first_child;
            }
            auto childrens=obj.children[0..obj.arity];
            int start=0;
            int mLevel=skipSubnode.level;
            if (mLevel>=levelMapping.length) mLevel=-1;
            for (int i=1;i<10;++i){
                start=rand.uniformR!(int)(childrens.length);
                if (mLevel==-1) break;
                auto depthAtt=levelMapping[mLevel].depth;
                auto subN=childrens[start];
                while(subN.depth>depthAtt){
                    subN=subN.father;
                }
                if (subN.depth!=depthAtt || subN.logical_index!=skipSubnode.pos) break;
            }
            return new RandomChildernIterator(this,childrens,start,node.level-1);
        }
    
    /+    static ClassMetaInfo metaI;
        static this(){
            metaI=ClassMetaInfo.createForType!(typeof(this))("ExplicitTopology!("~NumaNode.stringof~")");
            metaI.addFieldOfType!(NumaLevel[])("levels","the levels of this topology");
        }
        ClassMetaInfo getSerializationMetaInfo(){
            return metaI;
        }
        void serialize(Serializer s){
            s.field(metaI[0],levels);
        }
        void unserialize(Unserializer s){
            s.field(metaI[0],levels);
        }+/
    
        CacheInfo nextCache(NumaNode n){
            int countLeafs(hwloc_obj_t obj){
                if (obj is null) return 0;
                if (obj.first_child is null) return 1;
                int res=0;
                foreach (c;obj.children[0..obj.arity]){
                    res+=countLeafs(c);
                }
                return res;
            }
        
            CacheInfo res;
            auto obj=hwlocObjForNumaNode(n);
            while(obj!=null){
                if (obj.type==HWLOC_OBJ.CACHE) break;
                obj=obj.father;
            }
            if (obj!is null){
                auto level=backMapping[obj.depth];
                auto objDepth=levelMapping[level].depth;
                auto refObj=obj;
                while(refObj.depth>objDepth){
                    refObj=refObj.father;
                }
                assert(refObj.depth==objDepth);
                res.attachedTo=NumaNode(level,refObj.logical_index);
                res.size_kB=obj.attr.cache.memory_kB;
                res.sharingLevel=countLeafs(refObj);
                res.depth=obj.attr.cache.depth; // useful?
            }
            return res;
        }
    
        MemoryInfo nextMemory(NumaNode n){
            MemoryInfo res;
            auto obj=hwlocObjForNumaNode(n);
            while(obj!=null){
                if (obj.type==HWLOC_OBJ.NODE || obj.type==HWLOC_OBJ.MACHINE ||
                    obj.type==HWLOC_OBJ.SYSTEM) break;
                obj=obj.father;
            }
            if (obj!is null){
                auto level=backMapping[obj.depth];
                auto objDepth=levelMapping[level].depth;
                auto refObj=obj;
                while(refObj.depth>objDepth){
                    refObj=refObj.father;
                }
                assert(refObj.depth==objDepth);
                res.attachedTo=NumaNode(level,refObj.logical_index);
                switch(obj.type){
                case HWLOC_OBJ.NODE:
                    res.memory_kB=obj.attr.node.memory_kB;
                    res.huge_page_free=obj.attr.node.huge_page_free;
                    break;
                case HWLOC_OBJ.MACHINE:
                    res.memory_kB=obj.attr.machine.memory_kB;
                    res.huge_page_free=obj.attr.machine.huge_page_free;
                    break;
                case HWLOC_OBJ.SYSTEM:
                    res.memory_kB=obj.attr.system.memory_kB;
                    res.huge_page_free=obj.attr.system.huge_page_free;
                    break;
                default:
                    throw new Exception("unexpected type",__FILE__,__LINE__);
                }
            }
            return res;
        }
        MachineInfo nextMachine(NumaNode n){
            MachineInfo res;
            auto obj=hwlocObjForNumaNode(n);
            while(obj!=null){
                if (obj.type==HWLOC_OBJ.MACHINE || obj.type==HWLOC_OBJ.SYSTEM) break;
                obj=obj.father;
            }
            if (obj!is null){
                auto level=backMapping[obj.depth];
                auto objDepth=levelMapping[level].depth;
                auto refObj=obj;
                while(refObj.depth>objDepth){
                    refObj=refObj.father;
                }
                assert(refObj.depth==objDepth);
                res.attachedTo=NumaNode(level,refObj.logical_index);
                switch(obj.type){
                case HWLOC_OBJ.MACHINE:
                    res.dmi_board_vendor =fromStringz(obj.attr.machine.dmi_board_vendor);
                    res.dmi_board_name   =fromStringz(obj.attr.machine.dmi_board_name);
                    res.memory_kB        =obj.attr.machine.memory_kB        ;
                    res.huge_page_free   =obj.attr.machine.huge_page_free   ;
                    res.huge_page_size_kB=obj.attr.machine.huge_page_size_kB;
                    break;
                case HWLOC_OBJ.SYSTEM:
                    res.dmi_board_vendor =fromStringz(obj.attr.system.dmi_board_vendor);
                    res.dmi_board_name   =fromStringz(obj.attr.system.dmi_board_name);
                    res.memory_kB        =obj.attr.system.memory_kB        ;
                    res.huge_page_free   =obj.attr.system.huge_page_free   ;
                    res.huge_page_size_kB=obj.attr.system.huge_page_size_kB;
                    break;
                default:
                    throw new Exception("unexpected type",__FILE__,__LINE__);
                }
            }
            return res;
        }
        SocketInfo nextSocket(NumaNode n){
            SocketInfo res;
            auto obj=hwlocObjForNumaNode(n);
            while(obj!=null){
                if (obj.type==HWLOC_OBJ.SOCKET) break;
                obj=obj.father;
            }
            if (obj!is null){
                auto level=backMapping[obj.depth];
                auto objDepth=levelMapping[level].depth;
                auto refObj=obj;
                while(refObj.depth>objDepth){
                    refObj=refObj.father;
                }
                assert(refObj.depth==objDepth);
                res.attachedTo=NumaNode(level,refObj.logical_index);
            }
            return res;
        }
        /// tries to restrict the current thread to the given node
        /// returns false if the bind failed
        bool bindToNode(NumaNode n,bool singlify=false){
            auto obj=hwlocObjForNumaNode(n);
            hwloc_cpuset_t cpuset;
            if (singlify){
                cpuset=obj.cpuset.singlify();
            } else {
                cpuset=obj.cpuset;
            }

            /* And try to bind ourself there.  */
            if (hwloc_set_cpubind(topology, cpuset, 0)) {
                return false;
            }
            return true;
        }
        void desc(CharSink sink){
            auto s=dumper(sink);
            s("<HwlocTopology@")(cast(void*)this)("\n");
            s("  levelMapping:")(levelMapping)("\n");
            s("  backMapping:")(backMapping)("\n");
            writeOutTopo(sink,cast(Topology!(NumaNode))this);
            s(">");
        }
    }
}

NumaTopology defaultTopology;

static this(){
    version(noHwloc){
        defaultTopology=uniformTopology([mainCpu.coresPerCPU(),
            mainCpu.threadsPerCPU()/mainCpu.coresPerCPU()]);
    } else {
        defaultTopology=new HwlocTopology();
    }
}

