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
    int level;
    int pos;
    // system dependent
    int id;
    
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
        metaI.addFieldOfType!(int)("id","the id of this node (system dependent)");
    }
    ClassMetaInfo getSerializationMetaInfo(){
        return metaI;
    }
    void serial(Ser)(Ser s){
        s.field(metaI[0],level);
        s.field(metaI[1],pos);
        s.field(metaI[2],id);
    }
    void serialize(Serializer s){
        serial(s);
    }
    void unserialize(Unserializer s){
        serial(s);
    }
}

/// simple iterator
interface SimpleIterator(T){
    /// goes to the next element
    T next();
    /// true if the iterator is at the end
    bool atEnd();
    /// loop without index, has to be implemented
    int opApply(int delegate(T x) dlg);
}

/// returns the id of the current CPU
proc_id_t currentCpuId() { throw new Exception("unimplemented",__FILE__,__LINE__); }
/// loops on the available nodes (at one ot the levels 0,1 or 2)
SimpleIterator!(NumaNode) nodesAvailable() {
    throw new Exception("unimplemented",__FILE__,__LINE__); // do not implement at all, so that presence can be statically checked?
    return null;
}

/// describes the topology of a machine in a simplified hierarchical way
/// starting with leaf nodes each super level adds nodes that are further away
/// there are methods to loop on subnodes or on the added nodes
interface Topology(NodeType){
    /// maximum (whole system) level
    int maxLevel();
    /// maximum number of nodes at the given level (actual nodes might be less)
    int maxNodes(int level);
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
interface NumaTopology: Topology!(NumaNode){
    /// mask for the given node
    NodeMask maskForNode(NumaNode node);
    /// mapping from processors to nodes of level 0
    NumaNode procToNode(proc_id_t extLeaf);
    /// mapping from nodes of level 0 to processors
    proc_id_t nodeToProc(NumaNode);
    /// mapping from cpu socket to nodes of level 2
    NumaNode socketToNode(cpu_sock_t extLeaf);
    /// mapping from nodes of level 2 to cpu sockets
    cpu_sock_t nodeToSocket(NumaNode);
}

class ExplicitTopology(NodeType): Topology!(NumaNode){
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
        int opApply(int delegate(T el) loopBody){
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
        return levels.length;
    }
    /// maximum number of nodes at the given level (actual nodes might be less)
    int maxNodes(int level){
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
    NodeType superNode(NumaNode node){
        assert(node.level!=0,"no super node for node at level 0"); // return itself?
        return levels[node.level].superNodes[node.pos];
    }
    /// loops on the subnodes (level of subnodes is uniform, but might be 2 rather than node.level-1)
    SimpleIterator!(NodeType) subNodes(NodeType node){
        assert(node.level!=levels.length,"no subnode of the last level"); // return an empty iterator?
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


ExplicitTopology!(NumaNode) uniformTopology(int[] nDirectChilds){
    alias ExplicitTopology!(NumaNode).NumaLevel Level;
    int nNodesLevel=1;
    auto nLevels=nDirectChilds.length;
    Level[] levels=new Level[nLevels+1];
    int id=0;
    for (int ilevel=0;ilevel<nLevels;++ilevel){
        Level *lAtt=&(levels[nLevels-ilevel]);
        lAtt.nNodes=nNodesLevel;
        for (int inode=0;inode<nNodesLevel;++inode){
            lAtt.nodes[inode].level=nLevels-ilevel;
            lAtt.nodes[inode].pos=inode;
            lAtt.nodes[inode].id=++id;
            
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
        lAtt.nodes[inode].id=++id;
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
    return new ExplicitTopology!(NumaNode)(levels);
}
