module testHwloc;
/* topo-hello.c */
import blip.parallel.hwloc.hwloc;
import tango.stdc.stdio;
version(NoTrace){} else { import tango.core.stacktrace.TraceExceptions; }

static void print_children(hwloc_topology_t topology, hwloc_obj_t obj, int depth)
{
        char string[128];
        int i;

        hwloc_obj_snprintf(string.ptr,string.length, topology, obj, "#", 0);
        printf("%*s%s\n", 2*depth, "               ".ptr, string.ptr);
        for (i = 0; i < obj.arity; i++)
                print_children(topology, obj.children[i], depth + 1);
}

int main()
{
        /* Topology object */
        hwloc_topology_t topology;

        /* Allocate and initialize topology object.  */
        hwloc_topology_init(&topology);

        /* ... Optionally, put detection configuration here to e.g. ignore some
           objects types, define a synthetic topology, etc....  The default is
           to detect all the objects of the machine that the caller is allowed
           to access.
           See Configure Topology Detection.  */

        /* Perform the topology detection.  */
        hwloc_topology_load(topology);


        /* Optionally, get some additional topology information
         * in case we need the topology depth later.
         */
        uint topo_depth=hwloc_topology_get_depth(topology);

    void prObj(hwloc_obj_t obj){
        char[128] string;
        hwloc_obj_snprintf(string.ptr,string.length, topology, obj, "#", 0);
        printf("%*s%s\n", 4, "               ".ptr, string.ptr);
    }
    auto mObj=hwloc_get_obj_by_depth(topology,1,0);
    printf("mObj:");
    prObj(mObj);
    printf("childrens:");
    for (int ichild=0;ichild<mObj.arity;++ichild){
        printf("<ichild %d\n",ichild);
        prObj(mObj.children[ichild]);
        for (int jchild=0;jchild<mObj.children[ichild].arity;++jchild){
            printf("jchild %d\n",jchild);
            prObj(mObj.children[ichild].children[jchild]);
        }
        printf(">\n");
    }
    printf("\ndone\n");

        /* Walk the topology with an array style, from level 0 (always the
         * system level) to the lowest level (always the proc level). */
        int depth, i;
        char string[128];
        for (depth = 0; depth < topo_depth; depth++) {
                for (i = 0; i < hwloc_get_nbobjs_by_depth(topology, depth); i++) {
                        hwloc_obj_snprintf(string.ptr, string.length, topology,
                                        hwloc_get_obj_by_depth(topology, depth, i), "#", 0);
                        printf("%s\n", string.ptr);
                }
        }

        /* Walk the topology with a tree style.  */
        print_children(topology, hwloc_get_system_obj(topology), 0);


        /* Print the number of sockets.  */
        depth = hwloc_get_type_depth(topology, HWLOC_OBJ.SOCKET);
        if (depth == HWLOC_TYPE_DEPTH.UNKNOWN)
                printf("The number of sockets is unknown\n");
        else
                printf("%u socket(s)\n", hwloc_get_nbobjs_by_depth(topology, depth));


        /* Find out where cores are, or else smaller sets of CPUs if the OS
         * doesn't have the notion of core. */
        depth = hwloc_get_type_or_below_depth(topology, HWLOC_OBJ.CORE);

        /* Get last one.  */
        hwloc_obj_t obj = hwloc_get_obj_by_depth(topology, depth, hwloc_get_nbobjs_by_depth(topology, depth) - 1);
        if (!obj)
                return 0;

        /* Get its cpuset.  */
        /* Get only one logical processor (in case the core is SMT/hyperthreaded).  */
        hwloc_cpuset_t cpuset = obj.cpuset.singlify();

        /* And try to bind ourself there.  */
        if (hwloc_set_cpubind(topology, cpuset, 0)) {
                auto s=obj.cpuset.toString();
                printf("Couldn't bind to cpuset %.*s\n", s.length,s.ptr);
        }


        /* Destroy topology object.  */
        hwloc_topology_destroy(topology);

        return 0;
}
