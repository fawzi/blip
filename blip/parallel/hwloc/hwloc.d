/*
 * Bindings to hwloc lib, contains code from the headers of hwloc that is
 *
 * Copyright © 2009 CNRS, INRIA, Université Bordeaux 1
 * released under the BSD license.
 */
module blip.parallel.hwloc.hwloc;
import tango.core.BitVector;
import tango.stdc.config;
import tango.stdc.stdlib:abort;
import blip.parallel.hwloc.cpuset;
public import blip.parallel.hwloc.cpuset: hwloc_cpuset_t;

version(Windows){
    import tango.sys.win32.Types: HANDLE;
    alias HANDLE hwloc_pid_t;
    alias HANDLE hwloc_thread_t;
} else {
    import tango.stdc.posix.sys.types: pid_t,pthread_t;
    alias pid_t hwloc_pid_t;
    alias pthread_t hwloc_thread_t;
}

/** \file
 * \brief The hwloc API.
 */


/** \brief Topology context
 *
 * To be initialized with hwloc_topology_init() and built with hwloc_topology_load().
 */
typedef void * hwloc_topology_t;

/** \defgroup hwlocality_types Topology Object Types
 * @{
 */

/** \brief Type of topology object.
 *
 * Do not rely on the ordering of the values as new ones may be defined in the
 * future!  If you need to compare types, use hwloc_compare_types() instead.
 */
enum HWLOC_OBJ {
  SYSTEM, /**< \brief Whole system (may be a cluster of machines).
    * The whole system that is accessible to hwloc.
    * That may comprise several machines in SSI systems
    * like Kerrighed.
    */
  MACHINE,    /**< \brief Machine.
    * A set of processors and memory with cache
    * coherency.
    */
  NODE,   /**< \brief NUMA node.
    * A set of processors around memory which the
    * processors can directly access.
    */
  SOCKET, /**< \brief Socket, physical package, or chip.
    * In the physical meaning, i.e. that you can add
    * or remove physically.
    */
  CACHE,  /**< \brief Data cache.
    * Can be L1, L2, L3, ...
    */
  CORE,   /**< \brief Core.
    * A computation unit (may be shared by several
    * logical processors).
    */
  PROC,   /**< \brief (Logical) Processor.
    * An execution unit (may share a core with some
    * other logical processors, e.g. in the case of
    * an SMT core).
    *
    * Objects of this kind are always reported and can
    * thus be used as fallback when others are not.
    */
  
  MISC,   /**< \brief Miscellaneous objects.
    * Objects which do not fit in the above but are
    * detected by hwloc and are useful to take into
    * account for affinity. For instance, some OSes
    * expose their arbitrary processors aggregation this
    * way.
    */
}
alias HWLOC_OBJ hwloc_obj_type_t;

///** \brief Maximal value of an object type */
//enum {HWLOC_OBJ_TYPE_MAX=hwloc_obj_type_t.max}

/** \brief Compare the depth of two object types
 *
 * Types shouldn't be compared as they are, since newer ones may be added in
 * the future.  This function returns less than, equal to, or greater than zero
 * if \p type1 is considered to be respectively higher than, equal to, or deeper
 * than \p type2 in the hierarchy.
 *
 * \note that HWLOC_OBJ_SYSTEM will always be the highest, and
 * HWLOC_OBJ_PROC will always be the deepest.
 */
extern(C) int hwloc_compare_types (hwloc_obj_type_t type1, hwloc_obj_type_t type2);

/** @} */



/** \defgroup hwlocality_objects Topology Objects
 * @{
 */

 /** \brief Object type-specific Attributes */
 union hwloc_obj_attr_u {
   /** \brief Cache-specific Object Attributes */
   struct hwloc_cache_attr_s {
     c_ulong memory_kB;          /**< \brief Size of cache */
     uint depth;           /**< \brief Depth of cache */
   }
   hwloc_cache_attr_s cache;
   /** \brief Node-specific Object Attributes */
   struct hwloc_memory_attr_s {
     c_ulong memory_kB;          /**< \brief Size of memory node */
     c_ulong huge_page_free;     /**< \brief Number of available huge pages */
   };
   hwloc_memory_attr_s node;
   /**< \brief Machine-specific Object Attributes */
   struct hwloc_machine_attr_s {
     char *dmi_board_vendor;       /**< \brief DMI board vendor name */
     char *dmi_board_name;         /**< \brief DMI board model name */
     c_ulong memory_kB;          /**< \brief Size of memory node */
     c_ulong huge_page_free;     /**< \brief Number of available huge pages */
     c_ulong huge_page_size_kB;      /**< \brief Size of huge pages */
   }
   hwloc_machine_attr_s machine;
   /**< \brief System-specific Object Attributes */
   hwloc_machine_attr_s system;
   /** \brief Misc-specific Object Attributes */
   struct hwloc_misc_attr_s {
     uint depth;           /**< \brief Depth of misc object */
   }
   hwloc_misc_attr_s misc;
}
   
/** \brief Structure of a topology object
 *
 * Applications mustn't modify any field except ::userdata .
 */
struct hwloc_obj {
  /* physical information */
  hwloc_obj_type_t type;        /**< \brief Type of object */
  int os_index;          /**< \brief OS-provided physical index number */
  char *name;               /**< \brief Object description if any */

  /** \brief Object type-specific Attributes */
  hwloc_obj_attr_u *attr;

  /* global position */
  uint depth;           /**< \brief Vertical index in the hierarchy */
  uint logical_index;       /**< \brief Horizontal index in the whole list of similar objects,
                     * could be a "cousin_rank" since it's the rank within the "cousin" list below */
  hwloc_obj *next_cousin;    /**< \brief Next object of same type */
  hwloc_obj *prev_cousin;    /**< \brief Previous object of same type */

  /* father */
  hwloc_obj *father;     /**< \brief Father, \c NULL if root (system object) */
  uint sibling_rank;        /**< \brief Index in father's \c children[] array */
  hwloc_obj *next_sibling;   /**< \brief Next object below the same father*/
  hwloc_obj *prev_sibling;   /**< \brief Previous object below the same father */

  /* children */
  uint arity;           /**< \brief Number of children */
  hwloc_obj **children;      /**< \brief Children, \c children[0 .. arity -1] */
  hwloc_obj *first_child;    /**< \brief First child */
  hwloc_obj *last_child;     /**< \brief Last child */

  /* misc */
  void *userdata;           /**< \brief Application-given private data pointer, initialized to \c NULL, use it as you wish */

  /* cpuset */
  hwloc_cpuset_t cpuset;        /**< \brief CPUs covered by this object */

  int os_level;          /**< \brief OS-provided physical level */
}

alias hwloc_obj * hwloc_obj_t;

/** @} */



/** \defgroup hwlocality_creation Create and Destroy Topologies
 * @{
 */

/** \brief Allocate a topology context.
 *
 * \param[out] topologyp is assigned a pointer to the new allocated context.
 *
 * \return 0 on success, -1 on error.
 */
extern(C) int hwloc_topology_init (hwloc_topology_t *topologyp);

/** \brief Build the actual topology
 *
 * Build the actual topology once initialized with hwloc_topology_init() and
 * tuned with ::hwlocality_configuration routine.
 * No other routine may be called earlier using this topology context.
 *
 * \param topology is the topology to be loaded with objects.
 *
 * \return 0 on success, -1 on error.
 *
 * \sa hwlocality_configuration
 */
extern(C) int hwloc_topology_load(hwloc_topology_t topology);

/** \brief Terminate and free a topology context
 *
 * \param topology is the topology to be freed
 */
extern(C) void hwloc_topology_destroy (hwloc_topology_t topology);

/** \brief Run internal checks on a topology structure
 *
 * \param topology is the topology to be checked
 */
extern(C) void hwloc_topology_check(hwloc_topology_t topology);

/** @} */



/** \defgroup hwlocality_configuration Configure Topology Detection
 *
 * These functions can optionally be called between hwloc_topology_init() and
 * hwloc_topology_load() to configure how the detection should be performed,
 * e.g. to ignore some objects types, define a synthetic topology, etc.
 *
 * If none of them is called, the default is to detect all the objects of the
 * machine that the caller is allowed to access.
 *
 * @{
 */

/** \brief Ignore an object type.
 *
 * Ignore all objects from the given type.
 * The top-level type HWLOC_OBJ_SYSTEM and bottom-level type HWLOC_OBJ_PROC may
 * not be ignored.
 */
extern(C) int hwloc_topology_ignore_type(hwloc_topology_t topology, hwloc_obj_type_t type);

/** \brief Ignore an object type if it does not bring any structure.
 *
 * Ignore all objects from the given type as long as they do not bring any structure:
 * Each ignored object should have a single children or be the only child of its father.
 * The top-level type HWLOC_OBJ_SYSTEM and bottom-level type HWLOC_OBJ_PROC may
 * not be ignored.
 */
extern(C) int hwloc_topology_ignore_type_keep_structure(hwloc_topology_t topology, hwloc_obj_type_t type);

/** \brief Ignore all objects that do not bring any structure.
 *
 * Ignore all objects that do not bring any structure:
 * Each ignored object should have a single children or be the only child of its father.
 */
extern(C) int hwloc_topology_ignore_all_keep_structure(hwloc_topology_t topology);

/** \brief Flags to be set onto a topology context before load.
 *
 * Flags should be given to hwloc_topology_set_flags().
 */
enum HWLOC_TOPOLOGY_FLAG {
  /* \brief Detect the whole system, ignore reservations that may have been setup by the administrator.
   *
   * Gather all resources, even if some were disabled by the administrator.
   * For instance, ignore Linux Cpusets and gather all processors and memory nodes.
   */
  WHOLE_SYSTEM = (1<<0),

  /* \brief Assume that the selected backend provides the topology for the
   * system on which we are running.
   *
   * This forces is_thissystem to 1, i.e. makes hwloc assume that the selected
   * backend provides the topology for the system on which we are running, even
   * if it is not the OS-specific backend but the XML backend for instance.
   * This means making the binding functions actually call the OS-specific
   * system calls and really do binding, while the XML backend would otherwise
   * provide empty hooks just returning success.
   *
   * This can be used for efficiency reasons to first detect the topology once,
   * save it to an XML file, and quickly reload it later through the XML
   * backend, but still having binding functions actually do bind.
   */
  IS_THISSYSTEM = (1<<1),
}
alias HWLOC_TOPOLOGY_FLAG hwloc_topology_flags_e;

/** \brief Set OR'ed flags to non-yet-loaded topology.
 *
 * Set a OR'ed set of hwloc_topology_flags_e onto a topology that was not yet loaded.
 */
extern(C) int hwloc_topology_set_flags (hwloc_topology_t topology, c_ulong flags);

/** \brief Change the file-system root path when building the topology from sysfs/procfs.
 *
 * On Linux system, use sysfs and procfs files as if they were mounted on the given
 * \p fsroot_path instead of the main file-system root.
 * Not using the main file-system root causes hwloc_topology_is_thissystem field
 * to return 0.
 *
 * \note For conveniency, this backend provides empty binding hooks which just
 * return success.  To have hwloc still actually call OS-specific hooks, the
 * HWLOC_TOPOLOGY_FLAG_IS_THISSYSTEM has to be set to assert that the loaded
 * file is really the underlying system.
 */
extern(C) int hwloc_topology_set_fsroot(hwloc_topology_t topology, char * fsroot_path);

/** \brief Enable synthetic topology.
 *
 * Gather topology information from the given \p description
 * which should be a comma separated string of numbers describing
 * the arity of each level.
 * Each number may be prefixed with a type and a colon to enforce the type
 * of a level.
 *
 * \note For conveniency, this backend provides empty binding hooks which just
 * return success.
 */
extern(C) int hwloc_topology_set_synthetic(hwloc_topology_t topology, char * description);

/** \brief Enable XML-file based topology.
 *
 * Gather topology information the XML file given at \p xmlpath.
 * This file may have been generated earlier with lstopo file.xml.
 *
 * \note For conveniency, this backend provides empty binding hooks which just
 * return success.  To have hwloc still actually call OS-specific hooks, the
 * HWLOC_TOPOLOGY_FLAG_IS_THISSYSTEM has to be set to assert that the loaded
 * file is really the underlying system.
 */
extern(C) int hwloc_topology_set_xml(hwloc_topology_t topology, char * xmlpath);

/** @} */



/** \defgroup hwlocality_information Get some Topology Information
 * @{
 */

/** \brief Get the depth of the hierachical tree of objects.
 *
 * This is the depth of HWLOC_OBJ_PROC objects plus one.
 */
extern(C) uint hwloc_topology_get_depth(hwloc_topology_t  topology);

/** \brief Returns the depth of objects of type \p type.
 *
 * If no object of this type is present on the underlying architecture, or if
 * the OS doesn't provide this kind of information, the function returns
 * HWLOC_TYPE_DEPTH_UNKNOWN.
 *
 * If type is absent but a similar type is acceptable, see also
 * hwloc_get_type_or_below_depth() and hwloc_get_type_or_above_depth().
 */
extern(C) int hwloc_get_type_depth (hwloc_topology_t topology, hwloc_obj_type_t type);
enum HWLOC_TYPE_DEPTH {
    UNKNOWN=-1, /**< \brief No object of given type exists in the topology. */
    MULTIPLE=-2, /**< \brief Objects of given type exist at different depth in the topology. */
}

/** \brief Returns the type of objects at depth \p depth. */
extern(C) hwloc_obj_type_t hwloc_get_depth_type (hwloc_topology_t topology, uint depth);

/** \brief Returns the width of level at depth \p depth */
extern(C) uint hwloc_get_nbobjs_by_depth (hwloc_topology_t topology, uint depth);

/** \brief Returns the width of level type \p type
 *
 * If no object for that type exists, 0 is returned.
 * If there are several levels with objects of that type, -1 is returned.
 */
int hwloc_get_nbobjs_by_type (hwloc_topology_t topology, hwloc_obj_type_t type)
{
    int depth = hwloc_get_type_depth(topology, type);
    if (depth == HWLOC_TYPE_DEPTH.UNKNOWN)
        return 0;
    if (depth == HWLOC_TYPE_DEPTH.MULTIPLE)
        return -1; /* FIXME: agregate nbobjs from different levels? */
    return hwloc_get_nbobjs_by_depth(topology, depth);
}

/** \brief Does the topology context come from this system?
 *
 * \return 1 if this topology context was built using the system
 * running this program.
 * \return 0 instead (for instance if using another file-system root,
 * a XML topology file, or a synthetic topology).
 */
extern(C) int hwloc_topology_is_thissystem(hwloc_topology_t topology);

/** @} */



/** \defgroup hwlocality_traversal Retrieve Objects
 * @{
 */

/** \brief Returns the topology object at index \p index from depth \p depth */
extern(C) hwloc_obj_t hwloc_get_obj_by_depth (hwloc_topology_t topology, uint depth, uint index);

/** \brief Returns the topology object at index \p index with type \p type
 *
 * If no object for that type exists, \c NULL is returned.
 * If there are several levels with objects of that type, \c NULL is returned
 * and ther caller may fallback to hwloc_get_obj_by_depth().
 */
hwloc_obj_t hwloc_get_obj_by_type (hwloc_topology_t topology, hwloc_obj_type_t type, uint index)
{
  int depth = hwloc_get_type_depth(topology, type);
  if (depth == HWLOC_TYPE_DEPTH.UNKNOWN)
    return null;
  if (depth == HWLOC_TYPE_DEPTH.MULTIPLE)
    return null;
  return hwloc_get_obj_by_depth(topology, depth, index);
}

/** @} */



/** \defgroup hwlocality_conversion Object/String Conversion
 * @{
 */

/** \brief Return a stringified topology object type */
extern(C) char * hwloc_obj_type_string (hwloc_obj_type_t type);

/** \brief Return an object type from the string */
extern(C) hwloc_obj_type_t hwloc_obj_type_of_string (char * string);

/** \brief Stringify a given topology object into a human-readable form.
 *
 * \return how many characters were actually written (not including the ending \\0). */
extern(C) int hwloc_obj_snprintf(char * string, size_t size,
                 hwloc_topology_t topology, hwloc_obj_t obj,
                 char * indexprefix, int verbose);

/** \brief Stringify the cpuset containing a set of objects.
 *
 * \return how many characters were actually written (not including the ending \\0). */
extern(C) int hwloc_obj_cpuset_snprintf(char * str, size_t size, size_t nobj, hwloc_obj_t * objs);

/** @} */



/** \defgroup hwlocality_binding Binding
 *
 * It is often useful to call hwloc_cpuset_singlify() first so that a single CPU
 * remains in the set. This way, the process will not even migrate between
 * different CPUs. Some OSes also only support that kind of binding.
 *
 * \note Some OSes do not provide all ways to bind processes, threads, etc and
 * the corresponding binding functions may fail. ENOSYS is returned when it is
 * not possible to bind the requested kind of object processes/threads). EXDEV
 * is returned when the requested cpuset can not be enforced (e.g. some systems
 * only allow one CPU, and some other systems only allow one NUMA node)
 *
 * The most portable version that
 * should be preferred over the others, whenever possible, is
 *
 * \code
 * hwloc_set_cpubind(topology, set, 0),
 * \endcode
 *
 * as it just binds the current program, assuming it is monothread, or
 *
 * \code
 * hwloc_set_cpubind(topology, set, HWLOC_CPUBIND.THREAD),
 * \endcode
 *
 * which binds the current thread of the current program (which may be
 * multithreaded).
 *
 * \note To unbind, just call the binding function with either a full cpuset or
 * a cpuset equal to the system cpuset.
 * @{
 */

/** \brief Process/Thread binding policy.
 *
 * These flags can be used to refine the binding policy.
 *
 * The default (0) is to bind the current process, assumed to be mono-thread,
 * in a non-strict way.  This is the most portable way to bind as all OSes
 * usually provide it.
 *
 * \note Depending on OSes and implementations, strict binding (i.e. the
 * thread/process will really never be scheduled outside of the cpuset) may not
 * be possible, not be allowed, only used as a hint when no load balancing is
 * needed, etc.  If strict binding is required, the strict flag should be set,
 * and the function will fail if strict binding is not possible or allowed.
 *
 */
enum HWLOC_CPUBIND{
  PROCESS = (1<<0),   /**< \brief Bind all threads of the current multithreaded process.
                      * This may not be supported by some OSes (e.g. Linux). */
  THREAD = (1<<1),        /**< \brief Bind current thread of current process */
  STRICT = (1<<2),        /**< \brief Request for strict binding from the OS
                     * Note that strict binding may not be
                     * allowed for administrative reasons,
                     * and the binding function will fail
                     * in that case.
                     */
}
alias HWLOC_CPUBIND hwloc_cpubind_policy_t;

/** \brief Bind current process or thread on cpus given in cpuset \p set
 */
extern(C) int hwloc_set_cpubind(hwloc_topology_t topology, hwloc_cpuset_t set,
                int policy);

/** \brief Bind a process \p pid on cpus given in cpuset \p set
 *
 * \note hwloc_pid_t is pid_t on unix platforms, and HANDLE on native Windows
 * platforms
 *
 * \note HWLOC_CPUBIND.THREAD can not be used in \p policy.
 */
extern(C) int hwloc_set_proc_cpubind(hwloc_topology_t topology, hwloc_pid_t pid, hwloc_cpuset_t set, int policy);

/** \brief Bind a thread \p tid on cpus given in cpuset \p set
 *
 * \note hwloc_thread_t is pthread_t on unix platforms, and HANDLE on native
 * Windows platforms
 *
 * \note HWLOC_CPUBIND.PROCESS can not be used in \p policy.
 */
extern(C) int hwloc_set_thread_cpubind(hwloc_topology_t topology, hwloc_thread_t tid, hwloc_cpuset_t set, int policy);

/** @} */

//------ topology/helper: hwloc/helper.h

/** \defgroup hwlocality_helper_types Object Type Helpers
 * @{
 */

/** \brief Returns the depth of objects of type \p type or below
 *
 * If no object of this type is present on the underlying architecture, the
 * function returns the depth of the first "present" object typically found
 * inside \p type.
 */
uint hwloc_get_type_or_below_depth (hwloc_topology_t topology, hwloc_obj_type_t type)
{
  int depth = hwloc_get_type_depth(topology, type);

  if (depth != HWLOC_TYPE_DEPTH.UNKNOWN)
    return depth;

  /* find the highest existing level with type order >= */
  for(depth = hwloc_get_type_depth(topology, HWLOC_OBJ.PROC); ; depth--)
    if (hwloc_compare_types(hwloc_get_depth_type(topology, depth), type) < 0)
      return depth+1;

  /* Shouldn't ever happen, as there is always a SYSTEM level with lower order and known depth.  */
  abort();
  return 0;
}

/** \brief Returns the depth of objects of type \p type or above
 *
 * If no object of this type is present on the underlying architecture, the
 * function returns the depth of the first "present" object typically
 * containing \p type.
 */
uint hwloc_get_type_or_above_depth (hwloc_topology_t topology, hwloc_obj_type_t type)
{
  int depth = hwloc_get_type_depth(topology, type);

  if (depth != HWLOC_TYPE_DEPTH.UNKNOWN)
    return depth;

  /* find the lowest existing level with type order <= */
  for(depth = 0; ; depth++)
    if (hwloc_compare_types(hwloc_get_depth_type(topology, depth), type) > 0)
      return depth-1;

  /* Shouldn't ever happen, as there is always a PROC level with higher order and known depth.  */
  abort();
  return 0;
}

/** @} */

/** \brief Returns the top-object of the topology-tree. Its type is ::HWLOC_OBJ_SYSTEM. */
hwloc_obj_t hwloc_get_system_obj (hwloc_topology_t topology)
{
  return hwloc_get_obj_by_depth (topology, 0, 0);
}
