/// basic test of the hwloc bindings
/// basically a trascription of topo-hello.c
/// which was released under the BSD license.
///
// Copyright © 2009 CNRS, INRIA, Université Bordeaux 1, 2009-2010 the blip developer group
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
module testHwloc;
version(noHwloc){
    import blip.io.Console;
    void main(){
        sout("version(noHwloc): hwloc is not used\n");
    }
} else {
import blip.bindings.hwloc.hwloc;
import tango.stdc.stdio;
version(NoTrace){} else { import blip.core.stacktrace.TraceExceptions; }

static void print_children(hwloc_topology_t topology, hwloc_obj_t obj, int depth)
{
        char[128] string;
        char[20] indent;
        indent[]=' ';
        if (depth<indent.length/2) {
            indent[2*depth]=0;
        } else {
            indent[19]=0;
        }
        int i;
        hwloc_obj_type_snprintf(string.ptr,string.length, obj, 0);
        string[string.length-1]=0;
        printf("%s%s\n",indent.ptr, string.ptr);
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
        hwloc_obj_type_snprintf(string.ptr,string.length,obj, 0);
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
            printf("level=%d:\n",depth);
                for (i = 0; i < hwloc_get_nbobjs_by_depth(topology, depth); i++) {
                        hwloc_obj_type_snprintf(string.ptr, string.length,
                                        hwloc_get_obj_by_depth(topology, depth, i), 0);
                        printf("%s\n", string.ptr);
                }
            printf("finished level%d\n",depth);
        }
        printf("end arrayStyle\n");

        /* Walk the topology with a tree style.  */
        print_children(topology, hwloc_get_root_obj(topology), 0);
        printf("end recursiveStyle\n");


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

}// version(noHwloc) else
