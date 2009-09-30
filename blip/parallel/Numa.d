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
///   a good atarting point for these issues on macosX 10.5
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
module blip.parallel.Numa;
import tango.core.Thread;
import blip.serialization.Serialization;
import tango.math.random.Random;
import tango.stdc.stringz;
import blip.parallel.hwloc;
import blip.serialization.StringSerialize;

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
        return serializeToString(this);
    }
}

struct Cache{
    NumaNode attachedTo;
    ulong size_kB;
    ulong sharingLevel;
    ulong depth; // useful?
    mixin(serializeSome("",`attachedTo|size_kB|sharingLevel|depth`));
}

struct Memory{
    NumaNode attachedTo;
    ulong memory_kB;          /**< \brief Size of memory node */
    ulong huge_page_free;     /**< \brief Number of available huge pages */
    mixin(serializeSome("",`attachedTo|memory_kB|huge_page_free`));
}

struct Machine{
    NumaNode attachedTo;
    char[]dmi_board_vendor;       /**< \brief DMI board vendor name */
    char[]dmi_board_name;         /**< \brief DMI board model name */
    ulong memory_kB;          /**< \brief Size of memory node */
    ulong huge_page_free;     /**< \brief Number of available huge pages */
    ulong huge_page_size_kB;      /**< \brief Size of huge pages */
    mixin(serializeSome("",`attachedTo|dmi_board_vendor|dmi_board_name|memory_kB
        huge_page_free|huge_page_size_kB`));
}

struct Socket{
    NumaNode attachedTo;
    mixin(serializeSome("",`attachedTo`));
}

/// simple iterator
interface SimpleIterator(T){
    /// goes to the next element
    T next();
    /// true if the iterator is at the end
    bool atEnd();
    /// loop without index, has to be implemented
    int opApply(int delegate(ref T x) dlg);
}

/// returns the id of the current CPU
proc_id_t currentCpuId() { throw new Exception("unimplemented",__FILE__,__LINE__); }
/// loops on the available nodes (at one ot the levels 0,1 or 2)
SimpleIterator!(NumaNode) nodesAvailable() {
    throw new Exception("unimplemented",__FILE__,__LINE__); // do not implement at all, so that presence can be statically checked?
}

/// describes the topology of a machine in a simplified hierarchical way
/// starting with leaf nodes each super level adds nodes that are further away
/// there are methods to loop on subnodes or on the added nodes
interface Topology(NodeType){
    /// maximum (whole system) level
    int maxLevel();
    /// maximum number of nodes at the given level (actual nodes might be less)
    int nNodes(int level);
    /// it the given level is a partition (no overlap between the nodes)
    /// if false it might still be a partition, or not
    bool isPartition(int level);
    /// loops on the nodes at the given level
    SimpleIterator!(NodeType) nodes(int level);
    /// super node of the given node
    NodeType superNode(NumaNode node);
    /// loops on the subnodes (level of subnodes is uniform, but might be lower than node.lower-1)
    SimpleIterator!(NodeType) subNodes(NodeType node);
    /// loops on the subnodes in a random order (load balancing), if possible skipping the 
    // subnodes of the skip subnode
    SimpleIterator!(NodeType) subNodesRandom(NodeType node,NodeType skipSubnode=NodeType(-1,0));
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
    Cache nextCache(NumaNode);
    /// returns the next memory, if attachedTo.level=-1 the result is bogus (no memory found)
    Memory nextMemory(NumaNode);
    /// returns the next machine, if attachedTo.level=-1 the result is bogus (no machine found)
    Machine nextMachine(NumaNode);
    /// returns the next socket, if attachedTo.level=-1 the result is bogus (no socket found)
    Socket nextSocket(NumaNode);
}

class ExplicitTopology(NodeType): Topology!(NodeType){
    final class ArrayIterator(T):SimpleIterator!(T){
        T[] array;
        size_t pos;
        size_t left;
        this(T[] arr,size_t startIdx=0){
            array=arr;
            pos=startIdx;
            left=array.length;
        }
        T next(){
            if (left==0) throw new Exception("iterate past end",__FILE__,__LINE__);
            size_t posAtt=pos;
            ++pos;
            --left;
            if (pos==array.length) pos=0;
            return array[posAtt];
        }
        bool atEnd(){ return left==0; }
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
    SimpleIterator!(NodeType) nodes(int level){
        return new ArrayIterator!(NodeType)(levels[level].nodes);
    }
    /// super node of the given node
    NodeType superNode(NodeType node){
        assert(node.level+1<levels.length,"no super node for node at top level"); // return itself?
        return levels[node.level].superNodes[node.pos];
    }
    /// loops on the subnodes (level of subnodes is uniform, but might be 2 rather than node.level-1)
    SimpleIterator!(NodeType) subNodes(NodeType node){
        assert(node.level!=0,"no subnode of the last level"); // return an empty iterator?
        return new ArrayIterator!(NodeType)(levels[node.level].subNodes[node.pos]);
    }
    /// loops on the subnodes, but perform at least a random
    /// rotation on them and tries to avoid the subnodes of skip
    /// (thus can be used for load balancing purposes)
    SimpleIterator!(NodeType) subNodesRandom(NodeType node,NodeType skipSubnode=NodeType(-1,0)){
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

    Cache nextCache(NumaNode){ Cache res; return res; }
    Memory nextMemory(NumaNode){ Memory res; return res; }
    Machine nextMachine(NumaNode){ Machine res; return res; }
    Socket nextSocket(NumaNode){ Socket res; return res; }
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

class HwlocTopology: NumaTopology{
    hwloc_topology_t topology;
    
    struct LevelMap{
        int depth;
        bool partition;
        char[] toString(){
            return serializeToString(this);
        }
        mixin(serializeSome("",`depth|partition`));
    }
    LevelMap[] levelMapping;
    int backMapping[];
    
    class CousinIterator:SimpleIterator!(NumaNode){
        HwlocTopology topo;
        hwloc_obj_t pos;
        
        this(HwlocTopology topo,hwloc_obj_t pos){
            this.topo=topo;
            this.pos=pos;
        }
        
        NumaNode next(){
            NumaNode res;
            if (pos!is null){
                res=NumaNode(backMapping[pos.depth],pos.logical_index);
                pos=pos.next_cousin;
            }
            return res;
        }
        
        bool atEnd(){
            return pos is null;
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

    class RandomChildernIterator:SimpleIterator!(NumaNode){
        HwlocTopology topo;
        hwloc_obj_t[] childrens;
        int end;
        int pos;
        int level,depth1,depth2;
        hwloc_obj_t objPos;
        
        this(HwlocTopology topo,hwloc_obj_t[] childrens,int start,int level){
            this.topo=topo;
            this.pos=start;
            this.childrens=childrens;
            if (start==0) {
                this.end=childrens.length;
            } else {
                this.end=start-1;
            }
            this.level=level;
            if (childrens.length>0){
                depth1=childrens[0].depth;
                depth2=levelMapping[level-1].depth;
                objPos=childrens[start];
            } else {
                objPos=null;
            }
        }
        
        NumaNode next(){
            NumaNode res;
            if (objPos!is null){
                while(objPos.depth<depth2){
                    assert(objPos.arity>0);
                    objPos=objPos.first_child;
                }
                assert(objPos.depth==depth2);
                res=NumaNode(level,objPos.logical_index);
                // try advance objPos
                if (objPos.next_sibling!is null){
                    objPos=objPos.next_sibling;
                } else {
                    while (objPos.depth>depth1 && objPos.next_sibling is null){
                        objPos=objPos.father;
                    }
                    if (objPos.next_sibling!is null){
                        objPos=objPos.next_sibling;
                    } else {
                        ++pos;
                        if (pos!=end) {
                            pos=pos%childrens.length;
                            objPos=childrens[pos];
                        } else {
                            objPos=null;
                        }
                    }
                }
            }
            return res;
        }
        
        bool atEnd(){
            return objPos==null;
        }
        
        int opApply(int delegate(ref NumaNode x) dlg){
            if (objPos is null) return 0;
            while (1){
                while(objPos.depth<depth2){
                    assert(objPos.arity>0);
                    objPos=objPos.first_child;
                }
                assert(objPos.depth==depth2);
                auto n=NumaNode(level,objPos.logical_index);
                auto res=dlg(n);
                if (res!=0) return res;
                // try advance objPos
                if (objPos.next_sibling!is null){
                    objPos=objPos.next_sibling;
                } else {
                    while (objPos.depth>depth1 && objPos.next_sibling is null){
                        objPos=objPos.father;
                    }
                    if (objPos.next_sibling!is null){
                        objPos=objPos.next_sibling;
                    } else {
                        ++pos;
                        if (pos!=end) {
                            pos=pos%childrens.length;
                            objPos=childrens[pos];
                        } else {
                            break;
                        }
                    }
                }
            }
            return 0;
        }
        
        int opApply(int delegate(ref NumaNode x,ref hwloc_obj_t obj) dlg){
            if (objPos is null) return 0;
            while (1){
                while(objPos.depth<depth2){
                    assert(objPos.arity>0);
                    objPos=objPos.first_child;
                }
                assert(objPos.depth==depth2);
                auto n=NumaNode(level,objPos.logical_index);
                auto res=dlg(n,objPos);
                if (res!=0) return res;
                // try advance objPos
                if (objPos.next_sibling!is null){
                    objPos=objPos.next_sibling;
                } else {
                    while (objPos.depth>depth1 && objPos.next_sibling is null){
                        objPos=objPos.father;
                    }
                    if (objPos.next_sibling!is null){
                        objPos=objPos.next_sibling;
                    } else {
                        ++pos;
                        if (pos!=end) {
                            pos=pos%childrens.length;
                            objPos=childrens[pos];
                        } else {
                            break;
                        }
                    }
                }
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
        if (n.level==-1) throw new Exception("invalid node",__FILE__,__LINE__);
        return hwloc_get_obj_by_depth(topology,levelMapping[n.level].depth,n.pos);
    }
    /// loops on the nodes at the given level
    SimpleIterator!(NumaNode) nodes(int level){
        return new CousinIterator(this,
            hwloc_get_obj_by_depth(topology,levelMapping[level].depth,0));
    }
    /// super node of the given node
    NumaNode superNode(NumaNode node){
        assert(node.level+1<levelMapping.length,"no super node for node at top level"); // return itself?
        auto obj=hwlocObjForNumaNode(node);
        assert(obj!is null);
        auto prevDepth=levelMapping[node.level+1].depth;
        while (obj.depth>prevDepth){
            obj=obj.father;
            assert(obj!is null);
        }
        assert(obj.depth==prevDepth);
        return NumaNode(node.level+1,obj.logical_index);
    }
    /// loops on the subnodes (level of subnodes is uniform, but might be 2 rather than node.level-1)
    SimpleIterator!(NumaNode) subNodes(NumaNode node){
        assert(node.level!=0,"no subnode of the last level"); // return an empty iterator?
        auto obj=hwlocObjForNumaNode(node);
        auto nextDepth=levelMapping[node.level-1].depth;
        while (obj.depth<nextDepth-1 && obj.arity==1){
            obj=obj.first_child;
        }
        auto childrens=obj.children[0..obj.arity];
        return new RandomChildernIterator(this,childrens,0,node.level-1);
    }
    /// loops on the subnodes, but perform at least a random
    /// rotation on them and tries to avoid the subnodes of skip
    /// (thus can be used for load balancing purposes)
    /// could be better (really skip all subnodes of skip)
    SimpleIterator!(NumaNode) subNodesRandom(NumaNode node,NumaNode skipSubnode=NumaNode(-1,0)){
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
    
    Cache nextCache(NumaNode n){
        int countLeafs(hwloc_obj_t obj){
            if (obj is null) return 0;
            if (obj.first_child is null) return 1;
            int res=0;
            foreach (c;obj.children[0..obj.arity]){
                res+=countLeafs(c);
            }
            return res;
        }
        
        Cache res;
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
    
    Memory nextMemory(NumaNode n){
        Memory res;
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
    Machine nextMachine(NumaNode n){
        Machine res;
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
    Socket nextSocket(NumaNode n){
        Socket res;
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
        if (hwloc_set_cpubind(topology, &cpuset, 0)) {
            return false;
        }
        return true;
    }
}

NumaTopology defaultTopology;

static this(){
    defaultTopology=new HwlocTopology();
}

